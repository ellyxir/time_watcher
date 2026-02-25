defmodule TimeWatcher.StorageTest do
  use ExUnit.Case, async: false

  alias TimeWatcher.{Event, Storage}

  setup do
    data_dir =
      Path.join(System.tmp_dir!(), "tw_storage_test_#{System.unique_integer([:positive])}")

    File.rm_rf!(data_dir)
    on_cleanup = fn -> File.rm_rf!(data_dir) end

    on_exit(fn -> on_cleanup.() end)
    %{data_dir: data_dir}
  end

  describe "save_event/2" do
    test "writes event to correct date subdir", %{data_dir: data_dir} do
      event = %Event{
        timestamp: 1_740_000_000,
        repo: "my_repo",
        hashed_path: "abc123",
        event_type: :modified
      }

      assert :ok = Storage.save_event(event, data_dir)

      date_str =
        event.timestamp |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_string()

      date_dir = Path.join(data_dir, date_str)
      assert File.dir?(date_dir)

      [file] = File.ls!(date_dir)
      assert file =~ ~r/^#{event.timestamp}_.*_\d+\.json$/
      content = Path.join(date_dir, file) |> File.read!()
      assert {:ok, restored} = Event.from_json(content)
      assert restored.timestamp == event.timestamp
    end
  end

  describe "load_events/2" do
    test "reads back saved events", %{data_dir: data_dir} do
      event = %Event{
        timestamp: 1_740_000_000,
        repo: "my_repo",
        hashed_path: "abc123",
        event_type: :modified
      }

      Storage.save_event(event, data_dir)

      date_str =
        event.timestamp |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_string()

      events = Storage.load_events(date_str, data_dir)

      assert length(events) == 1
      assert hd(events).timestamp == event.timestamp
    end

    test "returns empty list for missing date", %{data_dir: data_dir} do
      assert Storage.load_events("2099-01-01", data_dir) == []
    end
  end

  describe "git_commit/2" do
    test "inits repo and commits", %{data_dir: data_dir} do
      File.mkdir_p!(data_dir)
      File.write!(Path.join(data_dir, "test.txt"), "hello")

      assert :ok = Storage.git_commit("test commit", data_dir)
      assert File.dir?(Path.join(data_dir, ".git"))

      {log, 0} = System.cmd("git", ["log", "--oneline", "-1"], cd: data_dir)
      assert log =~ "test commit"
    end
  end
end
