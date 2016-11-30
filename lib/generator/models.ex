defmodule Thrift.Generator.Models do
  alias Thrift.Protocols.Binary
  alias Thrift.Parser.FileGroup

  def generate!(thrift_filename, output_dir) when is_bitstring(thrift_filename) do
    thrift_filename
    |> Thrift.Parser.parse_file
    |> generate!(output_dir)
  end

  def generate!(%FileGroup{}=file_group, output_dir) do
    Enum.flat_map(file_group.schemas, fn {_, schema} ->
      schema
      |> Map.put(:file_group, file_group)
      |> generate_schema
      |> write_schema_to_file(output_dir)
    end)
  end

  def generate_to_string!(%FileGroup{}=file_group) do
    Enum.flat_map(file_group.schemas, fn {_, schema} ->
      schema
      |> Map.put(:file_group, file_group)
      |> generate_schema
    end)
    |> Enum.reverse
    |> Enum.map(fn {_, code} ->
      Macro.to_string(code)
    end)
    |> Enum.join("\n")
  end

  def generate_schema(schema) do
    List.flatten([
      generate_enums(schema),
      generate_structs(schema),
      generate_exceptions(schema),
      generate_services(schema),
    ])
  end

  defp write_schema_to_file(generated_modules, output_dir) do
    generated_modules
    |> Enum.map(fn {name, quoted} ->
      filename = name
      |> inspect
      |> String.split(".")
      |> Enum.map(&Macro.underscore/1)
      |> Path.join
      |> Kernel.<>(".ex")
      source = Macro.to_string(quoted)

      path = Path.join(output_dir, filename)
      path |> Path.dirname |> File.mkdir_p!
      path |> File.write!(source)

      filename
    end)
  end

  defp namespace(%{namespaces: namespaces}) do
    case namespaces do
      %{elixir: %{path: path}} ->
        path |> String.split(".") |> Enum.map(&Macro.camelize/1) |> Enum.join(".")
      %{} ->
        nil
    end
  end

  defp generate_enums(schema) do
    for {name, enum} <- schema.enums do
      full_name = namespace(schema) |> Module.concat(name)
      {full_name, generate_enum(full_name, enum)}
    end
  end

  defp generate_enum(name, enum) do
    macro_defs = Enum.map(enum.values, fn {key, value} ->
      macro_name = key |> to_string |> String.downcase |> String.to_atom
      quote do
        defmacro unquote(Macro.var(macro_name, nil)), do: unquote(value)
      end
    end)
    member_defs = Enum.map(enum.values, fn {_key, value} ->
      quote do
        def member?(unquote(value)), do: true
      end
    end)
    quote do
      defmodule unquote(name) do
        @moduledoc unquote("Auto-generated Thrift enum #{enum.name}")
        unquote_splicing(macro_defs)
        unquote_splicing(member_defs)
        def member?(_), do: false
      end
    end
  end

  defp generate_structs(schema) do
    for {name, struct} <- schema.structs do
      full_name = namespace(schema) |> Module.concat(name)
      {full_name, generate_struct("struct #{struct.name}", schema.file_group, full_name, struct.fields)}
    end
  end

  defp generate_exceptions(schema) do
    for {name, struct} <- schema.exceptions do
      full_name = namespace(schema) |> Module.concat(name)
      {full_name, generate_struct("exception #{struct.name}", schema.file_group, full_name, struct.fields)}
    end
  end

  defp generate_struct(label, file_group, module_name, fields) do
    struct_parts = Enum.map(fields, fn
      %{name: name, default: nil, type: type} ->
        {name, nil}
      %{name: name, default: default} when not is_nil(default) ->
        {name, default}
    end)
    binary_protocol = Binary.build(file_group, module_name, fields)
    quote do
      defmodule unquote(module_name) do
        _ = unquote "Auto-generated Thrift #{label}"
        unquote_splicing(for field <- fields do
          quote do
            _ = unquote "#{field.id}: #{to_thrift(field.type, file_group)} #{field.name}"
          end
        end)
        defstruct unquote(struct_parts)
        def new, do: %__MODULE__{}
        unquote(binary_protocol)
        def serialize(struct) do
          BinaryProtocol.serialize(struct)
        end
        def serialize(struct, :binary) do
          BinaryProtocol.serialize(struct)
        end
        def serialize(struct, :compact) do
          CompactProtocol.serialize(:struct, struct)
        end
        def deserialize(binary) do
          BinaryProtocol.deserialize(binary)
        end
      end
    end
  end

  alias Thrift.Parser.Models.Service

  defp generate_services(schema) do
    for {name, %Service{functions: functions, extends: parent}} <- schema.services do
      full_name = namespace(schema) |> Module.concat(name)
      {full_name, generate_service(schema.file_group, full_name, functions, parent)}
    end
  end

  defp generate_service(file_group, module_name, functions, nil) do
    for {name, function} <- functions do
      IO.inspect name
      IO.puts "#{inspect function}"
    end

    quote do
      defmodule unquote(module_name) do
        unquote_splicing(Enum.map(functions, fn
          {name, function=%{return_type: :void}} ->
            []
          {name, function} ->
            request_name = name |> to_string |> Macro.camelize |> Module.concat(Request)
            response_name = name |> to_string |> Macro.camelize |> Module.concat(Response)
            success = %Thrift.Parser.Models.Field{
              id: 0,
              name: :success,
              required: false,
              type: function.return_type
            }
            quote do
              unquote generate_struct("#{function.name} request", file_group, request_name, function.params)
              unquote generate_struct("#{function.name} response", file_group, response_name, [success | function.exceptions])
              unquote message_deserializer(function.name, [])
            end
        end))
      end
    end
  end

  defp message_deserializer(method_name, params) do
    method_name = to_string(method_name)
    quote do
      defp handle_request(<<128, 1, _, @call, unquote(byte_size(method_name))::size(32), unquote(method_name), seq_id::32-signed, rest::binary>>) do
        {request, ""} = unquote(Macro.camelize(method_name) |> String.to_atom).Request.deserialize(rest)
        try do
          Task.async(fn ->
            try do
              __MODULE__.Methods.calculate(request.logid, request.w)
            catch e ->
              {:throw, e}
            rescue e ->
              {:rescue, e}
            else result ->
              {:success, result}
            end
          end)
          |> Task.await(:infinity)
        else
          {:success, result} ->
            [
              <<128, 1, 0, @reply, unquote(byte_size(method_name))::size(32), unquote(method_name), seq_id::size(32)>>,
              %unquote(Macro.camelize(method_name) |> String.to_atom).Response{success: result}
              |> unquote(Macro.camelize(method_name) |> String.to_atom).Response.serialize()
            ]
          {:throw, %Tutorial.InvalidOperation{}=e} ->
            [
              <<128, 1, 0, @reply, unquote(byte_size(method_name))::size(32), unquote(method_name), seq_id::size(32)>>,
              %unquote(Macro.camelize(method_name) |> String.to_atom).Response{ouch: e}
              |> unquote(Macro.camelize(method_name) |> String.to_atom).Response.serialize()
            ]
              # @struct, 0, 1,
              #   @i32, 0, 1, whatOp::size(32),
              #   @string, 0, 2, byte_size(why)::size(32), why::binary,
              #   0,
              # 0>>
          {:rescue, %{message: message}} ->
            <<128, 1, 0, @exception, unquote(byte_size(method_name))::size(32), unquote(method_name), seq_id::size(32),
              @string, 0, 1, byte_size(message)::size(32), message::binary,
              @i32, 0, 2, @internal_error::32-signed,
              0>>
        end
      end
    end
  end

  defp generate_service(file_group, full_name, functions, parent) when is_atom(parent) do
    %Service{functions: parent_functions, extends: parent} = FileGroup.resolve(file_group, parent)
    functions = Map.merge(functions, parent_functions)
    generate_service(file_group, full_name, functions, parent)
  end

  # Zero values for built-in types
  defp zero(_schema, :bool), do: nil
  defp zero(_schema, :byte), do: nil
  defp zero(_schema, :i8), do: nil
  defp zero(_schema, :i16), do: nil
  defp zero(_schema, :i32), do: nil
  defp zero(_schema, :i64), do: nil
  defp zero(_schema, :double), do: nil
  defp zero(_schema, :string), do: nil
  defp zero(_schema, :binary), do: nil
  defp zero(_schema, {:map, _}), do: nil
  defp zero(_schema, {:list, _}), do: nil
  defp zero(_schema, {:set, _}), do: quote do: nil
  defp zero(_schema, %{values: [{_, value} | _]}), do: value
  defp zero(_schema, %Thrift.Parser.Models.Struct{}), do: nil

  # Zero values for user defined types
  defp zero(schema, %{referenced_type: type}=ref) do
    cond do
      # Local references
      Map.has_key?(schema.enums, type) ->
        zero(schema, schema.enums[type])
      Map.has_key?(schema.typedefs, type) ->
        zero(schema, schema.typedefs[type])
      Map.has_key?(schema.structs, type) ->
        quote do: nil

      # Included references
      true ->
        case FileGroup.resolve(schema.file_group, ref) do
          nil ->
            raise "Unknown type: #{inspect type}"
          thing ->
            zero(schema, thing)
        end
    end
  end

  def to_thrift(base_type, _file_group) when is_atom(base_type) do
    Atom.to_string(base_type)
  end
  def to_thrift({:map, {key_type, val_type}}, file_group) do
    "map<#{to_thrift key_type, file_group},#{to_thrift val_type, file_group}>"
  end
  def to_thrift({:set, element_type}, file_group) do
    "set<#{to_thrift element_type, file_group}>"
  end
  def to_thrift({:list, element_type}, file_group) do
    "list<#{to_thrift element_type, file_group}>"
  end
  def to_thrift(%Thrift.Parser.Models.TEnum{name: name}, _file_group) do
    "#{name}"
  end
  def to_thrift(%Thrift.Parser.Models.Exception{name: name}, _file_group) do
    "#{name}"
  end
  def to_thrift(%Thrift.Parser.Models.Struct{name: name}, _file_group) do
    "#{name}"
  end
  def to_thrift(%Thrift.Parser.Models.StructRef{referenced_type: type}, file_group) do
    FileGroup.resolve(file_group, type) |> to_thrift(file_group)
  end
end
