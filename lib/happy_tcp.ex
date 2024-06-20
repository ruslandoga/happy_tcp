defmodule :happy_tcp do
  @moduledoc """
  Universal TCP driver for inet and inet6 address families.

  Based on https://github.com/yandex/inet64_tcp but updates to OPT-27 and intersperses IPv6 and IPv4
  addresses for lookups and connection attempts instead of concating them, i.e.

      ["2404:6800:4003:c1c::66", "142.251.175.139", "2404:6800:4003:c1c::8a", "142.251.175.100", ...]

  instead of

      ["2404:6800:4003:c1c::66",  "2404:6800:4003:c1c::8a", ..., "142.251.175.139", "142.251.175.100", ...]

  """

  # relevant links
  # https://github.com/yandex/inet64_tcp
  # https://github.com/erlang/otp/blob/master/lib/kernel/src/inet_tcp.erl
  # https://github.com/erlang/otp/blob/master/lib/kernel/src/inet6_tcp.erl

  @spec mod_by_addr(:inet.ip_address()) :: :inet_tcp | :inet6_tcp
  defp mod_by_addr({_, _, _, _} = _ipv4), do: :inet_tcp
  defp mod_by_addr({_, _, _, _, _, _, _, _} = _ipv6), do: :inet6_tcp

  @spec get_specified_mod([:gen_tcp.option()]) :: :inet_tcp | :inet6_tcp | nil
  defp get_specified_mod([{addr_tag, address} | _]) when addr_tag in [:ip, :ifaddr] do
    mod_by_addr(address)
  end

  defp get_specified_mod([{:ipv6_v6only, true} | _]), do: :inet6_tcp
  defp get_specified_mod([_ | opts]), do: get_specified_mod(opts)
  defp get_specified_mod([]), do: nil

  # TODO when is it called?
  def getaddr(address) do
    case :inet6_tcp.getaddr(address) do
      {:ok, _} = good_result -> good_result
      _ -> :inet_tcp.getaddr(address)
    end
  end

  def getaddr(address, timer) do
    case :inet6_tcp.getaddr(address, timer) do
      {:ok, _} = good_result -> good_result
      _ -> :inet_tcp.getaddr(address, timer)
    end
  end

  def getaddrs(address) do
    result6 = :inet6_tcp.getaddrs(address)
    result4 = :inet_tcp.getaddrs(address)
    merge_getaddrs_results(result6, result4)
  end

  def getaddrs(address, timer) do
    result6 = :inet6_tcp.getaddrs(address, timer)
    result4 = :inet_tcp.getaddrs(address, timer)
    merge_getaddrs_results(result6, result4)
  end

  defp merge_getaddrs_results({:ok, addrs1}, {:ok, addrs2}) do
    {:ok, join_intersperse(addrs1, addrs2)}
  end

  defp merge_getaddrs_results({:ok, addrs1}, _error2), do: {:ok, addrs1}
  defp merge_getaddrs_results(_error1, {:ok, addrs2}), do: {:ok, addrs2}
  defp merge_getaddrs_results(error1, _error2), do: error1

  defp join_intersperse([], []), do: []
  defp join_intersperse([], [_ | _] = right), do: right
  defp join_intersperse([_ | _] = left, []), do: left

  defp join_intersperse([left | rest_left], [right | rest_right]) do
    [left, right | join_intersperse(rest_left, rest_right)]
  end

  # TODO cleanup
  def connect(address, port, opts) when is_integer(port) do
    mod_by_addr(address).connect(address, port, opts)
  end

  def connect(%{addr: address} = sock_addr, opts, time) do
    mod_by_addr(address).connect(sock_addr, opts, time)
  end

  def connect(address, port, opts, timeout) do
    mod_by_addr(address).connect(address, port, opts, timeout)
  end

  def listen(port, opts) do
    case get_specified_mod(opts) do
      :inet_tcp -> :inet_tcp.listen(port, opts)
      _ -> :inet6_tcp.listen(port, opts)
    end
  end

  # TODO when is it called?
  def fdopen(fd, opts) do
    case get_specified_mod(opts) do
      nil -> try_fdopen([:inet6_tcp, :inet_tcp], fd, opts, {:error, :einval})
      mod -> mod.fdopen(fd, opts)
    end
  end

  defp try_fdopen([mod | mods], fd, opts, _error) do
    case mod.fdopen(fd, opts) do
      {:ok, _socket} = ok -> ok
      {:error, _reason} = error -> try_fdopen(mods, fd, opts, error)
    end
  end

  defp try_fdopen([], _fd, _opts, error), do: error

  def getserv(port) when is_integer(port), do: {:ok, port}
  def getserv(name) when is_atom(name), do: :inet.getservbyname(name, :tcp)

  # TODO when is it called?
  def family, do: __MODULE__

  # TODO when is it called?
  def mask(mask, addr)

  def mask({_, _, _, _} = mask, {_, _, _, _} = addr) do
    :inet_tcp.mask(mask, addr)
  end

  def mask({_, _, _, _, _, _, _, _} = mask, {_, _, _, _, _, _, _, _} = addr) do
    :inet6_tcp.mask(mask, addr)
  end

  # TODO when is it called?
  def translate_ip(ip) do
    :inet6_tcp.translate_ip(ip)
  end
end
