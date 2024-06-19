# HappyTCP

Kind of like https://github.com/yandex/inet64_tcp but adapts to some of the changes made to `inet_tcp` and `inet_tcp6` modules in the last eight years.

## Installation

```elixir
def deps do
  [
    {:happy_tcp, github: "ruslandoga/happy_tcp"}
  ]
end
```

## Usage

```elixir
iex> default_tcp_module = :inet_db.tcp_module()
iex> :inet_db.set_tcp_module(:happy_tcp)
# try out some of the hosts from http://dual.tlund.se
iex> :gen_tcp.connect('ipv4.tlund.se', 80, active: false)
# note that this one would only work if you have ipv6 connection to the internet
# you can check it with some other tool like pin6
#
#     $ ping6 ipv6.tlund.se
#
iex> :gen_tcp.connect('ipv6.tlund.se', 80, active: false)
# this should prefer ipv6 if it's avaible on your machine
iex> :gen_tcp.connect('dual.tlund.se', 80, active: false)
# put everything back the way it was before
iex> :inet_db.set_tcp_module(default_tcp_module)
```

## Caveats

When resolving domains, the A and AAAA results are interspersed:

```elixir
iex> :happy_tcp.getaddrs(~c"google.com")
{:ok,
 [
   {9220, 26624, 16387, 3074, 0, 0, 0, 139},
   {74, 125, 24, 139},
   {9220, 26624, 16387, 3074, 0, 0, 0, 102},
   {74, 125, 24, 138},
   {9220, 26624, 16387, 3074, 0, 0, 0, 100},
   {74, 125, 24, 102},
   {9220, 26624, 16387, 3074, 0, 0, 0, 101},
   {74, 125, 24, 100},
   {74, 125, 24, 113},
   {74, 125, 24, 101}
 ]}
```
