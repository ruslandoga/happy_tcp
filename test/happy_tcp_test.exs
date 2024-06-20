defmodule HappyTCPTest do
  use ExUnit.Case

  setup do
    :inet_tcp = :inet_db.tcp_module()
    :inet_db.set_tcp_module(:happy_tcp)
    on_exit(fn -> :inet_db.set_tcp_module(:inet_tcp) end)
  end

  # TODO :socket

  test "it works" do
    {:ok, _socket} = :gen_tcp.connect(~c"google.com", 80, active: false)
  end
end
