defmodule Thrift.Binary.Framed.ProtocolHandler do
  @moduledoc """
  A GenServer that accepts connections on a server and processes the thrift messages.
  """

  alias Thrift.{
    Protocol,
    TApplicationException
  }
  require Logger

  @spec start_link(reference, pid, module, {module, module}) :: GenServer.on_start
  def start_link(ref, socket, transport, {server_module, handler_module}) do
    pid = spawn_link(__MODULE__, :init, [ref, socket, transport, server_module, handler_module])
    {:ok, pid}
  end

  def init(ref, socket, transport, server_module, handler_module) do
    :ok = :ranch.accept_ack(ref)
    transport.setopts(socket, packet: 4)

    do_thrift_call(transport, socket, server_module, handler_module)
  end

  @call 1
  @reply 2

  defp do_thrift_call(transport, socket, server_module, handler_module) do
    case transport.recv(socket, 0, 20_000) do
      {:ok, message} ->
        case message do
          <<128, 1, 0, @call, 4::32, "ping", seq_id::32, 0>> ->
            data = <<128, 1, 0, @reply, 4::32, "ping", seq_id::32, 2, 0::16, 1, 0>>
            :ok = transport.send(socket, data)
            do_thrift_call(transport, socket, server_module, handler_module)
          _ ->
            parsed_response = Protocol.Binary.deserialize(:message_begin, message)
            thrift_response = handle_thrift_message(parsed_response, server_module, handler_module)

            case thrift_response do
              {:ok, :reply, thrift_data} ->
                :ok = transport.send(socket, thrift_data)
                do_thrift_call(transport, socket, server_module, handler_module)

              {:error, {:server_error, thrift_data}} ->
                :ok = transport.send(socket, thrift_data)
                exit({:shutdown, :server_error})

              {:error, _} = err ->
                Logger.info("Thrift call failed: #{inspect err}")
                :ok = transport.close(socket)
            end

        end
    end

    # thrift_response  = with({:ok, message}      <- transport.recv(socket, 0, 20_000),
    #                         parsed_response     <- Protocol.Binary.deserialize(:message_begin, message)) do

    #   handle_thrift_message(parsed_response, server_module, handler_module)
    # end

  # def deserialize(:message_begin, <<1::size(1), 1::size(15), _::size(8),
  #                 0::size(5), message_type::size(3),
  #                 name_size::32-signed, name::binary-size(name_size), sequence_id::32-signed, rest::binary>>) do
  #   {:ok, {to_message_type(message_type), sequence_id, name, rest}}
  # end
  end

  def handle_thrift_message({:ok, {:call, sequence_id, name, args_binary}}, server_module, handler_module) do
    case server_module.handle_thrift(String.to_existing_atom(name), args_binary, handler_module) do
      {:reply, serialized_reply} ->
        message = Protocol.Binary.serialize(:message_begin, {:reply, sequence_id, name})

        {:ok, :reply, [message | serialized_reply]}

      {:server_error, %TApplicationException{} = exc} ->
        message = Protocol.Binary.serialize(:message_begin, {:exception, sequence_id, name})
        serialized_exception = Protocol.Binary.serialize(:application_exception, exc)

        {:error, {:server_error, [message |  serialized_exception]}}

      :noreply ->
        message = Protocol.Binary.serialize(:message_begin, {:reply, sequence_id, name})

        {:ok, :reply, [message | <<0>>]}
    end

  end

  def handle_thrift_message({:ok, {:oneway, _seq_id, name, args_binary}}, server_module, handler_module) do
    spawn(server_module, :handle_thrift, [name, args_binary, handler_module])
    {:ok, :reply, <<0>>}
  end

  def handle_thrift_message({:error, msg} = err, _, _) do
    Logger.warn("Could not decode Thrift message: #{inspect msg}")
    err
  end
end
