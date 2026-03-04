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

      # Need at least 2 events to produce a stretch
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

      # Each repo needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: base_time, repo: "app_one", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: base_time + 60,
          repo: "app_one",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 120,
          repo: "app_two",
          hashed_path: "b1",
          event_type: :created
        },
        %Event{
          timestamp: base_time + 180,
          repo: "app_two",
          hashed_path: "b2",
          event_type: :modified
        },
        %Event{
          timestamp: base_time + 240,
          repo: "app_three",
          hashed_path: "c1",
          event_type: :deleted
        },
        %Event{
          timestamp: base_time + 300,
          repo: "app_three",
          hashed_path: "c2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      output =
        capture_io(fn ->
          run_report(date, [], data_dir)
        end)

      assert output =~ "app_one"
      assert output =~ "app_two"
      assert output =~ "app_three"
    end
  end

  describe "report --days command" do
    test "outputs multiple days of activity", %{data_dir: data_dir} do
      # Day 1: 2026-01-15 10:00 UTC
      day1_time = 1_736_935_200
      # Day 2: 2026-01-16 10:00 UTC (24 hours later)
      day2_time = day1_time + 86_400

      # Each day needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: day1_time, repo: "my_app", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: day1_time + 120,
          repo: "my_app",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{timestamp: day2_time, repo: "my_app", hashed_path: "b1", event_type: :modified},
        %Event{
          timestamp: day2_time + 120,
          repo: "my_app",
          hashed_path: "b2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      date1 = timestamp_to_date(day1_time)
      date2 = timestamp_to_date(day2_time)

      output =
        capture_io(fn ->
          run_multi_day_report([date1, date2], [], data_dir)
        end)

      assert output =~ "Activity for #{date1}"
      assert output =~ "Activity for #{date2}"
      assert output =~ "Day total:"
      assert output =~ "Total (2 days):"
    end

    test "outputs markdown format with --days and --md", %{data_dir: data_dir} do
      day1_time = 1_736_935_200
      day2_time = day1_time + 86_400

      # Each day needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: day1_time, repo: "my_app", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: day1_time + 120,
          repo: "my_app",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{timestamp: day2_time, repo: "my_app", hashed_path: "b1", event_type: :modified},
        %Event{
          timestamp: day2_time + 120,
          repo: "my_app",
          hashed_path: "b2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      date1 = timestamp_to_date(day1_time)
      date2 = timestamp_to_date(day2_time)

      output =
        capture_io(fn ->
          run_multi_day_report([date1, date2], [md: true], data_dir)
        end)

      assert output =~ "## Activity for #{date1}"
      assert output =~ "## Activity for #{date2}"
      assert output =~ "| Time | Project | Duration |"
      assert output =~ "**Day total:"
      assert output =~ "**Total (2 days):"
    end

    test "skips days with no activity", %{data_dir: data_dir} do
      day1_time = 1_736_935_200
      # Skip day 2, add events on day 3
      day3_time = day1_time + 86_400 * 2

      # Each day needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: day1_time, repo: "my_app", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: day1_time + 120,
          repo: "my_app",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{timestamp: day3_time, repo: "my_app", hashed_path: "c1", event_type: :modified},
        %Event{
          timestamp: day3_time + 120,
          repo: "my_app",
          hashed_path: "c2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      date1 = timestamp_to_date(day1_time)
      date2 = timestamp_to_date(day1_time + 86_400)
      date3 = timestamp_to_date(day3_time)

      output =
        capture_io(fn ->
          run_multi_day_report([date1, date2, date3], [], data_dir)
        end)

      assert output =~ "Activity for #{date1}"
      refute output =~ "Activity for #{date2}"
      assert output =~ "Activity for #{date3}"
      assert output =~ "Total (2 days):"
    end

    test "shows no activity when all days are empty", %{data_dir: data_dir} do
      output =
        capture_io(fn ->
          run_multi_day_report(["2026-01-15", "2026-01-16"], [], data_dir)
        end)

      assert output =~ "No activity recorded for the selected period"
    end

    test "respects --cooldown option with --days", %{data_dir: data_dir} do
      day1_time = 1_736_935_200

      event1 = %Event{
        timestamp: day1_time,
        repo: "my_app",
        hashed_path: "abc",
        event_type: :modified
      }

      event2 = %Event{
        timestamp: day1_time + 480,
        repo: "my_app",
        hashed_path: "def",
        event_type: :modified
      }

      Storage.save_event(event1, data_dir)
      Storage.save_event(event2, data_dir)

      date1 = timestamp_to_date(day1_time)

      output =
        capture_io(fn ->
          run_multi_day_report([date1], [cooldown: 10], data_dir)
        end)

      assert output =~ "Activity for #{date1}"
      assert output =~ "my_app"
    end
  end

  describe "report --from/--to command" do
    test "outputs date range activity", %{data_dir: data_dir} do
      # Day 1: 2026-01-15 10:00 UTC
      day1_time = 1_736_935_200
      # Day 2: 2026-01-16 10:00 UTC (24 hours later)
      day2_time = day1_time + 86_400

      # Each day needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: day1_time, repo: "my_app", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: day1_time + 120,
          repo: "my_app",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{timestamp: day2_time, repo: "my_app", hashed_path: "b1", event_type: :modified},
        %Event{
          timestamp: day2_time + 120,
          repo: "my_app",
          hashed_path: "b2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      date1 = timestamp_to_date(day1_time)
      date2 = timestamp_to_date(day2_time)

      output =
        capture_io(fn ->
          run_multi_day_report([date1, date2], [], data_dir)
        end)

      assert output =~ "Activity for #{date1}"
      assert output =~ "Activity for #{date2}"
      assert output =~ "Day total:"
      assert output =~ "Total (2 days):"
    end

    test "outputs markdown format with --from/--to and --md", %{data_dir: data_dir} do
      day1_time = 1_736_935_200
      day2_time = day1_time + 86_400

      # Each day needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: day1_time, repo: "my_app", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: day1_time + 120,
          repo: "my_app",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{timestamp: day2_time, repo: "my_app", hashed_path: "b1", event_type: :modified},
        %Event{
          timestamp: day2_time + 120,
          repo: "my_app",
          hashed_path: "b2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      date1 = timestamp_to_date(day1_time)
      date2 = timestamp_to_date(day2_time)

      output =
        capture_io(fn ->
          run_multi_day_report([date1, date2], [md: true], data_dir)
        end)

      assert output =~ "## Activity for #{date1}"
      assert output =~ "## Activity for #{date2}"
      assert output =~ "| Time | Project | Duration |"
      assert output =~ "**Day total:"
      assert output =~ "**Total (2 days):"
    end

    test "skips days with no activity in date range", %{data_dir: data_dir} do
      day1_time = 1_736_935_200
      # Skip day 2, add events on day 3
      day3_time = day1_time + 86_400 * 2

      # Each day needs at least 2 events to produce a stretch
      events = [
        %Event{timestamp: day1_time, repo: "my_app", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: day1_time + 120,
          repo: "my_app",
          hashed_path: "a2",
          event_type: :modified
        },
        %Event{timestamp: day3_time, repo: "my_app", hashed_path: "c1", event_type: :modified},
        %Event{
          timestamp: day3_time + 120,
          repo: "my_app",
          hashed_path: "c2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      date1 = timestamp_to_date(day1_time)
      date2 = timestamp_to_date(day1_time + 86_400)
      date3 = timestamp_to_date(day3_time)

      output =
        capture_io(fn ->
          run_multi_day_report([date1, date2, date3], [], data_dir)
        end)

      assert output =~ "Activity for #{date1}"
      refute output =~ "Activity for #{date2}"
      assert output =~ "Activity for #{date3}"
      assert output =~ "Total (2 days):"
    end

    test "shows no activity when date range has no events", %{data_dir: data_dir} do
      output =
        capture_io(fn ->
          run_multi_day_report(["2026-01-15", "2026-01-16", "2026-01-17"], [], data_dir)
        end)

      assert output =~ "No activity recorded for the selected period"
    end

    test "single day range (--from equals --to)", %{data_dir: data_dir} do
      day1_time = 1_736_935_200
      date1 = timestamp_to_date(day1_time)

      # Need at least 2 events to produce a stretch
      events = [
        %Event{timestamp: day1_time, repo: "my_app", hashed_path: "a1", event_type: :modified},
        %Event{
          timestamp: day1_time + 120,
          repo: "my_app",
          hashed_path: "a2",
          event_type: :modified
        }
      ]

      Enum.each(events, &Storage.save_event(&1, data_dir))

      output =
        capture_io(fn ->
          run_multi_day_report([date1], [], data_dir)
        end)

      assert output =~ "Activity for #{date1}"
      assert output =~ "Total (1 days):"
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
      minutes -> [merge_window_minutes: minutes * 2]
    end
  end

  defp timestamp_to_date(timestamp) do
    timestamp |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_string()
  end

  # Helper to run multi-day report with custom data_dir
  defp run_multi_day_report(dates, opts, data_dir) do
    report_opts = build_report_opts(opts)
    markdown? = Keyword.get(opts, :md, false)

    day_results =
      dates
      |> Enum.map(fn date ->
        events = Storage.load_events(date, data_dir)
        stretches = TimeWatcher.Report.stretches(events, report_opts)
        {date, stretches}
      end)
      |> Enum.reject(fn {_date, stretches} -> stretches == [] end)

    if day_results == [] do
      IO.puts("No activity recorded for the selected period")
    else
      grand_total =
        day_results
        |> Enum.map(fn {_date, stretches} -> sum_stretches(stretches) end)
        |> Enum.sum()

      Enum.each(day_results, fn {date, stretches} ->
        print_day_report(date, stretches, markdown?)
      end)

      print_grand_total(length(day_results), grand_total, markdown?)
    end
  end

  defp print_day_report(date, stretches, markdown?) do
    day_total = sum_stretches(stretches)
    day_hours = div(day_total, 3600)
    day_minutes = div(rem(day_total, 3600), 60)

    if markdown? do
      IO.puts("## Activity for #{date}\n")
      IO.puts(TimeWatcher.Report.format_markdown(stretches))
      IO.puts("\n**Day total: #{day_hours}h #{day_minutes}m**\n")
    else
      IO.puts("Activity for #{date}:\n")
      IO.puts(TimeWatcher.Report.format(stretches))
      IO.puts("\nDay total: #{day_hours}h #{day_minutes}m\n")
    end
  end

  defp print_grand_total(num_days, total_seconds, markdown?) do
    total_hours = div(total_seconds, 3600)
    total_minutes = div(rem(total_seconds, 3600), 60)

    IO.puts("---")

    if markdown? do
      IO.puts("**Total (#{num_days} days): #{total_hours}h #{total_minutes}m**")
    else
      IO.puts("Total (#{num_days} days): #{total_hours}h #{total_minutes}m")
    end
  end

  defp sum_stretches(stretches) do
    Enum.reduce(stretches, 0, fn s, acc -> acc + (s.stop - s.start) end)
  end
end
