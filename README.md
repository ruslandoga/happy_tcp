# happy_tcp

`happy_tcp` is a dual-stack `tcp_module` adapter for Erlang/OTP's legacy
`inet` backend. It returns ordinary IPv6 and IPv4 address tuples in interleaved
order and lets `gen_tcp` try them sequentially.

> [!IMPORTANT]
> This is not complete RFC 8305 Happy Eyeballs. Connection attempts are neither
> raced nor staggered. A slow or black-holed first candidate can delay fallback,
> or prevent it before the shared timeout expires.

## Requirements

- Elixir 1.15 or later in the 1.x series. CI pairs each supported OTP major
  with the latest compatible Elixir minor and also tests the latest available
  Elixir/OTP pair.
- Erlang/OTP 25 through 29.
- The legacy `inet` backend. The `socket` backend is not supported by this
  custom-module integration.

Use an [upstream-supported Elixir/OTP pairing](https://hexdocs.pm/elixir/main/compatibility-and-deprecations.html);
not every combination within those ranges is compatible.

The adapter is intended for `gen_tcp`'s `tcp_module` callback surface, not as an
Erlang distribution driver.

## Installation

```elixir
def deps do
  [
    {:happy_tcp, github: "ruslandoga/happy_tcp"}
  ]
end
```

## Usage

Prefer per-connection configuration. `inet_backend` must be the first option:

```elixir
options = [
  {:inet_backend, :inet},
  {:tcp_module, :happy_tcp},
  :binary,
  {:active, false}
]

:gen_tcp.connect(~c"localhost", 4000, options, 5_000)
```

Do not combine an explicit custom `tcp_module` with the bare `:inet` or `:inet6`
options as a family-selection mechanism. The explicit custom module wins, but
OTP consumes the family atom before invoking its callbacks, so it is not a
dependable instruction to `happy_tcp`. The adapter instead chooses `:inet_tcp`
or `:inet6_tcp` from each numeric destination tuple. Use a concrete `ip` or
`ifaddr` tuple/map when a local bind family must be selected.

## Address ordering and fallback

`getaddrs/1` and `getaddrs/2` return one of these shapes:

```elixir
{:ok, [
  {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1},
  {192, 0, 2, 1},
  {0x2001, 0xDB8, 0, 0, 0, 0, 0, 2},
  {192, 0, 2, 2}
]}

{:error, reason}
```

Every successful value is an ordinary IPv4 four-tuple or IPv6 eight-tuple.
There are no hostname wrappers, nested candidate lists, or connection-control
sentinels.

IPv6 results come first, followed by IPv4, alternating while both families
have addresses. Resolver order is preserved within each family and the longer
family's tail is appended. Numeric IPv4 and IPv6 inputs are returned unchanged.
If one family lookup fails, the successful family's addresses are returned. If
both fail, the IPv6 lookup's error is returned deterministically.

`getaddrs/2` passes the same OTP timer to the IPv6 and IPv4 lookups. Resolution
and every sequential connection attempt therefore consume one shared deadline;
each family and candidate does not receive a fresh timeout.

`connect/3` and `connect/4` receive one real numeric address at a time, delegate
to `:inet_tcp` or `:inet6_tcp` based on tuple shape, and return an ordinary
`gen_tcp` socket. The sequential connection loop belongs to `gen_tcp`.

## Advanced VM-global configuration

`:inet_db.set_tcp_module/1` changes the default for the entire VM. Use it only
when that VM-wide effect is intended, and restore the exact prior value:

```elixir
previous_tcp_module = :inet_db.tcp_module()

try do
  :ok = :inet_db.set_tcp_module(:happy_tcp)

  :gen_tcp.connect(
    ~c"localhost",
    4000,
    [{:inet_backend, :inet}, :binary, {:active, false}],
    5_000
  )
after
  :ok = :inet_db.set_tcp_module(previous_tcp_module)
end
```
