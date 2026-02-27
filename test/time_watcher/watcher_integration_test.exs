defmodule TimeWatcher.WatcherIntegrationTest do
  @moduledoc """
  Integration tests that verify actual file system events are recorded.
  These tests create/modify/delete real files and verify events are persisted.
  """
  use ExUnit.Case

  # Not async: true because file system events have timing dependencies
  alias TimeWatcher.{Storage, Watcher}

  setup do
    test_id = System.unique_integer([:positive])
    data_dir = Path.join(System.tmp_dir!(), "tw_data_#{test_id}")
    watch_dir = Path.join(System.tmp_dir!(), "tw_watch_#{test_id}")

    File.mkdir_p!(data_dir)
    File.mkdir_p!(watch_dir)

    on_exit(fn ->
      File.rm_rf!(data_dir)
      File.rm_rf!(watch_dir)
    end)

    %{data_dir: data_dir, watch_dir: watch_dir}
  end

  describe "file creation events" do
    test "records event when file is created", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 0)

      # Give the watcher time to initialize
      Process.sleep(100)

      # Create a file
      file_path = Path.join(watch_dir, "new_file.txt")
      File.write!(file_path, "hello")

      # Wait for event to be processed and saved
      Process.sleep(200)

      # Check that an event was recorded
      date = Date.to_string(Date.utc_today())
      events = Storage.load_events(date, data_dir)

      assert events != []
      event = List.first(events)
      assert event.repo == Path.basename(watch_dir)
      assert event.event_type in [:created, :modified]

      GenServer.stop(pid)
    end
  end

  describe "file modification events" do
    test "records event when file is modified", %{data_dir: data_dir, watch_dir: watch_dir} do
      # Create file before starting watcher
      file_path = Path.join(watch_dir, "existing_file.txt")
      File.write!(file_path, "initial content")

      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 0)
      Process.sleep(100)

      # Modify the file
      File.write!(file_path, "modified content")

      # Wait for event
      Process.sleep(200)

      date = Date.to_string(Date.utc_today())
      events = Storage.load_events(date, data_dir)

      assert events != []
      event = List.first(events)
      assert event.repo == Path.basename(watch_dir)
      assert event.event_type == :modified

      GenServer.stop(pid)
    end
  end

  describe "file deletion events" do
    test "records event when file is deleted", %{data_dir: data_dir, watch_dir: watch_dir} do
      # Create file before starting watcher
      file_path = Path.join(watch_dir, "to_delete.txt")
      File.write!(file_path, "content")

      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 0)
      Process.sleep(100)

      # Delete the file
      File.rm!(file_path)

      # Wait for event
      Process.sleep(200)

      date = Date.to_string(Date.utc_today())
      events = Storage.load_events(date, data_dir)

      assert events != []
      event = List.first(events)
      assert event.repo == Path.basename(watch_dir)
      assert event.event_type == :deleted

      GenServer.stop(pid)
    end
  end

  describe "nested directory events" do
    test "records events for files in nested subdirectories", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      # Create nested directory structure
      nested_dir = Path.join([watch_dir, "level1", "level2"])
      File.mkdir_p!(nested_dir)

      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 0)
      Process.sleep(100)

      # Create file in nested directory
      file_path = Path.join(nested_dir, "deep_file.txt")
      File.write!(file_path, "nested content")

      # Wait for event
      Process.sleep(200)

      date = Date.to_string(Date.utc_today())
      events = Storage.load_events(date, data_dir)

      # Should have recorded the nested file event
      assert events != []
      event = List.first(events)
      assert event.repo == Path.basename(watch_dir)

      GenServer.stop(pid)
    end
  end

  describe "debouncing" do
    test "debounces rapid changes to the same file", %{data_dir: data_dir, watch_dir: watch_dir} do
      # Use 1 second debounce
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 1)
      Process.sleep(100)

      file_path = Path.join(watch_dir, "rapid_changes.txt")

      # Make 5 rapid changes within debounce window
      for i <- 1..5 do
        File.write!(file_path, "content #{i}")
        Process.sleep(50)
      end

      # Wait for processing
      Process.sleep(300)

      date = Date.to_string(Date.utc_today())
      events = Storage.load_events(date, data_dir)

      # Should only have 1 event due to debouncing
      assert length(events) == 1

      GenServer.stop(pid)
    end

    test "records separate events after debounce window expires", %{
      data_dir: data_dir,
      watch_dir: watch_dir
    } do
      # Use very short debounce for testing
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 0)
      Process.sleep(100)

      file_path = Path.join(watch_dir, "separate_changes.txt")

      # First change
      File.write!(file_path, "content 1")
      Process.sleep(200)

      # Second change after debounce window
      File.write!(file_path, "content 2")
      Process.sleep(200)

      date = Date.to_string(Date.utc_today())
      events = Storage.load_events(date, data_dir)

      # Should have 2 separate events
      assert length(events) >= 2

      GenServer.stop(pid)
    end
  end

  describe "multiple directories" do
    test "records events from multiple watched directories", %{data_dir: data_dir} do
      test_id = System.unique_integer([:positive])
      watch_dir1 = Path.join(System.tmp_dir!(), "tw_watch1_#{test_id}")
      watch_dir2 = Path.join(System.tmp_dir!(), "tw_watch2_#{test_id}")

      File.mkdir_p!(watch_dir1)
      File.mkdir_p!(watch_dir2)

      on_exit(fn ->
        File.rm_rf!(watch_dir1)
        File.rm_rf!(watch_dir2)
      end)

      {:ok, pid} =
        Watcher.start_link(
          dirs: [watch_dir1, watch_dir2],
          data_dir: data_dir,
          debounce_seconds: 0
        )

      Process.sleep(100)

      # Create files in both directories
      File.write!(Path.join(watch_dir1, "file1.txt"), "content1")
      Process.sleep(100)
      File.write!(Path.join(watch_dir2, "file2.txt"), "content2")
      Process.sleep(200)

      date = Date.to_string(Date.utc_today())
      events = Storage.load_events(date, data_dir)

      # Should have events from both directories
      assert length(events) >= 2

      repos = events |> Enum.map(& &1.repo) |> Enum.uniq() |> Enum.sort()
      expected = [Path.basename(watch_dir1), Path.basename(watch_dir2)] |> Enum.sort()
      assert repos == expected

      GenServer.stop(pid)
    end
  end

  describe "path hashing" do
    test "hashes file paths for privacy", %{data_dir: data_dir, watch_dir: watch_dir} do
      {:ok, pid} = Watcher.start_link(dirs: [watch_dir], data_dir: data_dir, debounce_seconds: 0)
      Process.sleep(100)

      # Create file with sensitive name
      file_path = Path.join(watch_dir, "secret_credentials.txt")
      File.write!(file_path, "password123")

      Process.sleep(200)

      date = Date.to_string(Date.utc_today())
      events = Storage.load_events(date, data_dir)

      assert events != []
      event = List.first(events)

      # Path should be hashed (64 hex characters = SHA256)
      assert String.length(event.hashed_path) == 64
      assert String.match?(event.hashed_path, ~r/^[0-9a-f]+$/)

      # Should NOT contain the actual filename
      refute event.hashed_path =~ "secret"
      refute event.hashed_path =~ "credentials"

      GenServer.stop(pid)
    end
  end
end
