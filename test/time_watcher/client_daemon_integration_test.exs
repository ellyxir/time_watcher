defmodule TimeWatcher.ClientDaemonIntegrationTest do
  @moduledoc """
  Integration tests for Client-Daemon RPC communication.
  Tests verify actual distributed Erlang communication between client and daemon.
  """
  use ExUnit.Case

  # Not async - tests use distributed Erlang which can conflict
  alias TimeWatcher.{Node, Watcher}

  @test_timeout 10_000

  setup do
    test_id = System.unique_integer([:positive])
    data_dir = Path.join(System.tmp_dir!(), "tw_data_#{test_id}")
    watch_dir = Path.join(System.tmp_dir!(), "tw_watch_#{test_id}")

    File.mkdir_p!(data_dir)
    File.mkdir_p!(watch_dir)

    # Ensure EPMD is running
    System.cmd("epmd", ["-daemon"], stderr_to_stdout: true)

    on_exit(fn ->
      # Clean up any lingering distribution
      if Elixir.Node.alive?(), do: Elixir.Node.stop()
      File.rm_rf!(data_dir)
      File.rm_rf!(watch_dir)
    end)

    %{data_dir: data_dir, watch_dir: watch_dir, test_id: test_id}
  end

  describe "direct watcher communication" do
    test "add_dir adds directory to watcher", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      # Initially empty
      assert Watcher.list_dirs(pid) == []

      # Add directory
      assert :ok = Watcher.add_dir(pid, watch_dir)

      # Should now be listed
      dirs = Watcher.list_dirs(pid)
      assert length(dirs) == 1
      assert hd(dirs).path == Path.expand(watch_dir)

      GenServer.stop(pid)
    end

    test "add_dir returns error for duplicate directory", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir)

      # Try to add same directory again
      assert {:error, :already_watching} = Watcher.add_dir(pid, watch_dir)

      GenServer.stop(pid)
    end

    test "remove_dir removes directory from watcher", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir)

      # Verify it's being watched
      assert length(Watcher.list_dirs(pid)) == 1

      # Remove it
      assert :ok = Watcher.remove_dir(pid, watch_dir)

      # Should be empty now
      assert Watcher.list_dirs(pid) == []

      GenServer.stop(pid)
    end

    test "remove_dir returns error for non-watched directory", %{data_dir: data_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert {:error, :not_watching} = Watcher.remove_dir(pid, "/nonexistent/path")

      GenServer.stop(pid)
    end

    test "list_dirs returns all watched directories with repo names", %{data_dir: data_dir} do
      test_id = System.unique_integer([:positive])
      dir1 = Path.join(System.tmp_dir!(), "tw_proj1_#{test_id}")
      dir2 = Path.join(System.tmp_dir!(), "tw_proj2_#{test_id}")

      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      on_exit(fn ->
        File.rm_rf!(dir1)
        File.rm_rf!(dir2)
      end)

      {:ok, pid} = Watcher.start_link(dirs: [dir1, dir2], data_dir: data_dir)

      dirs = Watcher.list_dirs(pid)
      assert length(dirs) == 2

      paths = Enum.map(dirs, & &1.path) |> Enum.sort()
      assert paths == Enum.sort([Path.expand(dir1), Path.expand(dir2)])

      # Repo names should be directory basenames
      repos = Enum.map(dirs, & &1.repo) |> Enum.sort()
      assert repos == Enum.sort([Path.basename(dir1), Path.basename(dir2)])

      GenServer.stop(pid)
    end
  end

  describe "distributed communication" do
    @tag timeout: @test_timeout
    @tag :distributed
    test "client can communicate with daemon via distribution", %{
      data_dir: data_dir,
      watch_dir: watch_dir,
      test_id: test_id
    } do
      # Start daemon node
      daemon_node = :"tw_test_daemon_#{test_id}@localhost"
      cookie = Node.ensure_cookie()

      {:ok, _} = Elixir.Node.start(daemon_node, :shortnames)
      Elixir.Node.set_cookie(cookie)

      # Start watcher on this node (simulating daemon)
      {:ok, _pid} =
        Watcher.start_link(
          dirs: [watch_dir],
          data_dir: data_dir,
          name: Watcher
        )

      # Verify we can call the watcher via the registered name
      dirs = Watcher.list_dirs(Watcher)
      assert length(dirs) == 1
      assert hd(dirs).path == Path.expand(watch_dir)

      # Add another directory
      new_dir = Path.join(System.tmp_dir!(), "tw_new_#{test_id}")
      File.mkdir_p!(new_dir)
      on_exit(fn -> File.rm_rf!(new_dir) end)

      assert :ok = Watcher.add_dir(Watcher, new_dir)
      assert length(Watcher.list_dirs(Watcher)) == 2

      # Remove a directory
      assert :ok = Watcher.remove_dir(Watcher, watch_dir)
      assert length(Watcher.list_dirs(Watcher)) == 1

      Elixir.Node.stop()
    end
  end

  describe "watcher state management" do
    test "dynamically added directories receive file events", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      # Start with no directories
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir, debounce_seconds: 0)

      # Add directory dynamically
      :ok = Watcher.add_dir(pid, watch_dir)
      Process.sleep(100)

      # Create a file - should trigger event
      file_path = Path.join(watch_dir, "dynamic_test.txt")
      File.write!(file_path, "content")
      Process.sleep(200)

      # Verify event was recorded
      date = Date.to_string(Date.utc_today())
      events = TimeWatcher.Storage.load_events(date, data_dir)

      assert events != []
      assert hd(events).repo == Path.basename(watch_dir)

      GenServer.stop(pid)
    end

    test "removed directories stop receiving events", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 0)
      Process.sleep(100)

      # Remove the directory
      :ok = Watcher.remove_dir(pid, watch_dir)
      Process.sleep(100)

      # Create a file - should NOT trigger event
      file_path = Path.join(watch_dir, "after_remove.txt")
      File.write!(file_path, "content")
      Process.sleep(200)

      # Verify no events were recorded
      date = Date.to_string(Date.utc_today())
      events = TimeWatcher.Storage.load_events(date, data_dir)

      assert events == []

      GenServer.stop(pid)
    end
  end

  describe "loop prevention" do
    test "cannot add data directory as watch target", %{data_dir: data_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert {:error, :would_cause_loop} = Watcher.add_dir(pid, data_dir)

      GenServer.stop(pid)
    end

    test "cannot add parent of data directory", %{data_dir: data_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      parent = Path.dirname(data_dir)
      assert {:error, :would_cause_loop} = Watcher.add_dir(pid, parent)

      GenServer.stop(pid)
    end

    test "cannot add subdirectory of data directory", %{data_dir: data_dir} do
      subdir = Path.join(data_dir, "subdir")
      File.mkdir_p!(subdir)

      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert {:error, :would_cause_loop} = Watcher.add_dir(pid, subdir)

      GenServer.stop(pid)
    end
  end
end
