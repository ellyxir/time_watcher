defmodule TimeWatcher.WatcherTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias TimeWatcher.Watcher

  setup do
    data_dir =
      Path.join(System.tmp_dir!(), "tw_watcher_test_#{System.unique_integer([:positive])}")

    watch_dir = Path.join(System.tmp_dir!(), "tw_watch_#{System.unique_integer([:positive])}")
    File.mkdir_p!(data_dir)
    File.mkdir_p!(watch_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      File.rm_rf!(watch_dir)
    end)

    %{data_dir: data_dir, watch_dir: watch_dir}
  end

  describe "add_dir/2" do
    test "adds a directory to be watched", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert :ok = Watcher.add_dir(pid, watch_dir)

      dirs = Watcher.list_dirs(pid)
      assert length(dirs) == 1
      assert hd(dirs).path == Path.expand(watch_dir)

      GenServer.stop(pid)
    end

    test "returns error when directory already watched", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir)

      assert {:error, :already_watching} = Watcher.add_dir(pid, watch_dir)

      GenServer.stop(pid)
    end

    test "adds multiple directories", %{data_dir: data_dir, watch_dir: watch_dir} do
      watch_dir2 = Path.join(System.tmp_dir!(), "tw_watch2_#{System.unique_integer([:positive])}")
      File.mkdir_p!(watch_dir2)
      on_exit(fn -> File.rm_rf!(watch_dir2) end)

      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir)

      assert :ok = Watcher.add_dir(pid, watch_dir2)

      dirs = Watcher.list_dirs(pid)
      assert length(dirs) == 2

      GenServer.stop(pid)
    end

    test "returns error when adding the data directory itself", %{data_dir: data_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert {:error, :would_cause_loop} = Watcher.add_dir(pid, data_dir)
      assert Watcher.list_dirs(pid) == []

      GenServer.stop(pid)
    end

    test "returns error when adding a subdirectory of the data directory", %{data_dir: data_dir} do
      subdir = Path.join(data_dir, "2026-02-27")
      File.mkdir_p!(subdir)

      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert {:error, :would_cause_loop} = Watcher.add_dir(pid, subdir)
      assert Watcher.list_dirs(pid) == []

      GenServer.stop(pid)
    end

    test "returns error when adding a parent directory of the data directory", %{
      data_dir: data_dir
    } do
      parent_dir = Path.dirname(data_dir)

      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert {:error, :would_cause_loop} = Watcher.add_dir(pid, parent_dir)
      assert Watcher.list_dirs(pid) == []

      GenServer.stop(pid)
    end

    test "allows directory with similar prefix to data directory", %{data_dir: data_dir} do
      # e.g., data_dir is /tmp/time_watcher, watch_dir is /tmp/time_watcher_project
      # These should NOT conflict - they are sibling directories
      similar_dir = data_dir <> "_project"
      File.mkdir_p!(similar_dir)
      on_exit(fn -> File.rm_rf!(similar_dir) end)

      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert :ok = Watcher.add_dir(pid, similar_dir)
      assert length(Watcher.list_dirs(pid)) == 1

      GenServer.stop(pid)
    end

    test "returns error when directory does not exist", %{data_dir: data_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert {:error, :directory_not_found} = Watcher.add_dir(pid, "/nonexistent/path/12345")

      GenServer.stop(pid)
    end
  end

  describe "list_dirs/1" do
    test "returns empty list when no directories watched", %{data_dir: data_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert Watcher.list_dirs(pid) == []

      GenServer.stop(pid)
    end

    test "returns watched directories with paths and repos", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir)

      dirs = Watcher.list_dirs(pid)
      assert length(dirs) == 1

      dir = hd(dirs)
      assert dir.path == Path.expand(watch_dir)
      assert dir.repo == Path.basename(watch_dir)

      GenServer.stop(pid)
    end

    test "lists multiple directories initialized at start", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      watch_dir2 = Path.join(System.tmp_dir!(), "tw_watch2_#{System.unique_integer([:positive])}")
      File.mkdir_p!(watch_dir2)
      on_exit(fn -> File.rm_rf!(watch_dir2) end)

      {:ok, pid} = Watcher.start_link(dirs: [watch_dir, watch_dir2], data_dir: data_dir)

      dirs = Watcher.list_dirs(pid)
      assert length(dirs) == 2

      paths = Enum.map(dirs, & &1.path)
      assert Path.expand(watch_dir) in paths
      assert Path.expand(watch_dir2) in paths

      GenServer.stop(pid)
    end

    test "excludes data directory from initial dirs to prevent loops", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir, data_dir], data_dir: data_dir)

      dirs = Watcher.list_dirs(pid)
      assert length(dirs) == 1

      paths = Enum.map(dirs, & &1.path)
      assert Path.expand(watch_dir) in paths
      refute Path.expand(data_dir) in paths

      GenServer.stop(pid)
    end

    test "skips non-existent directories on init without crashing", %{data_dir: data_dir} do
      {:ok, pid} =
        Watcher.start_link(dirs: ["/nonexistent/path/12345"], data_dir: data_dir)

      assert Watcher.list_dirs(pid) == []

      GenServer.stop(pid)
    end
  end

  describe "remove_dir/2" do
    test "removes a watched directory", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir)

      assert :ok = Watcher.remove_dir(pid, watch_dir)
      assert Watcher.list_dirs(pid) == []

      GenServer.stop(pid)
    end

    test "returns error when directory not watched", %{data_dir: data_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [], data_dir: data_dir)

      assert {:error, :not_watching} = Watcher.remove_dir(pid, "/nonexistent")

      GenServer.stop(pid)
    end

    test "stops the file watcher for removed directory", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir)

      # Get initial state to check watcher pid
      state = :sys.get_state(pid)
      expanded_dir = Path.expand(watch_dir)
      watcher_pid = Map.get(state.watcher_pids, expanded_dir)
      assert Process.alive?(watcher_pid)

      assert :ok = Watcher.remove_dir(pid, watch_dir)

      # Watcher should be stopped
      refute Process.alive?(watcher_pid)

      GenServer.stop(pid)
    end
  end

  describe "detect_repo/1" do
    test "extracts basename of watched directory" do
      assert Watcher.detect_repo("/home/user/projects/my_app") == "my_app"
    end

    test "handles trailing slash" do
      assert Watcher.detect_repo("/home/user/projects/my_app/") == "my_app"
    end
  end

  describe "nested directories" do
    test "file in nested watched dir uses most specific repo", %{data_dir: data_dir} do
      parent_dir = Path.join(System.tmp_dir!(), "tw_parent_#{System.unique_integer([:positive])}")
      child_dir = Path.join(parent_dir, "child")
      File.mkdir_p!(child_dir)
      on_exit(fn -> File.rm_rf!(parent_dir) end)

      {:ok, pid} = Watcher.start_link(dirs: [parent_dir, child_dir], data_dir: data_dir)

      # Simulate event for file in child directory
      file_path = Path.join(child_dir, "test.ex")
      send(pid, {:file_event, self(), {file_path, [:modified]}})
      Process.sleep(100)

      # Check that the event was recorded with the child repo, not parent
      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      events =
        case File.ls(date_dir) do
          {:ok, files} ->
            files
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.map(fn file ->
              {:ok, content} = File.read(Path.join(date_dir, file))
              Jason.decode!(content)
            end)

          _ ->
            []
        end

      assert length(events) == 1
      assert hd(events)["repo"] == "child"

      GenServer.stop(pid)
    end
  end

  describe "map_event_type/1" do
    test "maps :created" do
      assert Watcher.map_event_type([:created]) == :created
    end

    test "maps :modified" do
      assert Watcher.map_event_type([:modified]) == :modified
    end

    test "maps :removed to :deleted" do
      assert Watcher.map_event_type([:removed]) == :deleted
    end

    test "maps :deleted to :deleted (linux inotify)" do
      assert Watcher.map_event_type([:deleted]) == :deleted
    end

    test "maps :renamed to :modified" do
      assert Watcher.map_event_type([:renamed]) == :modified
    end

    test "defaults to :modified for unknown" do
      assert Watcher.map_event_type([:attribute]) == :modified
    end
  end

  describe "multiple directory events" do
    test "records events from multiple watched directories", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      watch_dir2 = Path.join(System.tmp_dir!(), "tw_watch2_#{System.unique_integer([:positive])}")
      File.mkdir_p!(watch_dir2)
      on_exit(fn -> File.rm_rf!(watch_dir2) end)

      {:ok, pid} = Watcher.start_link(dirs: [watch_dir, watch_dir2], data_dir: data_dir)

      # Simulate events from both directories
      path1 = Path.join(watch_dir, "file1.ex")
      path2 = Path.join(watch_dir2, "file2.ex")

      send(pid, {:file_event, self(), {path1, [:modified]}})
      Process.sleep(50)
      send(pid, {:file_event, self(), {path2, [:modified]}})
      Process.sleep(50)

      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      events =
        case File.ls(date_dir) do
          {:ok, files} ->
            files
            |> Enum.filter(&String.ends_with?(&1, ".json"))
            |> Enum.map(fn file ->
              {:ok, content} = File.read(Path.join(date_dir, file))
              Jason.decode!(content)
            end)

          _ ->
            []
        end

      assert length(events) == 2

      repos = Enum.map(events, & &1["repo"])
      assert Path.basename(watch_dir) in repos
      assert Path.basename(watch_dir2) in repos

      GenServer.stop(pid)
    end
  end

  describe "debounce logic" do
    test "drops rapid duplicate file events", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 60)

      # Simulate two rapid events for the same file
      path = Path.join(watch_dir, "foo.ex")
      send(pid, {:file_event, self(), {path, [:modified]}})
      Process.sleep(50)
      send(pid, {:file_event, self(), {path, [:modified]}})
      Process.sleep(50)

      # Check state - should only have one entry in last_event_at
      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      event_count =
        case File.ls(date_dir) do
          {:ok, files} -> length(Enum.filter(files, &String.ends_with?(&1, ".json")))
          _ -> 0
        end

      assert event_count == 1
      GenServer.stop(pid)
    end

    test "allows events after debounce window expires", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 0)

      path = Path.join(watch_dir, "foo.ex")
      send(pid, {:file_event, self(), {path, [:modified]}})
      Process.sleep(100)
      send(pid, {:file_event, self(), {path, [:modified]}})
      Process.sleep(100)

      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      event_count =
        case File.ls(date_dir) do
          {:ok, files} -> length(Enum.filter(files, &String.ends_with?(&1, ".json")))
          _ -> 0
        end

      assert event_count == 2
      GenServer.stop(pid)
    end
  end

  describe "ignore_patterns" do
    test "ignores files matching glob patterns", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} =
        Watcher.start_link(
          dirs: [watch_dir],
          data_dir: data_dir,
          ignore_patterns: [".watchman-cookie-*"]
        )

      # Simulate event for an ignored file
      path = Path.join(watch_dir, ".watchman-cookie-nixos-12345")
      send(pid, {:file_event, self(), {path, [:created]}})
      Process.sleep(50)

      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      event_count =
        case File.ls(date_dir) do
          {:ok, files} -> length(Enum.filter(files, &String.ends_with?(&1, ".json")))
          {:error, :enoent} -> 0
        end

      assert event_count == 0
      GenServer.stop(pid)
    end

    test "records files not matching ignore patterns", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} =
        Watcher.start_link(
          dirs: [watch_dir],
          data_dir: data_dir,
          ignore_patterns: [".watchman-cookie-*"]
        )

      # Simulate event for a normal file
      path = Path.join(watch_dir, "my_module.ex")
      send(pid, {:file_event, self(), {path, [:modified]}})
      Process.sleep(50)

      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      event_count =
        case File.ls(date_dir) do
          {:ok, files} -> length(Enum.filter(files, &String.ends_with?(&1, ".json")))
          {:error, :enoent} -> 0
        end

      assert event_count == 1
      GenServer.stop(pid)
    end

    test "supports multiple ignore patterns", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} =
        Watcher.start_link(
          dirs: [watch_dir],
          data_dir: data_dir,
          ignore_patterns: [".watchman-cookie-*", "*.swp", "*~"]
        )

      # Simulate events for various ignored files
      paths = [
        Path.join(watch_dir, ".watchman-cookie-12345"),
        Path.join(watch_dir, "file.swp"),
        Path.join(watch_dir, "backup~")
      ]

      for path <- paths do
        send(pid, {:file_event, self(), {path, [:created]}})
        Process.sleep(20)
      end

      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      event_count =
        case File.ls(date_dir) do
          {:ok, files} -> length(Enum.filter(files, &String.ends_with?(&1, ".json")))
          {:error, :enoent} -> 0
        end

      assert event_count == 0
      GenServer.stop(pid)
    end

    test "empty ignore_patterns ignores nothing", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} =
        Watcher.start_link(
          dirs: [watch_dir],
          data_dir: data_dir,
          ignore_patterns: []
        )

      path = Path.join(watch_dir, ".watchman-cookie-12345")
      send(pid, {:file_event, self(), {path, [:created]}})
      Process.sleep(50)

      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      event_count =
        case File.ls(date_dir) do
          {:ok, files} -> length(Enum.filter(files, &String.ends_with?(&1, ".json")))
          {:error, :enoent} -> 0
        end

      assert event_count == 1
      GenServer.stop(pid)
    end

    test "supports single character wildcard pattern", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} =
        Watcher.start_link(
          dirs: [watch_dir],
          data_dir: data_dir,
          ignore_patterns: ["file?.txt"]
        )

      # Should ignore file1.txt but not file12.txt
      path_ignored = Path.join(watch_dir, "file1.txt")
      path_not_ignored = Path.join(watch_dir, "file12.txt")

      send(pid, {:file_event, self(), {path_ignored, [:created]}})
      Process.sleep(20)
      send(pid, {:file_event, self(), {path_not_ignored, [:created]}})
      Process.sleep(50)

      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      event_count =
        case File.ls(date_dir) do
          {:ok, files} -> length(Enum.filter(files, &String.ends_with?(&1, ".json")))
          {:error, :enoent} -> 0
        end

      assert event_count == 1
      GenServer.stop(pid)
    end

    test "no ignore_patterns option ignores nothing", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} =
        Watcher.start_link(
          dirs: [watch_dir],
          data_dir: data_dir
        )

      path = Path.join(watch_dir, ".watchman-cookie-12345")
      send(pid, {:file_event, self(), {path, [:created]}})
      Process.sleep(50)

      date_dir = Path.join(data_dir, Date.to_string(Date.utc_today()))

      event_count =
        case File.ls(date_dir) do
          {:ok, files} -> length(Enum.filter(files, &String.ends_with?(&1, ".json")))
          {:error, :enoent} -> 0
        end

      assert event_count == 1
      GenServer.stop(pid)
    end
  end

  describe "verbose mode" do
    test "prints watched repos on init when verbose", %{data_dir: data_dir, watch_dir: watch_dir} do
      output =
        capture_io(fn ->
          {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, verbose: true)
          GenServer.stop(pid)
        end)

      assert output =~ "Watching:"
      assert output =~ Path.basename(watch_dir)
    end

    test "does not print on init when verbose is false", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      output =
        capture_io(fn ->
          {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, verbose: false)
          GenServer.stop(pid)
        end)

      assert output == ""
    end

    test "prints added repo when verbose", %{data_dir: data_dir, watch_dir: watch_dir} do
      watch_dir2 = Path.join(System.tmp_dir!(), "tw_watch2_#{System.unique_integer([:positive])}")
      File.mkdir_p!(watch_dir2)
      on_exit(fn -> File.rm_rf!(watch_dir2) end)

      output =
        capture_io(fn ->
          {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, verbose: true)
          Watcher.add_dir(pid, watch_dir2)
          GenServer.stop(pid)
        end)

      assert output =~ "Added:"
      assert output =~ Path.basename(watch_dir2)
    end

    test "prints event when verbose and file changes", %{data_dir: data_dir, watch_dir: watch_dir} do
      output =
        capture_io(fn ->
          {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, verbose: true)
          path = Path.join(watch_dir, "test.ex")
          send(pid, {:file_event, self(), {path, [:modified]}})
          Process.sleep(100)
          GenServer.stop(pid)
        end)

      assert output =~ "modified"
      assert output =~ Path.basename(watch_dir)
      assert output =~ "test.ex"
    end
  end
end
