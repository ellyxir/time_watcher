defmodule TimeWatcher.StorageIntegrationTest do
  @moduledoc """
  Integration tests for Storage module git operations.
  Tests verify git repository management and commit functionality.
  """
  use ExUnit.Case, async: true

  alias TimeWatcher.{Event, Storage}

  setup do
    test_dir = Path.join(System.tmp_dir!(), "tw_storage_#{System.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    %{data_dir: test_dir}
  end

  describe "git repository initialization" do
    test "git_commit initializes repo if not exists", %{data_dir: data_dir} do
      refute File.dir?(Path.join(data_dir, ".git"))

      :ok = Storage.git_commit("test commit", data_dir)

      assert File.dir?(Path.join(data_dir, ".git"))
    end

    test "git_commit works with existing repo", %{data_dir: data_dir} do
      # Initialize repo first
      System.cmd("git", ["init"], cd: data_dir)

      # Should work without error
      :ok = Storage.git_commit("first commit", data_dir)
      :ok = Storage.git_commit("second commit", data_dir)

      # Verify commits exist
      {log, 0} = System.cmd("git", ["log", "--oneline"], cd: data_dir)
      assert log =~ "first commit"
      assert log =~ "second commit"
    end
  end

  describe "event persistence with git" do
    test "save_event creates JSON file in date directory", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      event = %Event{
        timestamp: base_time,
        repo: "test_repo",
        hashed_path: "abc123",
        event_type: :modified
      }

      :ok = Storage.save_event(event, data_dir)

      date_dir = Path.join(data_dir, date)
      assert File.dir?(date_dir)

      files = File.ls!(date_dir)
      assert length(files) == 1

      [filename] = files
      assert String.ends_with?(filename, ".json")
      assert String.starts_with?(filename, "#{base_time}_")
    end

    test "multiple events create multiple files", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      events =
        for i <- 1..5 do
          %Event{
            timestamp: base_time + i,
            repo: "repo_#{i}",
            hashed_path: "hash_#{i}",
            event_type: :modified
          }
        end

      Enum.each(events, &Storage.save_event(&1, data_dir))

      date_dir = Path.join(data_dir, date)
      files = File.ls!(date_dir)
      assert length(files) == 5
    end

    test "events across dates create separate directories", %{data_dir: data_dir} do
      # Day 1: 2026-01-15
      time1 = 1_736_935_200
      date1 = timestamp_to_date(time1)

      # Day 2: 2026-01-16 (24 hours later)
      time2 = time1 + 86_400
      date2 = timestamp_to_date(time2)

      event1 = %Event{
        timestamp: time1,
        repo: "repo",
        hashed_path: "a",
        event_type: :modified
      }

      event2 = %Event{
        timestamp: time2,
        repo: "repo",
        hashed_path: "b",
        event_type: :modified
      }

      Storage.save_event(event1, data_dir)
      Storage.save_event(event2, data_dir)

      assert File.dir?(Path.join(data_dir, date1))
      assert File.dir?(Path.join(data_dir, date2))

      # Each directory should have 1 file
      assert length(File.ls!(Path.join(data_dir, date1))) == 1
      assert length(File.ls!(Path.join(data_dir, date2))) == 1
    end
  end

  describe "event loading" do
    test "load_events returns events sorted by filename", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Create events with different timestamps
      events = [
        %Event{
          timestamp: base_time + 200,
          repo: "third",
          hashed_path: "c",
          event_type: :modified
        },
        %Event{timestamp: base_time, repo: "first", hashed_path: "a", event_type: :modified},
        %Event{
          timestamp: base_time + 100,
          repo: "second",
          hashed_path: "b",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      loaded = Storage.load_events(date, data_dir)

      # Should be sorted by filename (which includes timestamp)
      repos = Enum.map(loaded, & &1.repo)
      assert repos == ["first", "second", "third"]
    end

    test "load_events returns empty list for missing date", %{data_dir: data_dir} do
      events = Storage.load_events("2099-12-31", data_dir)
      assert events == []
    end

    test "load_events skips non-JSON files", %{data_dir: data_dir} do
      date = "2026-01-15"
      date_dir = Path.join(data_dir, date)
      File.mkdir_p!(date_dir)

      # Create some non-JSON files
      File.write!(Path.join(date_dir, "readme.txt"), "ignore me")
      File.write!(Path.join(date_dir, ".gitkeep"), "")

      # Create a valid JSON event
      File.write!(
        Path.join(date_dir, "1736935200_host_1.json"),
        ~s({"timestamp":1736935200,"repo":"test","hashed_path":"abc","event_type":"modified"})
      )

      events = Storage.load_events(date, data_dir)
      assert length(events) == 1
    end
  end

  describe "git commit integration" do
    test "events can be committed after saving", %{data_dir: data_dir} do
      base_time = 1_736_935_200

      event = %Event{
        timestamp: base_time,
        repo: "repo",
        hashed_path: "abc",
        event_type: :modified
      }

      Storage.save_event(event, data_dir)
      :ok = Storage.git_commit("auto: event recorded", data_dir)

      # Verify file is tracked
      {status, 0} = System.cmd("git", ["status", "--porcelain"], cd: data_dir)
      assert status == ""

      # Verify commit message
      {log, 0} = System.cmd("git", ["log", "--oneline", "-1"], cd: data_dir)
      assert log =~ "auto: event recorded"
    end

    test "multiple events create multiple commits", %{data_dir: data_dir} do
      base_time = 1_736_935_200

      for i <- 1..3 do
        event = %Event{
          timestamp: base_time + i,
          repo: "repo",
          hashed_path: "hash_#{i}",
          event_type: :modified
        }

        Storage.save_event(event, data_dir)
        Storage.git_commit("commit #{i}", data_dir)
      end

      {log, 0} = System.cmd("git", ["log", "--oneline"], cd: data_dir)
      lines = String.split(log, "\n", trim: true)
      assert length(lines) == 3
    end
  end

  describe "concurrent operations" do
    test "concurrent saves don't corrupt data", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Save 20 events concurrently
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            event = %Event{
              timestamp: base_time + i,
              repo: "repo_#{i}",
              hashed_path: "hash_#{i}",
              event_type: :modified
            }

            Storage.save_event(event, data_dir)
          end)
        end

      Task.await_many(tasks)

      # All events should be saved correctly
      events = Storage.load_events(date, data_dir)
      assert length(events) == 20

      # All repos should be unique
      repos = Enum.map(events, & &1.repo) |> Enum.sort()
      expected = for i <- 1..20, do: "repo_#{i}"
      assert repos == Enum.sort(expected)
    end
  end

  describe "hostname in filenames" do
    test "event files include hostname", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      event = %Event{
        timestamp: base_time,
        repo: "repo",
        hashed_path: "abc",
        event_type: :modified
      }

      Storage.save_event(event, data_dir)

      date_dir = Path.join(data_dir, date)
      [filename] = File.ls!(date_dir)

      {:ok, hostname} = :inet.gethostname()
      assert filename =~ to_string(hostname)
    end
  end

  defp timestamp_to_date(timestamp) do
    timestamp |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_string()
  end
end
