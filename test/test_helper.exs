ipv6_exclusions =
  case :inet6_tcp.listen(0, [
         {:ip, {0, 0, 0, 0, 0, 0, 0, 1}},
         {:active, false}
       ]) do
    {:ok, socket} ->
      :ok = :inet6_tcp.close(socket)
      []

    {:error, _reason} ->
      [:ipv6]
  end

ExUnit.start(exclude: ipv6_exclusions)
