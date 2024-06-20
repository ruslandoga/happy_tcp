# HappyTCP

Kind of like https://github.com/yandex/inet64_tcp but additionally implements [Happy Eyeballs.](https://datatracker.ietf.org/doc/html/rfc8305)

## Installation

```elixir
def deps do
  [
    {:happy_tcp, github: "ruslandoga/happy_tcp"}
  ]
end
```

## Usage

The suggested way to use `happy_tcp` is to set it as the default `tcp_module` for all `gen_tcp` connections:

```elixir
iex> default_tcp_module = :inet_db.tcp_module()
#==> :inet_tcp
iex> :inet_db.set_tcp_module(:happy_tcp)
#==> :ok

# try out some of the hosts from http://dual.tlund.se

# try ipv4-only host (has only A records)
iex> {:ok, socket} = :gen_tcp.connect(~c"ipv4.tlund.se", 80, active: false)
#==> {:ok, #Port<0.666>}
iex> :inet.peername(socket)
#==> {:ok, {{193, 15, 228, 195}, 80}}
iex> :gen_tcp.close(socket)
#==> :ok

# now try ipv6-only host (has only AAAA recods)
#
# note that this one would only work if you have ipv6 connection to the internet
# you can check it with some other tool like ping6
#
#     $ ping6 ipv6.tlund.se
#
iex> {:ok, socket} = :gen_tcp.connect(~c"ipv6.tlund.se", 80, active: false)
#==> {:ok, #Port<0.666>}
#===> or {:error, :ehostunreach} if you don't have IPv6
iex> :inet.peername(socket)
#==> {:ok, {{10752, 2049, 15, 0, 0, 0, 0, 405}, 80}}
iex> :gen_tcp.close(socket)
#==> :ok

# now try dual-stack host (has both A and AAAA records)
#
# this should prefer ipv6 if it's avaible on your machine
iex> {:ok, socket} = :gen_tcp.connect(~c"dual.tlund.se", 80, active: false)
#==> {:ok, #Port<0.666>}
iex> :inet.peername(socket)
#==> {:ok, {{10752, 2049, 15, 0, 0, 0, 0, 405}, 80}}
#==> or {:ok, {{193, 15, 228, 195}, 80}} if you don't have IPv6
iex> :gen_tcp.close(socket)
#==> :ok

# now let's try TLS connections just in case (ensure :ssl app is loaded and started)
iex> {:ok, socket} = :ssl.connect(~c"google.com", 443, [:binary, cacerts: :public_key.cacerts_get])
#==> {:ok,
#==>  {:sslsocket, {:gen_tcp, #Port<0.666>, :tls_connection, :undefined},
#==>   [#PID<0.667.0>, #PID<0.666.0>]}}
iex> :ssl.peername(socket)
#==> {:ok, {{9220, 26624, 16387, 3074, 0, 0, 0, 101}, 443}}
#==> or {:ok, {{172, 217, 26, 78}, 443}} if you don't have IPv6
iex> :ssl.close(socket)
#==> :ok

# testing done, we can now put everything back the way it was before
iex> :inet_db.set_tcp_module(default_tcp_module)
#==> :ok
```

It can also be localized per connection:

```elixir
:gen_tcp.connect(~c"google.com", 80, tcp_module: :happy_tcp)
```

#### Mint

```elixir
Mint.HTTP.connect(:https, "google.com", 443, transport_opts: [tcp_module: :happy_tcp])
```

#### Finch

```elixir
{Finch, pools: %{default: [conn_opts: [transport_opts: [tcp_module: :happy_tcp]]]}}
```

#### httpc

TODO

#### Hackney

TODO

## Notes

When resolving domains, the A and AAAA results are interspersed:

```elixir
iex> :happy_tcp.getaddrs(~c"google.com")
#==> {:ok,
#==>  [
#==>    {9220, 26624, 16387, 3074, 0, 0, 0, 139},
#==>    {74, 125, 24, 139},
#==>    {9220, 26624, 16387, 3074, 0, 0, 0, 102},
#==>    {74, 125, 24, 138},
#==>    {9220, 26624, 16387, 3074, 0, 0, 0, 100},
#==>    {74, 125, 24, 102},
#==>    {9220, 26624, 16387, 3074, 0, 0, 0, 101},
#==>    {74, 125, 24, 100},
#==>    {74, 125, 24, 113},
#==>    {74, 125, 24, 101}
#==>  ]}
```

## TODOs

- actually implement happy eyeballs
  - can replace / inject a separate gen_tcp module the same way using `inet:gen_tcp_module` or can return a list of list from `:happy_tcp.getaddrs` :)
  - instead of connecting to addrs [sequentially](https://github.com/erlang/otp/blob/OTP-27.0/lib/kernel/src/gen_tcp.erl#L585-L609), do the happy eyeballs thing and connect to ipv6, give it 300ms, and if by that time it's not connected, start ipv4 connection, then wait to whoever returns first, if none, go ahead through the ips
  - "deep down" (gen_tcp -> inet_tcp -> prim_inet) gen_tcp.connect becomes [async](https://github.com/erlang/otp/blob/OTP-27.0/erts/preloaded/src/prim_inet.erl#L355-L411) so we can fire off a couple of them and wait for the first one and close (or cancel) the others
  - if gen_tcp_socket backend is used, we can start multiple gen_statems
- ensure [socket](https://www.erlang.org/doc/apps/kernel/socket.html) works too
