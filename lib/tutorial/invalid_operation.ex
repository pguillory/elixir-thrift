defmodule(Tutorial.InvalidOperation) do
  _ = "Auto-generated Thrift exception tutorial.InvalidOperation"
  _ = "1: i32 whatOp"
  _ = "2: string why"
  defstruct(whatOp: nil, why: nil)
  def(new) do
    %__MODULE__{}
  end
  defmodule(BinaryProtocol) do
    def(bool_to_int(false)) do
      0
    end
    def(bool_to_int(nil)) do
      0
    end
    def(bool_to_int(_)) do
      1
    end
    def(deserialize(binary)) do
      deserialize(binary, %Tutorial.InvalidOperation{})
    end
    defp(deserialize(<<0, rest::binary>>, acc = %Tutorial.InvalidOperation{})) do
      {acc, rest}
    end
    defp(deserialize(<<8, 1::size(16), value::size(32), rest::binary>>, acc)) do
      deserialize(rest, %{acc | whatOp: value})
    end
    defp(deserialize(<<11, 2::16-signed, string_size::32-signed, rest::binary>>, acc)) do
      <<value::binary-size(string_size), rest::binary>> = rest
      deserialize(rest, %{acc | why: value})
    end
    def(serialize(%Tutorial.InvalidOperation{whatOp: whatOp, why: why})) do
      [case(whatOp) do
        nil ->
          <<>>
        _ ->
          <<8, 1::size(16), whatOp::32-signed>>
      end, case(why) do
        nil ->
          <<>>
        _ ->
          [<<11, 2::size(16), byte_size(why)::size(32)>>, why]
      end, <<0>>]
    end
  end
  def(serialize(struct)) do
    BinaryProtocol.serialize(struct)
  end
  def(serialize(struct, :binary)) do
    BinaryProtocol.serialize(struct)
  end
  def(serialize(struct, :compact)) do
    CompactProtocol.serialize(:struct, struct)
  end
  def(deserialize(binary)) do
    BinaryProtocol.deserialize(binary)
  end
end