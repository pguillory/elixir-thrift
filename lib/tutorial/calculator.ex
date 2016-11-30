defmodule Tutorial.Calculator do
  @i32 8
  @string 11
  @struct 12

  @call 1
  @reply 2
  @exception 3
  @oneway 4

  @internal_error 6

  def start_link(opts) do
    pid = spawn_link fn ->
      port = Keyword.fetch!(opts, :port)
      {:ok, listener} = :gen_tcp.listen(port, [
        mode: :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        backlog: Keyword.get(opts, :backlog, 1000),
      ])
      accept(listener)
    end
    if name = Keyword.get(opts, :name) do
      Process.register(pid, name)
    end
    {:ok, pid}
  end

  defp accept(listener) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        spawn fn ->
          Process.link(socket)
          handle(socket)
        end
        accept(listener)
      {:error, :timeout} ->
        accept(listener)
      {:error, :closed} ->
        raise "Socket closed unexpectedly"
      {:error, error} ->
        raise "Error: #{inspect error}"
    end
  end

  defp handle(socket) do
    socket
    |> receive_frame
    |> handle_request
    |> send_frame(socket)

    handle(socket)
  end

  defp receive_frame(socket) do
    case :gen_tcp.recv(socket, 4) do
      {:error, :closed} ->
        exit :normal
      {:ok, <<128, 1, _, @call>>} ->
        raise "Client using un-framed transport"
      {:ok, <<128, 1, _, @oneway>>} ->
        raise "Client using un-framed transport"
      {:ok, <<length::32-signed>>} when length < 0 ->
        raise "Frame length too small: #{length}"
      {:ok, <<length::32-signed>>} when length > 16384000 ->
        raise "Frame length too large: #{length}"
      {:ok, <<length::32-signed>>} ->
        case :gen_tcp.recv(socket, length) do
          {:error, :closed} ->
            exit :normal
          {:ok, data} ->
            data
        end
    end
  end

  defp send_frame(data, socket) do
    frame_header = <<:erlang.iolist_size(data)::32-signed>>
    case :gen_tcp.send(socket, [frame_header | data]) do
      {:error, :closed} ->
        exit :normal
      :ok ->
        :ok
    end
  end

  defp handle_request(<<128, 1, _, @call, 3::size(32), "add", seq_id::32-signed,
                        @i32, 0, 1, num1::size(32),
                        @i32, 0, 2, num2::size(32), 0>>) do
    try do
      Tutorial.Calculator.Methods.add(num1, num2)
    rescue
      e in [RuntimeError] ->
        message = e.message
        <<128, 1, 0, @exception, byte_size("add")::size(32), "add", seq_id::size(32),
          @string, 0, 1, byte_size(message)::size(32), message::binary,
          @i32, 0, 2, @internal_error::32-signed,
          0>>
    else
      result when is_integer(result) ->
        <<128, 1, 0, @reply, byte_size("add")::size(32), "add", seq_id::size(32),
          @i32, 0, 0, result::32-signed,
          0>>
    end
  end

  defmodule(Calculate.Request) do
    _ = "Auto-generated Thrift calculate request"
    _ = "1: i32 logid"
    _ = "2: tutorial.Work w"
    defstruct(logid: nil, w: nil)
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
        deserialize(binary, %Calculate.Request{})
      end
      defp(deserialize(<<0, rest::binary>>, acc = %Calculate.Request{})) do
        {acc, rest}
      end
      defp(deserialize(<<8, 1::size(16), value::size(32), rest::binary>>, acc)) do
        deserialize(rest, %{acc | logid: value})
      end
      defp(deserialize(<<12, 2::16-signed, rest::binary>>, acc)) do
        {value, rest} = Elixir.Tutorial.Work.BinaryProtocol.deserialize(rest)
        deserialize(rest, %{acc | w: value})
      end
      def(serialize(%Calculate.Request{logid: logid, w: w})) do
        [case(logid) do
          nil ->
            <<>>
          _ ->
            <<8, 1::size(16), logid::32-signed>>
        end, case(w) do
          nil ->
            <<>>
          _ ->
            [<<12, 2::size(16)>>, Tutorial.Work.serialize(w)]
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
  defmodule(Calculate.Response) do
    _ = "Auto-generated Thrift calculate request"
    _ = "0: i32 success"
    _ = "1: tutorial.InvalidOperation ouch"
    defstruct(success: nil, ouch: nil)
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
        deserialize(binary, %Calculate.Response{})
      end
      defp(deserialize(<<0, rest::binary>>, acc = %Calculate.Response{})) do
        {acc, rest}
      end
      defp(deserialize(<<8, 0::size(16), value::size(32), rest::binary>>, acc)) do
        deserialize(rest, %{acc | success: value})
      end
      defp(deserialize(<<12, 1::16-signed, rest::binary>>, acc)) do
        {value, rest} = Elixir.Tutorial.InvalidOperation.BinaryProtocol.deserialize(rest)
        deserialize(rest, %{acc | ouch: value})
      end
      def(serialize(%Calculate.Response{success: success, ouch: ouch})) do
        [case(success) do
          nil ->
            <<>>
          _ ->
            <<8, 0::size(16), success::32-signed>>
        end, case(ouch) do
          nil ->
            <<>>
          _ ->
            [<<12, 1::size(16)>>, Tutorial.InvalidOperation.serialize(ouch)]
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

  defp handle_request(<<128, 1, _, @call, 9::size(32), "calculate", seq_id::32-signed, rest::binary>>) do
    {request, ""} = Calculate.Request.deserialize(rest)

    # <<@i32, 0, 1, logid::size(32), rest::binary>> = rest
    # <<@struct, 0, 2, rest::binary>> = rest
    # {w, rest} = Tutorial.Work.deserialize(rest)
    # <<0>> = rest

    try do
      Task.async(fn ->
        try do
          Tutorial.Calculator.Methods.calculate(request.logid, request.w)
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
        <<128, 1, 0, @reply, byte_size("calculate")::size(32), "calculate", seq_id::size(32),
          @i32, 0, 0, result::32-signed,
          0>>
      {:throw, %Tutorial.InvalidOperation{whatOp: whatOp, why: why}} ->
        <<128, 1, 0, @reply, byte_size("calculate")::size(32), "calculate", seq_id::size(32),
          @struct, 0, 1,
            @i32, 0, 1, whatOp::size(32),
            @string, 0, 2, byte_size(why)::size(32), why::binary,
            0,
          0>>
      {:rescue, %{message: message}} ->
        <<128, 1, 0, @exception, byte_size("calculate")::size(32), "calculate", seq_id::size(32),
          @string, 0, 1, byte_size(message)::size(32), message::binary,
          @i32, 0, 2, @internal_error::32-signed,
          0>>
    end
  end
end

defmodule Tutorial.Calculator.Methods do
  require Tutorial.Operation
  alias Tutorial.Operation
  alias Tutorial.InvalidOperation

  def ping do
    :ok
  end

  def add(num1, num2) do
    # raise "uh oh"
    num1 + num2
  end

  def calculate(_logid, w) do
    case w.op do
      Operation.add ->
        w.num1 + w.num2
      Operation.subtract ->
        w.num1 - w.num2
      Operation.multiply ->
        w.num1 * w.num2
      Operation.divide ->
        w.num1 / w.num2
      _ ->
        # raise "asdf"
        throw %InvalidOperation{whatOp: w.op, why: "just because"}
    end
  end

  def zip do
    nil
  end

  def sharingTest(s) do
    s
  end
end
