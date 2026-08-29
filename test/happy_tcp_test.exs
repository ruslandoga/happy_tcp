defmodule HappyTCPTest do
  use ExUnit.Case, async: false

  @ipv4_loopback {127, 0, 0, 1}
  @ipv6_any {0, 0, 0, 0, 0, 0, 0, 0}
  @ipv6_loopback {0, 0, 0, 0, 0, 0, 0, 1}
  @ipv6_a {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}
  @ipv6_b {0x2001, 0xDB8, 0, 0, 0, 0, 0, 2}
  @ipv6_c {0x2001, 0xDB8, 0, 0, 0, 0, 0, 3}
  @ipv6_d {0x2001, 0xDB8, 0, 0, 0, 0, 0, 4}
  @ipv4_a {192, 0, 2, 1}
  @ipv4_b {192, 0, 2, 2}
  @ipv4_c {192, 0, 2, 3}
  @ipv4_d {192, 0, 2, 4}
  @ipv4_e {192, 0, 2, 5}

  @ipv6_available (case :inet6_tcp.listen(0, [
                          {:ip, @ipv6_loopback},
                          {:active, false}
                        ]) do
                     {:ok, socket} ->
                       :ok = :inet6_tcp.close(socket)
                       true

                     {:error, _reason} ->
                       false
                   end)

  @ipv6_skip if @ipv6_available, do: false, else: "IPv6 loopback is unavailable"

  test "getaddrs interleaves resolver order and appends either uneven tail" do
    install_test_hosts("""
    2001:db8::1 ipv6-long.invalid
    2001:db8::2 ipv6-long.invalid
    2001:db8::3 ipv6-long.invalid
    192.0.2.1 ipv6-long.invalid
    192.0.2.2 ipv6-long.invalid
    2001:db8::4 ipv4-long.invalid
    192.0.2.3 ipv4-long.invalid
    192.0.2.4 ipv4-long.invalid
    192.0.2.5 ipv4-long.invalid
    """)

    assert {:ok, [@ipv6_a, @ipv4_a, @ipv6_b, @ipv4_b, @ipv6_c]} =
             :happy_tcp.getaddrs(~c"ipv6-long.invalid")

    assert {:ok, [@ipv6_d, @ipv4_c, @ipv4_d, @ipv4_e]} =
             :happy_tcp.getaddrs(~c"ipv4-long.invalid")
  end

  test "getaddrs returns whichever address family succeeds" do
    install_test_hosts("""
    2001:db8::1 ipv6-only.invalid
    192.0.2.1 ipv4-only.invalid
    """)

    assert {:ok, [@ipv6_a]} = :happy_tcp.getaddrs(~c"ipv6-only.invalid")
    assert {:ok, [@ipv4_a]} = :happy_tcp.getaddrs(~c"ipv4-only.invalid")
  end

  test "getaddrs returns only ordinary numeric tuples for a local hostname" do
    hostname = install_dual_stack_test_host()

    assert {:ok, [@ipv6_loopback, @ipv4_loopback] = addresses} =
             :happy_tcp.getaddrs(hostname)

    assert Enum.all?(addresses, &numeric_ip?/1)
  end

  test "getaddrs preserves literal IPv4 and IPv6 inputs" do
    for address <- [@ipv4_loopback, @ipv6_loopback] do
      assert {:ok, [^address]} = :happy_tcp.getaddrs(address)
    end
  end

  test "getaddrs returns a deterministic error when both lookups fail" do
    install_test_hosts("127.0.0.1 another-host.invalid\n")

    assert {:error, :nxdomain} = :happy_tcp.getaddrs(~c"missing.invalid")
    assert {:error, :einval} = :happy_tcp.getaddrs({256, 0, 0, 1})
  end

  test "getaddrs/2 passes one shared OTP timer to both family lookups" do
    timer = :inet.start_timer(10_000)
    trace = start_call_trace([{:inet6_tcp, :getaddrs, 2}, {:inet_tcp, :getaddrs, 2}])
    test_pid = self()

    try do
      assert {:ok, [@ipv4_loopback]} = :happy_tcp.getaddrs(@ipv4_loopback, timer)

      assert_receive {:trace_event,
                      {:trace, ^test_pid, :call,
                       {:inet6_tcp, :getaddrs, [@ipv4_loopback, ^timer]}}}

      assert_receive {:trace_event,
                      {:trace, ^test_pid, :call, {:inet_tcp, :getaddrs, [@ipv4_loopback, ^timer]}}}
    after
      stop_call_trace(trace)
      _ = :inet.stop_timer(timer)
    end
  end

  test "per-call tcp_module configuration returns an ordinary gen_tcp socket" do
    with_listener(:inet_tcp, @ipv4_loopback, fn _listener, port ->
      assert {:ok, socket} =
               :gen_tcp.connect(
                 @ipv4_loopback,
                 port,
                 legacy_happy_opts(),
                 1_000
               )

      assert is_port(socket)
      assert {:ok, {@ipv4_loopback, ^port}} = :inet.peername(socket)
      :ok = :gen_tcp.close(socket)
    end)
  end

  test "VM-global tcp_module configuration is honored and restored exactly" do
    previous_tcp_module = :inet_db.tcp_module()
    :ok = :inet_db.set_tcp_module(:happy_tcp)

    on_exit(fn ->
      :ok = :inet_db.set_tcp_module(previous_tcp_module)
    end)

    with_listener(:inet_tcp, @ipv4_loopback, fn _listener, port ->
      trace = start_call_trace([{:happy_tcp, :getaddrs, 2}])
      test_pid = self()

      try do
        assert {:ok, socket} =
                 :gen_tcp.connect(
                   @ipv4_loopback,
                   port,
                   [{:inet_backend, :inet}, :binary, {:active, false}],
                   1_000
                 )

        assert_receive {:trace_event,
                        {:trace, ^test_pid, :call,
                         {:happy_tcp, :getaddrs, [@ipv4_loopback, _timer]}}}

        :ok = :gen_tcp.close(socket)
      after
        stop_call_trace(trace)
      end
    end)
  end

  @tag skip: @ipv6_skip
  test "gen_tcp sequentially falls through an immediate IPv6 failure to IPv4" do
    hostname = install_dual_stack_test_host()

    with_listener(:inet_tcp, @ipv4_loopback, fn listener, port ->
      assert {:error, :econnrefused} =
               :inet6_tcp.connect(@ipv6_loopback, port, [{:active, false}], 1_000)

      server =
        Task.async(fn ->
          {:ok, socket} = :inet_tcp.accept(listener, 2_000)
          result = :inet_tcp.recv(socket, 0, 2_000)
          :ok = :inet_tcp.close(socket)
          result
        end)

      trace = start_call_trace([{:happy_tcp, :connect, 4}])
      test_pid = self()

      try do
        assert {:ok, socket} =
                 :gen_tcp.connect(hostname, port, legacy_happy_opts(), 2_000)

        assert_receive {:trace_event,
                        {:trace, ^test_pid, :call,
                         {:happy_tcp, :connect, [@ipv6_loopback, ^port, _opts, _timeout]}}}

        assert_receive {:trace_event,
                        {:trace, ^test_pid, :call,
                         {:happy_tcp, :connect, [@ipv4_loopback, ^port, _opts, _timeout]}}}

        assert {:ok, {@ipv4_loopback, ^port}} = :inet.peername(socket)
        :ok = :gen_tcp.send(socket, "sequential fallback")
        assert {:ok, "sequential fallback"} = Task.await(server, 3_000)
        :ok = :gen_tcp.close(socket)
      after
        stop_call_trace(trace)
      end
    end)
  end

  test "IPv4 any, loopback, and sockaddr map bind forms do not crash dispatch" do
    for address <- [:any, :loopback] do
      bind_address = %{family: :inet, addr: address, port: 0}

      assert {:ok, listener} =
               :gen_tcp.listen(0, [
                 {:inet_backend, :inet},
                 {:tcp_module, :happy_tcp},
                 {:ifaddr, bind_address},
                 {:active, false}
               ])

      assert {:ok, {bound_address, _port}} = :inet.sockname(listener)
      assert tuple_size(bound_address) == 4
      :ok = :gen_tcp.close(listener)
    end
  end

  test "the last concrete bind option selects the IPv4 delegate" do
    assert {:ok, listener} =
             :gen_tcp.listen(0, [
               {:inet_backend, :inet},
               {:tcp_module, :happy_tcp},
               {:ip, @ipv6_loopback},
               {:ifaddr, %{family: :inet, addr: :loopback, port: 0}},
               {:active, false}
             ])

    assert {:ok, {@ipv4_loopback, _port}} = :inet.sockname(listener)
    :ok = :gen_tcp.close(listener)
  end

  @tag skip: @ipv6_skip
  test "the last concrete bind option selects the IPv6 delegate" do
    assert {:ok, listener} =
             :gen_tcp.listen(0, [
               {:inet_backend, :inet},
               {:tcp_module, :happy_tcp},
               {:ip, @ipv4_loopback},
               {:ifaddr, %{family: :inet6, addr: :loopback, port: 0}},
               {:active, false}
             ])

    assert {:ok, {@ipv6_loopback, _port}} = :inet.sockname(listener)
    :ok = :gen_tcp.close(listener)
  end

  @tag skip: @ipv6_skip
  test "symbolic IP bind forms use the IPv6 default without crashing dispatch" do
    for address <- [:any, :loopback] do
      assert {:ok, listener} =
               :gen_tcp.listen(0, [
                 {:inet_backend, :inet},
                 {:tcp_module, :happy_tcp},
                 {:ip, address},
                 {:active, false}
               ])

      assert {:ok, {bound_address, _port}} = :inet.sockname(listener)
      assert tuple_size(bound_address) == 8
      :ok = :gen_tcp.close(listener)
    end
  end

  test "IPv4 sockaddr map connect accepts symbolic addresses" do
    for address <- [:any, :loopback] do
      with_listener(:inet_tcp, @ipv4_loopback, fn _listener, port ->
        sock_addr = %{family: :inet, addr: address, port: port}

        assert {:ok, socket} =
                 :gen_tcp.connect(sock_addr, legacy_happy_opts(), 1_000)

        assert {:ok, {@ipv4_loopback, ^port}} = :inet.peername(socket)
        :ok = :gen_tcp.close(socket)
      end)
    end
  end

  @tag skip: @ipv6_skip
  test "IPv6 sockaddr map connect accepts symbolic addresses" do
    for address <- [:any, :loopback] do
      with_listener(:inet6_tcp, @ipv6_loopback, fn _listener, port ->
        sock_addr = %{family: :inet6, addr: address, port: port}

        assert {:ok, socket} =
                 :gen_tcp.connect(sock_addr, legacy_happy_opts(), 1_000)

        assert {:ok, {@ipv6_loopback, ^port}} = :inet.peername(socket)
        :ok = :gen_tcp.close(socket)
      end)
    end
  end

  test "accept callback dispatches to the IPv4 module" do
    exercise_accept(:inet_tcp, @ipv4_loopback)
  end

  @tag skip: @ipv6_skip
  test "accept callback dispatches to the IPv6 module" do
    exercise_accept(:inet6_tcp, @ipv6_loopback)
  end

  test "family and address translation callbacks have explicit IPv6 defaults" do
    sock_addr = %{family: :inet, addr: @ipv4_loopback, port: 1234}

    assert :inet6 = :happy_tcp.family()
    assert @ipv6_any = :happy_tcp.translate_ip(:any)
    assert @ipv6_loopback = :happy_tcp.translate_ip(:loopback)
    assert @ipv4_loopback = :happy_tcp.translate_ip(@ipv4_loopback)
    assert ^sock_addr = :happy_tcp.translate_ip(sock_addr)
  end

  defp exercise_accept(mod, address) do
    with_listener(mod, address, fn listener, port ->
      acceptor =
        Task.async(fn ->
          {:ok, server} = :happy_tcp.accept(listener, 1_000)
          {:ok, peer} = :inet.peername(server)
          :ok = mod.close(server)
          peer
        end)

      assert {:ok, client} = mod.connect(address, port, [{:active, false}], 1_000)
      {peer_address, _peer_port} = Task.await(acceptor, 2_000)
      assert tuple_size(peer_address) == tuple_size(address)

      :ok = mod.close(client)
    end)
  end

  defp with_listener(mod, address, fun) do
    {:ok, listener} = mod.listen(0, [{:ip, address}, :binary, {:active, false}])
    {:ok, {^address, port}} = :inet.sockname(listener)

    try do
      fun.(listener, port)
    after
      :ok = mod.close(listener)
    end
  end

  defp legacy_happy_opts do
    [
      {:inet_backend, :inet},
      {:tcp_module, :happy_tcp},
      :binary,
      {:active, false}
    ]
  end

  defp numeric_ip?(address) when is_tuple(address) and tuple_size(address) == 4 do
    address
    |> Tuple.to_list()
    |> Enum.all?(&(&1 in 0..255))
  end

  defp numeric_ip?(address) when is_tuple(address) and tuple_size(address) == 8 do
    address
    |> Tuple.to_list()
    |> Enum.all?(&(&1 in 0..65_535))
  end

  defp numeric_ip?(_address), do: false

  defp install_dual_stack_test_host do
    hostname = ~c"happy-tcp-loopback.invalid"
    install_test_hosts("::1 happy-tcp-loopback.invalid\n127.0.0.1 happy-tcp-loopback.invalid\n")
    hostname
  end

  defp install_test_hosts(contents) do
    previous_lookup = :inet_db.res_option(:lookup)
    previous_hosts_file = :inet_db.res_option(:hosts_file)

    hosts_file =
      Path.join(
        System.tmp_dir!(),
        "happy_tcp_hosts_#{System.unique_integer([:monotonic, :positive])}"
      )

    File.write!(hosts_file, contents)

    on_exit(fn ->
      :ok = :inet_db.set_hosts_file(previous_hosts_file)
      :ok = :inet_db.set_lookup(previous_lookup)
      :ok = File.rm(hosts_file)
    end)

    :ok = :inet_db.set_hosts_file(String.to_charlist(hosts_file))
    :ok = :inet_db.set_lookup([:file])
    :ok
  end

  defp start_call_trace(mfas) do
    owner = self()
    tracer = spawn_link(fn -> forward_trace_events(owner) end)

    Enum.each(mfas, fn {mod, _function, _arity} = mfa ->
      {:module, ^mod} = :code.ensure_loaded(mod)
      1 = :erlang.trace_pattern(mfa, true, [])
    end)

    1 = :erlang.trace(owner, true, [:call, {:tracer, tracer}])
    {owner, tracer, mfas}
  end

  defp stop_call_trace({owner, tracer, mfas}) do
    1 = :erlang.trace(owner, false, [:call])

    Enum.each(mfas, fn mfa ->
      1 = :erlang.trace_pattern(mfa, false, [])
    end)

    send(tracer, :stop)
    :ok
  end

  defp forward_trace_events(owner) do
    receive do
      :stop ->
        :ok

      event ->
        send(owner, {:trace_event, event})
        forward_trace_events(owner)
    end
  end
end
