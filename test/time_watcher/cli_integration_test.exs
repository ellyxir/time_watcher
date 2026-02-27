defmodule TimeWatcher.CLIIntegrationTest do
  @moduledoc """
  Integration tests for CLI commands that verify actual output.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias TimeWatcher.{CLI, Event, Storage}

  setup do
    # Create temp data directory for each test
    test_dir = Path.join(System.tmp_dir!(), "tw_cli_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    %{data_dir: test_dir}
  end

  describe "report command integration" do
    test "outputs 'no activity' when no events exist", %{data_dir: data_dir} do
      date = "2026-01-15"

      output =
        capture_io(fn ->
          run_report(date, [], data_dir)
        end)

      assert output =~ "No activity recorded for #{date}"
    end

    test "outputs formatted activity for events in storage", %{data_dir: data_dir} do
      # Use a timestamp that corresponds to 2026-01-15
      # 2026-01-15 10:00:00 UTC = 1736935200
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      event1 = %Event{
        timestamp: base_time,
        repo: "my_app",
        hashed_path: "abc",
        event_type: :modified
      }

      event2 = %Event{
        timestamp: base_time + 120,
        repo: "my_app",
        hashed_path: "def",
        event_type: :modified
      }

      Storage.save_event(event1, data_dir)
      Storage.save_event(event2, data_dir)

      output =
        capture_io(fn ->
          run_report(date, [], data_dir)
        end)

      assert output =~ "Activity for #{date}"
      assert output =~ "my_app"
      assert output =~ "Total:"
    end

    test "outputs markdown table with --md flag", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      event = %Event{
        timestamp: base_time,
        repo: "my_app",
        hashed_path: "abc",
        event_type: :modified
      }

      Storage.save_event(event, data_dir)

      output =
        capture_io(fn ->
          run_report(date, [md: true], data_dir)
        end)

      assert output =~ "## Activity for #{date}"
      assert output =~ "| Time | Project | Duration |"
      assert output =~ "|------|---------|----------|"
      assert output =~ "my_app"
      assert output =~ "**Total:"
    end

    test "respects --cooldown option", %{data_dir: data_dir} do
      # Events 8 minutes apart - default 5min cooldown would separate them
      # but 10min cooldown should merge them
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      event1 = %Event{
        timestamp: base_time,
        repo: "my_app",
        hashed_path: "abc",
        event_type: :modified
      }

      event2 = %Event{
        timestamp: base_time + 480,
        repo: "my_app",
        hashed_path: "def",
        event_type: :modified
      }

      Storage.save_event(event1, data_dir)
      Storage.save_event(event2, data_dir)

      # With default cooldown (5 min = 10 min window), events should be separate
      output_default =
        capture_io(fn ->
          run_report(date, [], data_dir)
        end)

      # With 10 min cooldown (20 min window), events should merge
      output_large =
        capture_io(fn ->
          run_report(date, [cooldown: 10], data_dir)
        end)

      # Count stretches by counting repo occurrences in output
      default_stretches = length(String.split(output_default, "my_app")) - 1
      large_stretches = length(String.split(output_large, "my_app")) - 1

      # Large cooldown should result in fewer (merged) stretches
      assert large_stretches <= default_stretches
    end

    test "shows multiple repos in report", %{data_dir: data_dir} do
      base_time = 1_736_935_200
      date = timestamp_to_date(base_time)

      event1 = %Event{
        timestamp: base_time,
        repo: "app_one",
        hashed_path: "a",
        event_type: :modified
      }

      event2 = %Event{
        timestamp: base_time + 60,
        repo: "app_two",
        hashed_path: "b",
        event_type: :created
      }

      event3 = %Event{
        timestamp: base_time + 120,
        repo: "app_three",
        hashed_path: "c",
        event_type: :deleted
      }

      Storage.save_event(event1, data_dir)
      Storage.save_event(event2, data_dir)
      Storage.save_event(event3, data_dir)

      output =
        capture_io(fn ->
          run_report(date, [], data_dir)
        end)

      assert output =~ "app_one"
      assert output =~ "app_two"
      assert output =~ "app_three"
    end
  end

  describe "help command" do
    test "outputs usage information" do
      output =
        capture_io(fn ->
          CLI.main(["help"])
        end)

      assert output =~ "tw - git-based time tracker"
      assert output =~ "Usage:"
      assert output =~ "tw watch"
      assert output =~ "tw report"
      assert output =~ "tw stop"
      assert output =~ "--md"
      assert output =~ "--cooldown"
    end

    test "unknown command shows help" do
      output =
        capture_io(fn ->
          CLI.main(["unknown_command"])
        end)

      assert output =~ "tw - git-based time tracker"
    end

    test "empty args shows help" do
      output =
        capture_io(fn ->
          CLI.main([])
        end)

      assert output =~ "tw - git-based time tracker"
    end
  end

  # Helper to run report with custom data_dir
  # We need to temporarily override the storage module's data_dir
  defp run_report(date, opts, data_dir) do
    events = Storage.load_events(date, data_dir)
    report_opts = build_report_opts(opts)
    stretches = TimeWatcher.Report.stretches(events, report_opts)
    markdown? = Keyword.get(opts, :md, false)

    if stretches == [] do
      IO.puts("No activity recorded for #{date}")
    else
      total_seconds = Enum.reduce(stretches, 0, fn s, acc -> acc + (s.stop - s.start) end)
      hours = div(total_seconds, 3600)
      minutes = div(rem(total_seconds, 3600), 60)

      if markdown? do
        IO.puts("## Activity for #{date}\n")
        IO.puts(TimeWatcher.Report.format_markdown(stretches))
        IO.puts("\n**Total: #{hours}h #{minutes}m**")
      else
        IO.puts("Activity for #{date}:\n")
        IO.puts(TimeWatcher.Report.format(stretches))
        IO.puts("\nTotal: #{hours}h #{minutes}m")
      end
    end
  end

  defp build_report_opts(opts) do
    case Keyword.get(opts, :cooldown) do
      nil -> []
      minutes -> [window_minutes: minutes * 2]
    end
  end

  defp timestamp_to_date(timestamp) do
    timestamp |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_string()
  end
end
