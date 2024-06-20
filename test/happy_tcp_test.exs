defmodule HappyTCPTest do
  use ExUnit.Case

  setup do
    :inet_tcp = :inet_db.tcp_module()
    :ok = :inet_db.set_tcp_module(:happy_tcp)
    on_exit(fn -> :ok = :inet_db.set_tcp_module(:inet_tcp) end)
  end

  # TODO :socket

  test "server defaults to inet6, client happy" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        assert {:ok, {{0, 0, 0, 0, 0, 0, 0, 1}, _}} = :inet.peername(socket)
        :gen_tcp.recv(socket, 0)
      end)

    {:ok, socket} = :gen_tcp.connect(~c"localhost", port, active: false)
    assert {:ok, {{0, 0, 0, 0, 0, 0, 0, 1}, ^port}} = :inet.peername(socket)

    :ok = :gen_tcp.send(socket, "hello, world!")
    assert {:ok, "hello, world!"} = Task.await(server)
  end

  @tag :skip
  test "client can force inet" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        assert {:ok, {{127, 0, 0, 1}, _}} = :inet.peername(socket)
        :gen_tcp.recv(socket, 0)
      end)

    {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:inet, active: false])
    assert {:ok, {{127, 0, 0, 1}, ^port}} = :inet.peername(socket)

    :ok = :gen_tcp.send(socket, "hello, world!")
    assert {:ok, "hello, world!"} = Task.await(server)
  end

  test "server supports inet, client adapts" do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, :inet, active: false])
    {:ok, port} = :inet.port(listen_socket)

    server =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listen_socket)
        assert {:ok, {{127, 0, 0, 1}, _}} = :inet.peername(socket)
        :gen_tcp.recv(socket, 0)
      end)

    {:ok, socket} = :gen_tcp.connect(~c"localhost", port, active: false)
    assert {:ok, {{127, 0, 0, 1}, ^port}} = :inet.peername(socket)

    :ok = :gen_tcp.send(socket, "hello, world!")
    assert {:ok, "hello, world!"} = Task.await(server)
  end

  @tag :ipv6_only
  test "connects to google.com over ipv6" do
    {:ok, socket} = :gen_tcp.connect(~c"google.com", 80, [:binary, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert {:ok, {{_, _, _, _, _, _, _, _}, 80}} = :inet.peername(socket)
  end

  @tag :ipv4_only
  test "connects to google.com over ipv4" do
    {:ok, socket} = :gen_tcp.connect(~c"google.com", 80, [:binary, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)
    assert {:ok, {{_, _, _, _}, 80}} = :inet.peername(socket)
  end
end
