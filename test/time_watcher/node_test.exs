defmodule TimeWatcher.NodeTest do
  use ExUnit.Case, async: true

  alias TimeWatcher.Node

  describe "daemon_node_name/0" do
    test "returns configured daemon node name" do
      # In test env, configured to :tw_watcher_test@localhost
      assert Node.daemon_node_name() == :tw_watcher_test@localhost
    end

    test "defaults to :tw_watcher@localhost when not configured" do
      # Temporarily clear the config
      original = Application.get_env(:time_watcher, :daemon_node_name)
      Application.delete_env(:time_watcher, :daemon_node_name)

      assert Node.daemon_node_name() == :tw_watcher@localhost

      # Restore
      if original, do: Application.put_env(:time_watcher, :daemon_node_name, original)
    end
  end

  describe "client_node_name/0" do
    test "returns unique client node names" do
      name1 = Node.client_node_name()
      name2 = Node.client_node_name()

      assert is_atom(name1)
      assert is_atom(name2)
      assert name1 != name2
      assert Atom.to_string(name1) =~ ~r/^tw_client_\d+@localhost$/
      assert Atom.to_string(name2) =~ ~r/^tw_client_\d+@localhost$/
    end
  end

  describe "cookie_path/0" do
    test "returns path in .local/share/time_watcher" do
      path = Node.cookie_path()
      assert path =~ ".local/share/time_watcher/.erlang.cookie"
    end
  end

  describe "generate_cookie_value/0" do
    test "generates a cryptographically secure cookie" do
      cookie1 = Node.generate_cookie_value()
      cookie2 = Node.generate_cookie_value()

      assert is_binary(cookie1)
      assert is_binary(cookie2)
      assert cookie1 != cookie2
      # Should be 32 bytes hex encoded = 64 chars
      assert byte_size(cookie1) == 64
    end
  end

  describe "ensure_cookie/0" do
    setup do
      test_dir =
        Path.join(System.tmp_dir!(), "tw_node_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(test_dir)
      on_exit(fn -> File.rm_rf!(test_dir) end)
      %{test_dir: test_dir}
    end

    test "creates cookie file if it doesn't exist", %{test_dir: test_dir} do
      cookie_path = Path.join(test_dir, ".erlang.cookie")
      refute File.exists?(cookie_path)

      cookie = Node.ensure_cookie(cookie_path)

      assert is_atom(cookie)
      assert File.exists?(cookie_path)
      assert File.stat!(cookie_path).mode |> Bitwise.band(0o777) == 0o600
    end

    test "reads existing cookie file", %{test_dir: test_dir} do
      cookie_path = Path.join(test_dir, ".erlang.cookie")
      File.write!(cookie_path, "existing_cookie_value")

      cookie = Node.ensure_cookie(cookie_path)

      assert cookie == :existing_cookie_value
    end
  end
end
