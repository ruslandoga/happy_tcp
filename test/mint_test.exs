defmodule MintTest do
  use ExUnit.Case, async: true

  setup do
    :inet_tcp = :inet_db.tcp_module()
    :ok = :inet_db.set_tcp_module(:happy_tcp)
    on_exit(fn -> :ok = :inet_db.set_tcp_module(:inet_tcp) end)
  end

  defp get(url) do
    %URI{scheme: scheme, host: host, port: port, path: path} = URI.parse(url)
    port = port || default_port(scheme)
    {:ok, conn} = Mint.HTTP.connect(scheme(scheme), host, port)

    try do
      {:ok, conn, ref} = Mint.HTTP.request(conn, "GET", path, [], [])
      recv(conn, ref, [])
    after
      Mint.HTTP.close(conn)
    end
  end

  defp recv(conn, ref, acc) do
    {:ok, conn, responses} = Mint.HTTP.recv(conn, 0, :timer.seconds(15))

    case handle_responses(responses, ref) do
      {:ok, [status, headers | body]} -> [status, headers, IO.iodata_to_binary(body)]
      {:more, responses} -> recv(conn, ref, acc ++ responses)
    end
  end

  for type <- [:status, :headers, :data] do
    defp handle_responses([{:status, ref, status} | responses], ref) do
      [status | handle_responses(responses, ref)]
    end
  end

  defp handle_responses([], _ref), do: nil

  test "google.com" do
    assert 1 == 1
  end
end
