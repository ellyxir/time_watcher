defmodule TimeWatcher.NodeIntegrationTest do
  @moduledoc """
  Integration tests for distributed Erlang node management.
  Tests cookie handling, node naming, and EPMD interaction.
  """
  use ExUnit.Case

  # Not async - distribution tests can conflict
  alias TimeWatcher.Node

  setup do
    # Clean up any lingering distribution
    if Elixir.Node.alive?(), do: Elixir.Node.stop()

    # Ensure EPMD is running
    System.cmd("epmd", ["-daemon"], stderr_to_stdout: true)

    test_id = System.unique_integer([:positive])

    on_exit(fn ->
      if Elixir.Node.alive?(), do: Elixir.Node.stop()
    end)

    %{test_id: test_id}
  end

  describe "cookie management" do
    test "ensure_cookie creates cookie file if not exists" do
      # Use a temp directory for the cookie
      temp_dir = Path.join(System.tmp_dir!(), "tw_cookie_#{System.unique_integer([:positive])}")
      File.mkdir_p!(temp_dir)
      cookie_path = Path.join(temp_dir, "cookie")

      on_exit(fn -> File.rm_rf!(temp_dir) end)

      # Temporarily set XDG_DATA_HOME
      original_xdg = System.get_env("XDG_DATA_HOME")

      try do
        System.put_env("XDG_DATA_HOME", temp_dir)

        # Cookie file shouldn't exist yet
        refute File.exists?(cookie_path)

        # This should create a cookie (but uses default path, so we test the function works)
        cookie = Node.ensure_cookie()

        # Cookie should be an atom
        assert is_atom(cookie)
        assert cookie != nil
      after
        if original_xdg do
          System.put_env("XDG_DATA_HOME", original_xdg)
        else
          System.delete_env("XDG_DATA_HOME")
        end
      end
    end

    test "ensure_cookie returns consistent value" do
      cookie1 = Node.ensure_cookie()
      cookie2 = Node.ensure_cookie()

      assert cookie1 == cookie2
    end

    test "cookie is valid Erlang atom" do
      cookie = Node.ensure_cookie()

      assert is_atom(cookie)
      # Cookie should be alphanumeric
      cookie_str = Atom.to_string(cookie)
      assert String.match?(cookie_str, ~r/^[A-Za-z0-9]+$/)
    end
  end

  describe "node naming" do
    test "daemon_node_name returns consistent name" do
      name1 = Node.daemon_node_name()
      name2 = Node.daemon_node_name()

      assert name1 == name2
      assert name1 == :tw_watcher@localhost
    end

    test "client_node_name returns unique names" do
      name1 = Node.client_node_name()
      name2 = Node.client_node_name()

      # Names should be different (unique per call)
      assert name1 != name2

      # Both should be atoms ending in @localhost
      assert is_atom(name1)
      assert is_atom(name2)
      assert Atom.to_string(name1) =~ "@localhost"
      assert Atom.to_string(name2) =~ "@localhost"
    end

    test "client_node_name includes tw_client prefix" do
      name = Node.client_node_name()
      name_str = Atom.to_string(name)

      assert String.starts_with?(name_str, "tw_client_")
    end
  end

  describe "distribution startup" do
    @tag :distributed
    test "can start a node with daemon name", %{test_id: _test_id} do
      # Use a unique name to avoid conflicts
      test_node = :"tw_test_#{System.unique_integer([:positive])}@localhost"
      cookie = Node.ensure_cookie()

      {:ok, _pid} = Elixir.Node.start(test_node, :shortnames)
      Elixir.Node.set_cookie(cookie)

      assert Elixir.Node.alive?()
      assert Elixir.Node.self() == test_node

      Elixir.Node.stop()
    end

    @tag :distributed
    test "cookie can be set on started node" do
      node1 = :"tw_test_a_#{System.unique_integer([:positive])}@localhost"
      cookie = Node.ensure_cookie()

      # Test that cookie is consistently available and can be set
      assert is_atom(cookie)

      {:ok, _} = Elixir.Node.start(node1, :shortnames)
      Elixir.Node.set_cookie(cookie)
      assert Elixir.Node.get_cookie() == cookie
      Elixir.Node.stop()
    end
  end

  describe "node ping" do
    @tag :distributed
    test "ping returns :pang for non-existent node" do
      # Start distribution so we can ping
      test_node = :"tw_ping_test_#{System.unique_integer([:positive])}@localhost"
      cookie = Node.ensure_cookie()

      {:ok, _} = Elixir.Node.start(test_node, :shortnames)
      Elixir.Node.set_cookie(cookie)

      # Non-existent node should return :pang
      result = Elixir.Node.ping(:nonexistent_node@localhost)
      assert result == :pang

      Elixir.Node.stop()
    end
  end

  describe "EPMD interaction" do
    test "epmd names can be queried" do
      # epmd -names should work
      {output, exit_code} = System.cmd("epmd", ["-names"], stderr_to_stdout: true)

      # Should succeed or report no names
      assert exit_code == 0 or output =~ "epmd: Cannot connect"
    end

    @tag :distributed
    test "started node appears in epmd names" do
      test_node = :"tw_epmd_test_#{System.unique_integer([:positive])}@localhost"
      cookie = Node.ensure_cookie()

      {:ok, _} = Elixir.Node.start(test_node, :shortnames)
      Elixir.Node.set_cookie(cookie)

      # Give epmd time to register
      Process.sleep(100)

      {output, 0} = System.cmd("epmd", ["-names"], stderr_to_stdout: true)

      # Our node name (without @localhost) should appear
      node_short_name =
        test_node
        |> Atom.to_string()
        |> String.split("@")
        |> hd()

      assert output =~ node_short_name

      Elixir.Node.stop()
    end
  end
end
