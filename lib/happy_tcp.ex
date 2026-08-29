defmodule :happy_tcp do
  @moduledoc """
  `happy_tcp` is a dual-stack `tcp_module` adapter for Erlang/OTP's legacy
  `inet` backend.

  `getaddrs/1` and `getaddrs/2` return `{:ok, [ip_address()]}` or
  `{:error, reason}`. Successful lists contain ordinary numeric IP addresses:
  IPv4 four-tuples and IPv6 eight-tuples. Numeric inputs are returned unchanged
  as the sole list item. Resolver order is retained within each family while
  the results are interleaved IPv6-first. If one family has more results, its
  remaining addresses are appended. If only one lookup succeeds, that family's
  addresses are returned; if both fail, the IPv6 lookup error is returned.

  `gen_tcp` tries the returned addresses sequentially. Attempts are not raced
  or staggered, so this is not complete RFC 8305 Happy Eyeballs. A slow or
  black-holed candidate can consume the shared timeout before fallback occurs.
  `getaddrs/2` passes the same OTP timer to both family lookups so resolution
  also observes that single deadline.

  Custom `tcp_module` integration is supported only with the legacy `inet`
  backend. The `socket` backend and Erlang distribution are outside this
  module's scope.
  """

  # relevant links
  # https://github.com/yandex/inet64_tcp
  # https://github.com/erlang/otp/blob/master/lib/kernel/src/inet_tcp.erl
  # https://github.com/erlang/otp/blob/master/lib/kernel/src/inet6_tcp.erl

  # Determine a module by IP address tuple.
  @spec mod_by_addr(:inet.ip_address()) :: :inet_tcp | :inet6_tcp
  defp mod_by_addr({_, _, _, _} = _ipv4), do: :inet_tcp
  defp mod_by_addr({_, _, _, _, _, _, _, _} = _ipv6), do: :inet6_tcp

  defp mod_by_sockaddr(%{addr: address}) when is_tuple(address), do: mod_by_addr(address)
  defp mod_by_sockaddr(%{family: :inet}), do: :inet_tcp
  defp mod_by_sockaddr(%{family: :inet6}), do: :inet6_tcp

  # Determine a module by socket options (may return nil).
  @spec get_specified_mod([:gen_tcp.option()]) :: :inet_tcp | :inet6_tcp | nil
  defp get_specified_mod(opts), do: get_specified_mod(opts, nil)

  defp get_specified_mod([{addr_tag, address} | opts], inferred_mod)
       when addr_tag in [:ip, :ifaddr] do
    get_specified_mod(opts, specified_mod_by_addr(address) || inferred_mod)
  end

  defp get_specified_mod([:inet | _], _inferred_mod), do: :inet_tcp
  defp get_specified_mod([:inet6 | _], _inferred_mod), do: :inet6_tcp

  defp get_specified_mod([{:ipv6_v6only, value} | _], _inferred_mod)
       when is_boolean(value),
       do: :inet6_tcp

  defp get_specified_mod([_ | opts], inferred_mod), do: get_specified_mod(opts, inferred_mod)
  defp get_specified_mod([], inferred_mod), do: inferred_mod

  defp specified_mod_by_addr({_, _, _, _}), do: :inet_tcp
  defp specified_mod_by_addr({_, _, _, _, _, _, _, _}), do: :inet6_tcp
  defp specified_mod_by_addr(%{family: :inet}), do: :inet_tcp
  defp specified_mod_by_addr(%{family: :inet6}), do: :inet6_tcp
  defp specified_mod_by_addr(%{addr: address}), do: specified_mod_by_addr(address)
  defp specified_mod_by_addr(_address), do: nil

  # Prefer IPv6 for the single-address callback.
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

  defp merge_getaddrs_results({:ok, ipv6_addresses}, {:ok, ipv4_addresses}) do
    {:ok, interleave(ipv6_addresses, ipv4_addresses)}
  end

  defp merge_getaddrs_results({:ok, ipv6_addresses}, {:error, _reason}) do
    {:ok, ipv6_addresses}
  end

  defp merge_getaddrs_results({:error, _reason}, {:ok, ipv4_addresses}) do
    {:ok, ipv4_addresses}
  end

  # Prefer the first lookup's error so the failure policy does not depend on
  # how much of the shared deadline remained for the IPv4 lookup.
  defp merge_getaddrs_results(
         {:error, _ipv6_reason} = ipv6_error,
         {:error, _ipv4_reason}
       ) do
    ipv6_error
  end

  defp interleave([], ipv4_addresses), do: ipv4_addresses
  defp interleave(ipv6_addresses, []), do: ipv6_addresses

  defp interleave([ipv6 | rest_ipv6], [ipv4 | rest_ipv4]) do
    [ipv6, ipv4 | interleave(rest_ipv6, rest_ipv4)]
  end

  # Select the delegate from the real numeric candidate supplied by gen_tcp.

  def connect(address, port, opts) when is_integer(port) do
    mod_by_addr(address).connect(address, port, opts)
  end

  def connect(%{} = sock_addr, opts, time) do
    mod = mod_by_sockaddr(sock_addr)
    mod.connect(normalize_sockaddr(sock_addr, mod), opts, time)
  end

  def connect(address, port, opts, timeout) do
    mod_by_addr(address).connect(address, port, opts, timeout)
  end

  # Older OTP releases accept numeric sockaddr map destinations but not every
  # symbolic form supported by newer releases.
  defp normalize_sockaddr(%{addr: address} = sock_addr, mod)
       when address in [:any, :loopback] do
    %{sock_addr | addr: mod.translate_ip(address)}
  end

  defp normalize_sockaddr(sock_addr, _mod), do: sock_addr

  # Guess a module from bind options, defaulting to IPv6.
  def listen(port, opts) do
    case get_specified_mod(opts) do
      nil -> :inet6_tcp.listen(port, opts)
      mod -> mod.listen(port, opts)
    end
  end

  # Guess a module by options; when unspecified, try IPv6 and then IPv4.
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

  # The following functions have identical implementations in inet_tcp and
  # inet6_tcp.

  def close(socket), do: :inet.tcp_close(socket)
  def send(socket, packet, opts \\ []), do: :prim_inet.send(socket, packet, opts)
  def recv(socket, length, timeout \\ -1), do: :prim_inet.recv(socket, length, timeout)
  def unrecv(socket, data), do: :prim_inet.unrecv(socket, data)
  def shutdown(socket, how), do: :prim_inet.shutdown(socket, how)
  def controlling_process(socket, new_owner), do: :inet.tcp_controlling_process(socket, new_owner)
  def getserv(port_or_name), do: :inet_tcp.getserv(port_or_name)

  # IPv6 is the only valid family value consistent with this adapter's default.
  # This callback exists for surface compatibility; happy_tcp is not a
  # distribution driver.
  def family, do: :inet6

  def mask({_, _, _, _} = mask, {_, _, _, _} = addr), do: :inet_tcp.mask(mask, addr)

  def mask({_, _, _, _, _, _, _, _} = mask, {_, _, _, _, _, _, _, _} = addr) do
    :inet6_tcp.mask(mask, addr)
  end

  def parse_address(host) do
    case :inet_tcp.parse_address(host) do
      {:ok, _addr} = ok -> ok
      _ -> :inet6_tcp.parse_address(host)
    end
  end

  def translate_ip(ip), do: :inet6_tcp.translate_ip(ip)

  def accept(socket, timeout \\ :infinity) do
    with {:ok, {address, _port}} <- :inet.sockname(socket) do
      mod_by_addr(address).accept(socket, timeout)
    end
  end
end
