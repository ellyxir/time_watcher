defmodule TimeWatcher.ReportIntegrationTest do
  @moduledoc """
  Integration tests for the full report generation pipeline.
  Tests the flow: Storage.load_events -> Report.stretches -> Report.format
  """
  use ExUnit.Case, async: true

  alias TimeWatcher.{Event, Report, Storage}

  setup do
    test_dir = Path.join(System.tmp_dir!(), "tw_report_#{System.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    %{data_dir: test_dir}
  end

  describe "full pipeline: load -> stretches -> format" do
    test "processes events from disk into formatted report", %{data_dir: data_dir} do
      # Create events at known timestamps
      # 2026-01-15 10:00:00 UTC = 1736935200
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Need at least 2 events per repo to produce a stretch
      events = [
        %Event{timestamp: base_time, repo: "project_a", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: base_time + 120,
          repo: "project_a",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 3600,
          repo: "project_b",
          hashed_path: "b1",
          event_type: :created
        },
        %Event{
          timestamp: base_time + 3720,
          repo: "project_b",
          hashed_path: "b2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      # Load from disk
      loaded_events = Storage.load_events(date, data_dir)
      assert length(loaded_events) == 4

      # Generate stretches (one per repo with 2+ events)
      stretches = Report.stretches(loaded_events)
      assert length(stretches) == 2

      # Format output
      output = Report.format(stretches)
      assert output =~ "project_a"
      assert output =~ "project_b"
    end

    test "handles events spanning multiple repos", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Create interleaved events across 3 repos
      # Each repo needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: base_time, repo: "repo_1", hashed_path: "h1", event_type: :modified},
        %Event{
          timestamp: base_time + 60,
          repo: "repo_2",
          hashed_path: "h2",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 120,
          repo: "repo_3",
          hashed_path: "h3",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 180,
          repo: "repo_1",
          hashed_path: "h4",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 240,
          repo: "repo_2",
          hashed_path: "h5",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 300,
          repo: "repo_3",
          hashed_path: "h6",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      loaded = Storage.load_events(date, data_dir)
      stretches = Report.stretches(loaded)

      # Should have 3 stretches (one per repo with 2+ events)
      repos = stretches |> Enum.map(& &1.repo) |> Enum.sort()
      assert repos == ["repo_1", "repo_2", "repo_3"]
    end

    test "empty storage returns empty stretches", %{data_dir: data_dir} do
      date = "2026-01-15"

      events = Storage.load_events(date, data_dir)
      assert events == []

      stretches = Report.stretches(events)
      assert stretches == []

      output = Report.format(stretches)
      assert output == ""
    end

    test "gracefully handles corrupted JSON files", %{data_dir: data_dir} do
      # Use a timestamp that corresponds to a known date
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)
      date_dir = Path.join(data_dir, date)
      File.mkdir_p!(date_dir)

      # Write a corrupted JSON file
      File.write!(Path.join(date_dir, "corrupted.json"), "not valid json{{{")

      # Write a valid event with matching timestamp
      valid_event = %Event{
        timestamp: base_time,
        repo: "valid_repo",
        hashed_path: "abc",
        event_type: :modified
      }

      Storage.save_event(valid_event, data_dir)

      # Should load only the valid event, skipping corrupted file
      events = Storage.load_events(date, data_dir)
      assert length(events) == 1
      assert hd(events).repo == "valid_repo"
    end

    test "handles events with various event types", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      events = [
        %Event{timestamp: base_time, repo: "repo", hashed_path: "a", event_type: :created},
        %Event{timestamp: base_time + 60, repo: "repo", hashed_path: "b", event_type: :modified},
        %Event{timestamp: base_time + 120, repo: "repo", hashed_path: "c", event_type: :deleted}
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      loaded = Storage.load_events(date, data_dir)
      assert length(loaded) == 3

      # All event types should be present
      types = Enum.map(loaded, & &1.event_type) |> Enum.sort()
      assert types == [:created, :deleted, :modified]

      # Should merge into single stretch
      stretches = Report.stretches(loaded)
      assert length(stretches) == 1
    end
  end

  describe "markdown format pipeline" do
    test "generates valid markdown table from stored events", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Each repo needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: base_time, repo: "my_project", hashed_path: "a", event_type: :modified},
        %Event{
          timestamp: base_time + 120,
          repo: "my_project",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 3600,
          repo: "other_project",
          hashed_path: "b",
          event_type: :created
        },
        %Event{
          timestamp: base_time + 3720,
          repo: "other_project",
          hashed_path: "b2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      loaded = Storage.load_events(date, data_dir)
      stretches = Report.stretches(loaded)
      markdown = Report.format_markdown(stretches)

      # Verify markdown table structure
      assert markdown =~ "| Time | Project | Duration |"
      assert markdown =~ "|------|---------|----------|"
      assert markdown =~ "my_project"
      assert markdown =~ "other_project"

      # Should have proper pipe delimiters
      lines = String.split(markdown, "\n")
      assert length(lines) == 4
      assert Enum.all?(lines, &String.starts_with?(&1, "|"))
    end
  end

  describe "custom window sizes" do
    test "larger window merges more events", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Events 12 minutes apart (720 seconds)
      # Default 10-min merge window: too far apart, no stretch
      # 30-min merge window: within range, events merge into 1 stretch
      events = [
        %Event{timestamp: base_time, repo: "repo", hashed_path: "a", event_type: :modified},
        %Event{timestamp: base_time + 720, repo: "repo", hashed_path: "b", event_type: :modified}
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      loaded = Storage.load_events(date, data_dir)

      # Default 10-min window: 12 min apart = no stretch (isolated events)
      default_stretches = Report.stretches(loaded)
      assert default_stretches == []

      # 30-min window: 12 min apart = merged into 1 stretch
      large_stretches = Report.stretches(loaded, merge_window_minutes: 30)
      assert length(large_stretches) == 1
    end

    test "smaller window creates separate events that dont produce stretches", %{
      data_dir: data_dir
    } do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Events 6 minutes apart (360 seconds)
      # Default 10-min merge window: within range, merge into 1 stretch
      # 4-min merge window: too far apart, no stretch
      events = [
        %Event{timestamp: base_time, repo: "repo", hashed_path: "a", event_type: :modified},
        %Event{timestamp: base_time + 360, repo: "repo", hashed_path: "b", event_type: :modified}
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      loaded = Storage.load_events(date, data_dir)

      # Default 10-min window: 6 min apart = merged
      default_stretches = Report.stretches(loaded)
      assert length(default_stretches) == 1

      # 4-min window: 6 min apart = no stretch (isolated events)
      small_stretches = Report.stretches(loaded, merge_window_minutes: 4)
      assert small_stretches == []
    end
  end

  describe "time calculations" do
    test "calculates correct duration for stretches", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Two events 5 minutes apart = 5 min duration (actual time between events)
      events = [
        %Event{timestamp: base_time, repo: "repo", hashed_path: "a", event_type: :modified},
        %Event{timestamp: base_time + 300, repo: "repo", hashed_path: "b", event_type: :modified}
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      loaded = Storage.load_events(date, data_dir)
      [stretch] = Report.stretches(loaded)

      # Duration is actual time between first and last event
      duration = stretch.stop - stretch.start
      assert duration == 300
    end

    test "single event produces no stretch", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      event = %Event{timestamp: base_time, repo: "repo", hashed_path: "a", event_type: :modified}
      Storage.save_event(event, data_dir)

      loaded = Storage.load_events(date, data_dir)
      stretches = Report.stretches(loaded)

      # Single event cannot establish a duration
      assert stretches == []
    end

    test "stretches are sorted by start time", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      # Add events in random order, each repo needs 2+ events
      events = [
        %Event{
          timestamp: base_time + 7200,
          repo: "third",
          hashed_path: "c1",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 7260,
          repo: "third",
          hashed_path: "c2",
          event_type: :modified
        },
        %Event{timestamp: base_time, repo: "first", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: base_time + 60,
          repo: "first",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 3600,
          repo: "second",
          hashed_path: "b1",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 3660,
          repo: "second",
          hashed_path: "b2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      loaded = Storage.load_events(date, data_dir)
      stretches = Report.stretches(loaded)

      # Should be sorted by start time
      repos = Enum.map(stretches, & &1.repo)
      assert repos == ["first", "second", "third"]
    end
  end

  defp timestamp_to_date(timestamp) do
    timestamp |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_string()
  end
end
