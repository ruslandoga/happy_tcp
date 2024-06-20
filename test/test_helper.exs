default_tcp_module = :inet_db.tcp_module()
:inet.tcp_module()
:ok = :inet_db.set_tcp_module(:happy_tcp)

config =
  try do
    {:ok, socket} = :gen_tcp.connect(~c"google.com", 80, active: false)
    {:ok, {addr, _port}} = :inet.peername(socket)

    case addr do
      {_, _, _, _} -> [exclude: [:ipv6_only]]
      {_, _, _, _, _, _, _, _} -> [exclude: [:ipv4_only]]
    end
  after
    :ok = :inet_db.set_tcp_module(default_tcp_module)
  end

ExUnit.start(config)
