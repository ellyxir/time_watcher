defmodule TimeWatcher.WatcherTest do
  use ExUnit.Case, async: false

  alias TimeWatcher.Watcher

  describe "detect_repo/1" do
    test "extracts basename of watched directory" do
      assert Watcher.detect_repo("/home/user/projects/my_app") == "my_app"
    end

    test "handles trailing slash" do
      assert Watcher.detect_repo("/home/user/projects/my_app/") == "my_app"
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

    test "maps :renamed to :modified" do
      assert Watcher.map_event_type([:renamed]) == :modified
    end

    test "defaults to :modified for unknown" do
      assert Watcher.map_event_type([:attribute]) == :modified
    end
  end

  describe "debounce logic" do
    setup do
      data_dir =
        Path.join(System.tmp_dir!(), "tw_watcher_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(data_dir)
      on_exit(fn -> File.rm_rf!(data_dir) end)
      %{data_dir: data_dir}
    end

    test "drops rapid duplicate file events", %{data_dir: data_dir} do
      watch_dir = Path.join(System.tmp_dir!(), "tw_watch_#{System.unique_integer([:positive])}")
      File.mkdir_p!(watch_dir)
      on_exit(fn -> File.rm_rf!(watch_dir) end)

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

    test "allows events after debounce window expires", %{data_dir: data_dir} do
      watch_dir = Path.join(System.tmp_dir!(), "tw_watch_#{System.unique_integer([:positive])}")
      File.mkdir_p!(watch_dir)
      on_exit(fn -> File.rm_rf!(watch_dir) end)

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
end
