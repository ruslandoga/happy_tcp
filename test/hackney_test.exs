defmodule HackneyTest do
  use ExUnit.Case, async: true

  setup do
    :inet_tcp = :inet_db.tcp_module()
    :ok = :inet_db.set_tcp_module(:happy_tcp)
    on_exit(fn -> :ok = :inet_db.set_tcp_module(:inet_tcp) end)
  end

  test "google.com" do
    assert {:ok, 200, _headers, _body_ref} = :hackney.get("https://www.google.com")
  end
end
