# defmodule Zambezi.Producers.StreamView do
#   @moduledoc """
#   We store multiple events in SQS messages. This module turns these chunks into a stream
#   so that GenStage can pull from it.

#   Items returned from this stage are wrapped in the `AckableMessage` struct, and when they're
#   delivered to their final resting place, they can be acked and removed from the purview of the
#   streamerizer.

#   Additionally, each SQS message has a timeout in it, and when that timeout passes, any unacked
#   messages are sent to an error queue for processing.
#   """

#   @initial_delay_ms 50
#   @max_delay_ms 500
#   @in_flight_batch_count Application.get_env(:zambezi, :in_flight_batch_count)

#   alias Experimental.GenStage
#   alias Zambezi.Producers.StreamView.BatchMonitor
#   use GenStage

#   defmodule State do
#     defstruct source_queue_spec: nil,
#     failure_queue_spec: nil,
#     messages: [],
#     batch_ttl_ms: 5000,
#     retry_strategy: nil,
#     name: nil,
#     in_flight_batches: 0,
#     extra_demand: 0


#     def new(name, source_queue_spec, failure_queue_spec, batch_ttl_ms, retry_strategy) do
#       %State{
#         name: name,
#         source_queue_spec: source_queue_spec,
#         failure_queue_spec: failure_queue_spec,
#         retry_strategy: retry_strategy,
#         batch_ttl_ms: batch_ttl_ms,
#       }
#     end

#     def decrement_in_flight(%State{in_flight_batches: in_flight}=state) do
#       %State{state | in_flight_batches: in_flight - 1}
#     end

#     def increment_in_flight(%State{in_flight_batches: in_flight}=state) do
#       %State{state | in_flight_batches: in_flight + 1}
#     end
#   end

#   def init(opts) do
#     source_queue_spec = Keyword.fetch!(opts, :source_queue_spec)
#     batch_ttl_ms = Keyword.get(opts, :batch_timeout_ms, 5000)
#     failure_queue = Keyword.fetch!(opts, :failure_queue_spec)
#     retry_strategy = Keyword.fetch!(opts, :retry_strategy)
#     name = Keyword.get(opts, :name, "stream_view")

#     {:producer, State.new(name, source_queue_spec, failure_queue, batch_ttl_ms, retry_strategy)}
#   end

#   def start_link(opts) do
#     name = Keyword.get(opts, :name)
#     GenStage.start_link(__MODULE__, opts, name: name)
#   end

#   def batch_ready(stream_view_pid, messages) do
#     GenStage.cast(stream_view_pid, {:batch_ready, messages})
#   end

#   def handle_demand(demand, state=%State{}) do
#     {state, demanded} = state
#     |> request_more_batches
#     |> take_demand(demand)

#     {:noreply, demanded, state}
#   end

#   def handle_info({:DOWN, _, _, _, _}, state) do
#     {:noreply, [], State.decrement_in_flight(state)}
#   end

#   def handle_call({:complete, message, success_metrics}, _from, state) do

#     log_success_metrics(success_metrics, state.name)
#     state.retry_strategy.delete(state.source_queue_spec, message)

#     {:reply, :ok, [], State.decrement_in_flight(state)}
#   end

#   def handle_call({:message_failure, original_message, failed_messages, success_metrics}, _from, state) do
#     Elixometer.update_spiral("#{state.name}_batch_failures", Enum.count(failed_messages))
#     log_success_metrics(success_metrics, state.name)

#     state.retry_strategy.handle_failed_message(state.source_queue_spec,
#                                                state.failure_queue_spec,
#                                                original_message,
#                                                failed_messages)

#     {:reply, :ok, [], State.decrement_in_flight(state)}
#   end

#   def handle_cast({:additional_demand, delay_ms}, %State{}=state) do
#     new_delay = min(delay_ms * 2, @max_delay_ms)

#     {state, demanded} = state
#     |> request_more_batches(new_delay)
#     |> take_demand

#     {:noreply, demanded, state}
#   end

#   def handle_cast({:new_batch, sqs_message}, %State{}=state) do
#     {:ok, batch_monitor} = BatchMonitor.start_link(self, sqs_message, state.batch_ttl_ms)

#     {new_state, demanded} = state
#     |> request_more_batches
#     |> take_demand

#     {:noreply, demanded, new_state}
#   end

#   def handle_cast({:batch_ready, messages}, %State{}=state) do
#     new_state = %State{state |
#                        messages: state.messages ++ messages,
#                        in_flight_batches: state.in_flight_batches + 1}


#     {new_state, demanded} = new_state
#     |> request_more_batches
#     |> take_demand

#     {:noreply, demanded, new_state}
#   end

#   def handle_cast({:fetch_batch, delay}, %State{in_flight_batches: in_flight}=state)
#   when in_flight < @in_flight_batch_count do
#     stream_view = self
#     spawn(fn ->
#       case next_message(state) do
#         {:error, :queue_is_empty} ->
#           message =  {:additional_demand, delay}
#           :timer.apply_after(delay, GenStage, :cast, [stream_view, message])
#           {state, []}

#         {:ok, message} ->
#           GenStage.cast(stream_view, {:new_batch, message})
#       end
#     end)

#     {new_state, demanded} = take_demand(state)
#     {:noreply, demanded, new_state}
#   end

#   def handle_cast({:fetch_batch, _delay}, state) do
#     {state, demanded} = state
#     |> request_more_batches
#     |> take_demand

#     {:noreply, demanded, state}
#   end

#   defp take_demand(%State{}=state) do
#     take_demand(state, 0)
#   end

#   defp take_demand(%State{}=state, additional_demand) do
#     total_demand = state.extra_demand + additional_demand
#     {demanded, rest} = Enum.split(state.messages, total_demand)
#     remaining_demand = (total_demand - Enum.count(demanded))

#     if remaining_demand > 0 do
#       Elixometer.update_spiral("#{state.name}.unmet_demand", 1)
#     end

#     {%State{state | messages: rest,
#             extra_demand: remaining_demand}, demanded}
#   end

#   defp request_more_batches(state=%State{}, delay \\ @initial_delay_ms) do

#     if state.in_flight_batches <= @in_flight_batch_count do
#       GenStage.cast(self, {:fetch_batch, delay})
#     end

#     state
#   end

#   defp next_message(%State{}=state) do
#     case state.retry_strategy.dequeue(state.source_queue_spec,
#                                       wait_time_seconds: 1,
#                                       attribute_names: :all,
#                                       message_attribute_names: :all) do
#       {:ok, _msg}=success ->
#         success

#       {:error, _reason}=err ->
#         Elixometer.update_spiral("#{state.name}.queue_empty", 1)
#         err
#     end
#   end

#   defp log_success_metrics({success_count, failure_count}, name) do
#     Elixometer.update_spiral("#{name}_successes", success_count)
#     Elixometer.update_spiral("#{name}_failures", failure_count)
#   end
# end