defmodule FramedServerBenchmark do
  use Benchfella

  # @thrift_file_path "./test/fixtures/app/thrift/simple.thrift"
  # import ParserUtils

  # defmodule Simple.Handler do
  #   def echo_user(user) do
  #     user
  #   end

  #   def ping, do: true
  # end

  # defmodule ErlangHandlers do
  #   def handle_function(:echo_user, {user}) do
  #     {:reply, user}
  #   end

  #   def handle_function(:ping, _) do
  #     {:reply, true}
  #   end
  # end

  def recv(sock) do
    {:ok, <<128, 1, 0, 1, 4::32, "ping", 0::32, 0>>} = :gen_tcp.recv(sock, 0)
    :ok = :gen_tcp.send(sock, <<128, 1, 0, 2, 4::32, "ping", 0::32, 2, 0::16, 1, 0>>)
    recv(sock)
    # {:ok, <<128, 1, 0, 2, 4::32, "ping", 0::32, 2, 0::16, 1, 0>>} = :gen_tcp.recv(client, 0)
  end

  setup_all do
    # @thrift_file_path
    # |> parse_thrift
    # |> compile_module

    # Application.start(:ranch)

    {:ok, lsock} = :gen_tcp.listen(12345, mode: :binary, packet: 4, active: false, nodelay: true)
    spawn_link fn ->
      {:ok, sock} = :gen_tcp.accept(lsock)
      recv(sock)
    end

    # {:ok, server_pid} = SimpleService.Binary.Framed.Server.start_link(Simple.Handler, 12345, [])
    # {:ok, erlang_server_pid} = :thrift_socket_server.start(handler: ErlangHandlers,
    #                                                        port: 56789,
    #                                                        service: :simple_service_thrift,
    #                                                        framed: true,
    #                                                        socket_opts: [
    #                                                          recv_timeout: 15_000,
    #                                                          keepalive: true])

    # map_value = 1..100
    # |> Enum.map(fn num -> {num, "foo#{num}"} end)
    # |> Map.new

    # blocked_user_ids = Enum.to_list(50_000..50_150)
    # user_options = [
    #   is_evil: false,
    #   user_id: 2841204,
    #   number_of_hairs_on_head: 1029448,
    #   amount_of_red: 23,
    #   nineties_era_color: 381221,
    #   mint_gum: 24421.024,
    #   username: "Stinkypants",
    #   my_map: map_value,
    #   optional_integers: Enum.to_list(1..100),
    #   blocked_user_ids: blocked_user_ids
    # ]

    # erlang_user = user(:erlang, user_options)
    # elixir_user = user(:elixir, user_options)

    # {:ok, client} = SimpleService.Binary.Framed.Client.start_link("localhost", 12345, [])
    {:ok, client} = :gen_tcp.connect('localhost', 12345, mode: :binary, packet: 4, active: false, nodelay: true)
    # IO.inspect client

    # {:ok, erlang_client} = :thrift_client_util.new('localhost', 56789, :simple_service_thrift, framed: true)

    {:ok, client: client}
  end

  # bench "Echoing a struct in Elixir" do
  #   user = bench_context[:elixir_user]
  #   client = bench_context[:client]
  #   {:ok, user} = SimpleService.Binary.Framed.Client.echo_user(client, user)
  # end

  bench "Returning a boolean in Elixir" do
    client = bench_context[:client]
    # IO.inspect client
    :ok = :gen_tcp.send(client, <<128, 1, 0, 1, 4::32, "ping", 0::32, 0>>)
    {:ok, <<128, 1, 0, 2, 4::32, "ping", 0::32, 2, 0::16, 1, 0>>} = :gen_tcp.recv(client, 0)
    # {:ok, user} = SimpleService.Binary.Framed.Client.ping(client)
  end

  # bench "Echoing a struct in Erlang" do
  #   {_client, {:ok, _u}} = bench_context[:erlang_client]
  #   |> :thrift_client.call(:echo_user, [bench_context[:erlang_user]])
  # end

  # bench "Returning a boolean in Erlang" do
  #   {_client, {:ok, true}} = bench_context[:erlang_client]
  #   |> :thrift_client.call(:ping, [])
  # end

end
