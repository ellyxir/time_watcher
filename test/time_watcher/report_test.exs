defmodule TimeWatcher.ReportTest do
  use ExUnit.Case, async: true

  alias TimeWatcher.{Event, Report}

  defp event(timestamp, repo) do
    %Event{
      timestamp: timestamp,
      repo: repo,
      hashed_path: "abc",
      event_type: :modified
    }
  end

  describe "stretches/2" do
    test "single event = 10 min stretch" do
      events = [event(1_000_000, "repo")]
      stretches = Report.stretches(events)

      assert length(stretches) == 1
      [stretch] = stretches
      assert stretch.start == 1_000_000 - 300
      assert stretch.stop == 1_000_000 + 300
      assert stretch.repo == "repo"
    end

    test "close events merge into one stretch" do
      # 2 minutes apart - windows overlap
      events = [event(1_000_000, "repo"), event(1_000_120, "repo")]
      stretches = Report.stretches(events)

      assert length(stretches) == 1
      [stretch] = stretches
      assert stretch.start == 1_000_000 - 300
      assert stretch.stop == 1_000_120 + 300
    end

    test "far events = separate stretches" do
      # 20 minutes apart - windows don't overlap
      events = [event(1_000_000, "repo"), event(1_001_200, "repo")]
      stretches = Report.stretches(events)

      assert length(stretches) == 2
    end

    test "different repos = separate stretches even if close" do
      events = [event(1_000_000, "repo_a"), event(1_000_060, "repo_b")]
      stretches = Report.stretches(events)

      assert length(stretches) == 2
      repos = Enum.map(stretches, & &1.repo) |> Enum.sort()
      assert repos == ["repo_a", "repo_b"]
    end

    test "custom window size" do
      events = [event(1_000_000, "repo")]
      stretches = Report.stretches(events, window_minutes: 20)

      [stretch] = stretches
      assert stretch.start == 1_000_000 - 600
      assert stretch.stop == 1_000_000 + 600
    end
  end

  describe "format/1" do
    test "outputs human-readable lines with duration" do
      stretches = [
        %{
          repo: "my_project",
          start: 1_740_000_000,
          stop: 1_740_003_600
        }
      ]

      output = Report.format(stretches)
      assert output =~ "my_project"
      assert output =~ "1h 0m"
    end

    test "formats minutes correctly" do
      stretches = [
        %{
          repo: "proj",
          start: 1_740_000_000,
          stop: 1_740_000_000 + 900
        }
      ]

      output = Report.format(stretches)
      assert output =~ "0h 15m"
    end
  end

  describe "format_markdown/1" do
    test "outputs markdown table with headers" do
      stretches = [
        %{
          repo: "my_project",
          start: 1_740_000_000,
          stop: 1_740_003_600
        }
      ]

      output = Report.format_markdown(stretches)
      assert output =~ "| Time | Project | Duration |"
      assert output =~ "|------|---------|----------|"
      assert output =~ "my_project"
      assert output =~ "1h 0m"
    end

    test "formats multiple stretches as table rows" do
      stretches = [
        %{repo: "proj_a", start: 1_740_000_000, stop: 1_740_001_800},
        %{repo: "proj_b", start: 1_740_002_000, stop: 1_740_003_800}
      ]

      output = Report.format_markdown(stretches)
      lines = String.split(output, "\n")
      # Header + separator + 2 data rows
      assert length(lines) == 4
      assert Enum.any?(lines, &(&1 =~ "proj_a"))
      assert Enum.any?(lines, &(&1 =~ "proj_b"))
    end

    test "formats empty stretches as empty table" do
      output = Report.format_markdown([])
      assert output =~ "| Time | Project | Duration |"
      lines = String.split(output, "\n")
      # Just header and separator
      assert length(lines) == 2
    end
  end
end
