defmodule HappyTCPTest do
  use ExUnit.Case

  setup do
    :inet = :inet_db.tcp_module()
    :inet_db.set_tcp_module(:happy_tcp)
    on_exit(fn -> :inet_db.set_tcp_module(:inet) end)
  end

  test "it works"
end
