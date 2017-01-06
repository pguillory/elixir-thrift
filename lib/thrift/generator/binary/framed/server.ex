defmodule Thrift.Generator.Binary.Framed.Server do
  @moduledoc false
  alias Thrift.Generator.{
    Service,
    Utils
  }
  alias Thrift.Parser.FileGroup
  alias Thrift.Parser.Models.Function

  def generate(service_module, service, file_group) do
    functions = service.functions
    |> Map.values
    |> Enum.map(&generate_handler_function(file_group, service_module, &1))

    quote do
      defmodule Binary.Framed.Server do
        @moduledoc false
        require Logger

        alias Thrift.Binary.Framed.Server, as: ServerImpl
        defdelegate stop(name), to: ServerImpl

        def start_link(handler_module, port, opts) do
          ServerImpl.start_link(__MODULE__, port, handler_module, opts)
        end

        unquote_splicing(functions)
      end
    end
  end

  # def generate_handler_function(file_group, service_module, %Function{params: []} = function) do
  #   fn_name = Atom.to_string(function.name)
  #   handler_fn_name = Utils.underscore(function.name)
  #   response_module = Module.concat(service_module, Service.module_name(function, :response))

  #   quote do
  #     def handle_thrift(unquote(fn_name), _binary_data, handler_module) do
  #       try do
  #         handler_module.unquote(handler_fn_name)()
  #       rescue
  #         unquote(rescue_blocks(function, file_group, response_module))
  #       catch
  #         unquote(catch_block)
  #       else
  #         unquote(else_block(function, response_module))
  #       end
  #     end
  #   end
  # end
  def generate_handler_function(file_group, service_module, function) do
    # fn_name = Atom.to_string(function.name)
    handler_fn_name = Utils.underscore(function.name)
    handler_args = Enum.map(function.params, &Macro.var(&1.name, nil))
    response_module = Module.concat(service_module, Service.module_name(function, :response))

    quote do
      def handle_thrift(unquote(function.name), binary_data, handler_module) do
        unquote(args_block(service_module, function))
        try do
          handler_module.unquote(handler_fn_name)(unquote_splicing(handler_args))
        rescue
          unquote(rescue_blocks(function, file_group, response_module))
        catch
          unquote(catch_block)
        else
          unquote(else_block(function, response_module))
        end
      end
    end
  end

  defp args_block(_service_module, %Function{params: []} = _function) do
    quote do
      _ = binary_data
    end
  end
  defp args_block(service_module, function) do
    args_module = Module.concat(service_module, Service.module_name(function, :args))
    struct_matches = Enum.map(function.params, &{&1.name, Macro.var(&1.name, nil)})
    quote do
      {%unquote(args_module){unquote_splicing(struct_matches)}, ""} = unquote(args_module).BinaryProtocol.deserialize(binary_data)
    end
  end

  defp rescue_blocks(function, file_group, response_module) do
    Enum.flat_map(function.exceptions, fn
      exc ->
        resolved = FileGroup.resolve(file_group, exc)
        dest_module = FileGroup.dest_module(file_group, resolved.type)
        error_var = Macro.var(exc.name, nil)
        field_setter = quote do: {unquote(exc.name), unquote(error_var)}

        quote do
          unquote(error_var) in unquote(dest_module) ->
            exception = %unquote(response_module){unquote(field_setter)}
            {:reply, unquote(response_module).BinaryProtocol.serialize(exception)}
        end
    end)
  end

  defp catch_block() do
    quote do
      kind, reason ->
        formatted_exception = Exception.format(kind, reason, System.stacktrace)
        Logger.error("Exception not defined in thrift spec was thrown: #{formatted_exception}")
        {:server_error, Thrift.TApplicationException.exception(
          message: "Server error: #{formatted_exception}",
          type: :internal_error)}
    end
  end

  defp else_block(%Function{return_type: :void}, _response_module) do
    quote do
      _ ->
        :noreply
    end
  end
  defp else_block(%Function{}, response_module) do
    quote do
      rsp ->
        response = %unquote(response_module){success: rsp}
        {:reply, unquote(response_module).BinaryProtocol.serialize(response)}
    end
  end
end
