defmodule SSLTest do
  use ExUnit.Case, async: true

  setup do
    :inet_tcp = :inet_db.tcp_module()
    :ok = :inet_db.set_tcp_module(:happy_tcp)
    on_exit(fn -> :ok = :inet_db.set_tcp_module(:inet_tcp) end)
  end

  @tag :ipv4_only
  test "connects to google.com over ipv4" do
    {:ok, socket} =
      :ssl.connect(~c"google.com", 443, [
        :binary,
        active: false,
        cacerts: :public_key.cacerts_get()
      ])

    on_exit(fn -> :ssl.close(socket) end)
    assert {:ok, {{_, _, _, _}, 443}} = :ssl.peername(socket)
  end
end
