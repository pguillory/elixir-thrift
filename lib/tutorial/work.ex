defmodule(Tutorial.Work) do
  _ = "Auto-generated Thrift struct tutorial.Work"
  _ = "1: i32 num1"
  _ = "2: i32 num2"
  _ = "3: tutorial.Operation op"
  _ = "4: string comment"
  defstruct(num1: 0, num2: nil, op: 1, comment: nil)
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
      deserialize(binary, %Tutorial.Work{})
    end
    defp(deserialize(<<0, rest::binary>>, acc = %Tutorial.Work{})) do
      {acc, rest}
    end
    defp(deserialize(<<8, 1::size(16), value::size(32), rest::binary>>, acc)) do
      deserialize(rest, %{acc | num1: value})
    end
    defp(deserialize(<<8, 2::size(16), value::size(32), rest::binary>>, acc)) do
      deserialize(rest, %{acc | num2: value})
    end
    defp(deserialize(<<8, 3::size(16), value::size(32), rest::binary>>, acc)) do
      deserialize(rest, %{acc | op: value})
    end
    defp(deserialize(<<11, 4::16-signed, string_size::32-signed, rest::binary>>, acc)) do
      <<value::binary-size(string_size), rest::binary>> = rest
      deserialize(rest, %{acc | comment: value})
    end
    def(serialize(%Tutorial.Work{num1: num1, num2: num2, op: op, comment: comment})) do
      [case(num1) do
        nil ->
          <<>>
        _ ->
          <<8, 1::size(16), num1::32-signed>>
      end, case(num2) do
        nil ->
          <<>>
        _ ->
          <<8, 2::size(16), num2::32-signed>>
      end, case(op) do
        nil ->
          <<>>
        _ ->
          <<8, 3::size(16), op::32-signed>>
      end, case(comment) do
        nil ->
          <<>>
        _ ->
          [<<11, 4::size(16), byte_size(comment)::size(32)>>, comment]
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