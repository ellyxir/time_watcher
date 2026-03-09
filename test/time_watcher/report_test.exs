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
    test "single event produces no stretch" do
      events = [event(1_000_000, "repo")]
      stretches = Report.stretches(events)

      assert stretches == []
    end

    test "two close events merge into one stretch with actual timestamps" do
      # 2 minutes apart - within merge window
      events = [event(1_000_000, "repo"), event(1_000_120, "repo")]
      stretches = Report.stretches(events)

      assert length(stretches) == 1
      [stretch] = stretches
      # Duration should be actual time between events, not padded
      assert stretch.start == 1_000_000
      assert stretch.stop == 1_000_120
      assert stretch.repo == "repo"
    end

    test "far events produce separate stretches" do
      # 20 minutes apart - outside merge window, each becomes isolated
      events = [event(1_000_000, "repo"), event(1_001_200, "repo")]
      stretches = Report.stretches(events)

      # Single isolated events don't produce stretches
      assert stretches == []
    end

    test "multiple isolated events produce no stretches" do
      # Events 20 minutes apart each - all isolated
      events = [
        event(1_000_000, "repo"),
        event(1_001_200, "repo"),
        event(1_002_400, "repo")
      ]

      stretches = Report.stretches(events)
      assert stretches == []
    end

    test "three events where two are close produces one stretch" do
      # Events at 0, 2min, and 20min - first two merge, third is isolated
      events = [
        event(1_000_000, "repo"),
        event(1_000_120, "repo"),
        event(1_001_200, "repo")
      ]

      stretches = Report.stretches(events)

      assert length(stretches) == 1
      [stretch] = stretches
      assert stretch.start == 1_000_000
      assert stretch.stop == 1_000_120
    end

    test "different repos produce separate stretches even if close" do
      events = [event(1_000_000, "repo_a"), event(1_000_060, "repo_b")]
      stretches = Report.stretches(events)

      # Each repo only has one event, so no stretches
      assert stretches == []
    end

    test "different repos with multiple events each" do
      events = [
        event(1_000_000, "repo_a"),
        event(1_000_120, "repo_a"),
        event(1_000_060, "repo_b"),
        event(1_000_180, "repo_b")
      ]

      stretches = Report.stretches(events)

      assert length(stretches) == 2
      repos = Enum.map(stretches, & &1.repo) |> Enum.sort()
      assert repos == ["repo_a", "repo_b"]
    end

    test "custom merge window determines what events merge" do
      # Events 8 minutes apart
      events = [event(1_000_000, "repo"), event(1_000_480, "repo")]

      # Default 10-min window: should merge
      stretches = Report.stretches(events)
      assert length(stretches) == 1

      # 5-min window: should not merge (isolated events = no stretch)
      stretches = Report.stretches(events, merge_window_minutes: 5)
      assert stretches == []
    end

    test "legacy window_minutes option still works" do
      # Events 8 minutes apart
      events = [event(1_000_000, "repo"), event(1_000_480, "repo")]

      # Default 10-min window: should merge
      assert length(Report.stretches(events)) == 1

      # Using legacy option name with 5-min window: should not merge
      assert Report.stretches(events, window_minutes: 5) == []
    end

    test "events exactly at merge window boundary still merge" do
      # Events exactly 10 minutes apart (600 seconds)
      events = [event(1_000_000, "repo"), event(1_000_600, "repo")]
      stretches = Report.stretches(events)

      assert length(stretches) == 1
      [stretch] = stretches
      assert stretch.stop - stretch.start == 600
    end
  end

  describe "duration/1" do
    test "returns duration in seconds for a stretch" do
      stretch = %{repo: "repo", start: 1_000_000, stop: 1_000_120}
      assert Report.duration(stretch) == 120
    end

    test "returns zero for stretch with same start and stop" do
      stretch = %{repo: "repo", start: 1_000_000, stop: 1_000_000}
      assert Report.duration(stretch) == 0
    end

    test "works with large durations" do
      # 2 hours = 7200 seconds
      stretch = %{repo: "repo", start: 1_000_000, stop: 1_007_200}
      assert Report.duration(stretch) == 7200
    end
  end

  describe "total_duration/1" do
    test "sums durations of multiple stretches" do
      stretches = [
        %{repo: "repo_a", start: 1_000_000, stop: 1_000_120},
        %{repo: "repo_b", start: 1_000_200, stop: 1_000_500}
      ]

      # 120 + 300 = 420
      assert Report.total_duration(stretches) == 420
    end

    test "returns zero for empty list" do
      assert Report.total_duration([]) == 0
    end

    test "returns duration for single stretch" do
      stretches = [%{repo: "repo", start: 1_000_000, stop: 1_000_060}]
      assert Report.total_duration(stretches) == 60
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

  describe "subtotals/1" do
    test "returns empty list for empty stretches" do
      assert Report.subtotals([]) == []
    end

    test "returns single subtotal for single project" do
      stretches = [
        %{repo: "proj_a", start: 1_000_000, stop: 1_000_120}
      ]

      subtotals = Report.subtotals(stretches)

      assert subtotals == [{"proj_a", 120}]
    end

    test "aggregates duration across multiple stretches for same project" do
      stretches = [
        %{repo: "proj_a", start: 1_000_000, stop: 1_000_120},
        %{repo: "proj_a", start: 1_001_000, stop: 1_001_300}
      ]

      subtotals = Report.subtotals(stretches)

      # 120 + 300 = 420
      assert subtotals == [{"proj_a", 420}]
    end

    test "returns subtotals for multiple projects sorted by name" do
      stretches = [
        %{repo: "proj_b", start: 1_000_000, stop: 1_000_300},
        %{repo: "proj_a", start: 1_000_100, stop: 1_000_220}
      ]

      subtotals = Report.subtotals(stretches)

      assert subtotals == [{"proj_a", 120}, {"proj_b", 300}]
    end

    test "handles interleaved stretches from multiple projects" do
      stretches = [
        %{repo: "proj_a", start: 1_000_000, stop: 1_000_120},
        %{repo: "proj_b", start: 1_000_060, stop: 1_000_180},
        %{repo: "proj_a", start: 1_000_200, stop: 1_000_500}
      ]

      subtotals = Report.subtotals(stretches)

      # proj_a: 120 + 300 = 420, proj_b: 120
      assert subtotals == [{"proj_a", 420}, {"proj_b", 120}]
    end
  end

  describe "format_subtotals/1" do
    test "formats subtotals as human-readable lines" do
      subtotals = [{"proj_a", 4800}, {"proj_b", 1800}]

      output = Report.format_subtotals(subtotals)

      assert output =~ "proj_a: 1h 20m"
      assert output =~ "proj_b: 0h 30m"
    end

    test "formats empty subtotals as empty string" do
      assert Report.format_subtotals([]) == ""
    end
  end

  describe "format_subtotals_markdown/1" do
    test "formats subtotals as markdown table" do
      subtotals = [{"proj_a", 4800}, {"proj_b", 1800}]

      output = Report.format_subtotals_markdown(subtotals)

      assert output =~ "| Project | Duration |"
      assert output =~ "|---------|----------|"
      assert output =~ "| proj_a | 1h 20m |"
      assert output =~ "| proj_b | 0h 30m |"
    end

    test "formats empty subtotals as empty table" do
      output = Report.format_subtotals_markdown([])

      assert output =~ "| Project | Duration |"
      lines = String.split(output, "\n")
      assert length(lines) == 2
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

  describe "daily_project_hours/1" do
    test "returns empty map for empty stretches" do
      assert Report.daily_project_hours([]) == %{}
    end

    test "aggregates single stretch into project and date" do
      # 2026-01-15 09:00:00 UTC to 09:30:00 UTC (30 min = 0.5 hours)
      stretches = [
        %{repo: "my_project", start: 1_768_467_600, stop: 1_768_469_400}
      ]

      result = Report.daily_project_hours(stretches)

      assert result == %{
               "my_project" => %{
                 ~D[2026-01-15] => 0.5
               }
             }
    end

    test "aggregates multiple stretches on same day for same project" do
      # 2026-01-15 09:00 - 09:30 (30 min) and 14:00 - 15:00 (60 min) = 1.5 hours
      stretches = [
        %{repo: "my_project", start: 1_768_467_600, stop: 1_768_469_400},
        %{repo: "my_project", start: 1_768_485_600, stop: 1_768_489_200}
      ]

      result = Report.daily_project_hours(stretches)

      assert result == %{
               "my_project" => %{
                 ~D[2026-01-15] => 1.5
               }
             }
    end

    test "separates hours by date for same project" do
      # 2026-01-15 09:00 - 09:30 (30 min = 0.5h)
      # 2026-01-16 10:00 - 11:00 (60 min = 1.0h)
      stretches = [
        %{repo: "my_project", start: 1_768_467_600, stop: 1_768_469_400},
        %{repo: "my_project", start: 1_768_557_600, stop: 1_768_561_200}
      ]

      result = Report.daily_project_hours(stretches)

      assert result == %{
               "my_project" => %{
                 ~D[2026-01-15] => 0.5,
                 ~D[2026-01-16] => 1.0
               }
             }
    end

    test "separates hours by project" do
      # Same day, different projects
      # proj_a: 30 min = 0.5h, proj_b: 60 min = 1.0h
      stretches = [
        %{repo: "proj_a", start: 1_768_467_600, stop: 1_768_469_400},
        %{repo: "proj_b", start: 1_768_485_600, stop: 1_768_489_200}
      ]

      result = Report.daily_project_hours(stretches)

      assert result == %{
               "proj_a" => %{~D[2026-01-15] => 0.5},
               "proj_b" => %{~D[2026-01-15] => 1.0}
             }
    end

    test "handles multiple projects across multiple days" do
      stretches = [
        # proj_a: 2026-01-15 09:00 - 09:30, 30 min
        %{repo: "proj_a", start: 1_768_467_600, stop: 1_768_469_400},
        # proj_b: 2026-01-15 14:00 - 15:00, 60 min
        %{repo: "proj_b", start: 1_768_485_600, stop: 1_768_489_200},
        # proj_a: 2026-01-16 10:00 - 11:30, 90 min
        %{repo: "proj_a", start: 1_768_557_600, stop: 1_768_563_000}
      ]

      result = Report.daily_project_hours(stretches)

      assert result == %{
               "proj_a" => %{
                 ~D[2026-01-15] => 0.5,
                 ~D[2026-01-16] => 1.5
               },
               "proj_b" => %{
                 ~D[2026-01-15] => 1.0
               }
             }
    end

    test "converts seconds to decimal hours accurately" do
      # 2026-01-15 09:00 - 10:45, 1 hour 45 minutes = 6300 seconds = 1.75 hours
      stretches = [
        %{repo: "proj", start: 1_768_467_600, stop: 1_768_473_900}
      ]

      result = Report.daily_project_hours(stretches)

      assert result["proj"][~D[2026-01-15]] == 1.75
    end

    test "uses start timestamp to determine date" do
      # Stretch starts at 2026-01-15 23:30 UTC and ends at 2026-01-16 00:30 UTC
      # Should be attributed to 2026-01-15
      stretches = [
        %{repo: "proj", start: 1_768_519_800, stop: 1_768_523_400}
      ]

      result = Report.daily_project_hours(stretches)

      assert Map.has_key?(result["proj"], ~D[2026-01-15])
      refute Map.has_key?(result["proj"], ~D[2026-01-16])
    end
  end

  describe "format_json/3" do
    test "returns valid JSON with correct structure" do
      # 2026-01-15 09:00 - 09:30 (30 min = 0.5h)
      stretches = [
        %{repo: "my_project", start: 1_768_467_600, stop: 1_768_469_400}
      ]

      json = Report.format_json(stretches, ~D[2026-01-15], ~D[2026-01-15])
      result = Jason.decode!(json)

      assert result["start_date"] == "2026-01-15"
      assert result["end_date"] == "2026-01-15"
      assert is_map(result["projects"])
    end

    test "includes project with days array and total_hours" do
      stretches = [
        %{repo: "my_project", start: 1_768_467_600, stop: 1_768_469_400}
      ]

      json = Report.format_json(stretches, ~D[2026-01-15], ~D[2026-01-15])
      result = Jason.decode!(json)

      project = result["projects"]["my_project"]
      assert is_list(project["days"])
      assert is_number(project["total_hours"])
    end

    test "formats days as date and hours objects" do
      stretches = [
        %{repo: "my_project", start: 1_768_467_600, stop: 1_768_469_400}
      ]

      json = Report.format_json(stretches, ~D[2026-01-15], ~D[2026-01-15])
      result = Jason.decode!(json)

      [day] = result["projects"]["my_project"]["days"]
      assert day["date"] == "2026-01-15"
      assert day["hours"] == 0.5
    end

    test "calculates correct total_hours across multiple days" do
      stretches = [
        # 2026-01-15: 30 min = 0.5h
        %{repo: "my_project", start: 1_768_467_600, stop: 1_768_469_400},
        # 2026-01-16: 60 min = 1.0h
        %{repo: "my_project", start: 1_768_557_600, stop: 1_768_561_200}
      ]

      json = Report.format_json(stretches, ~D[2026-01-15], ~D[2026-01-16])
      result = Jason.decode!(json)

      assert result["projects"]["my_project"]["total_hours"] == 1.5
    end

    test "sorts days chronologically" do
      stretches = [
        # Add in reverse order
        %{repo: "my_project", start: 1_768_557_600, stop: 1_768_561_200},
        %{repo: "my_project", start: 1_768_467_600, stop: 1_768_469_400}
      ]

      json = Report.format_json(stretches, ~D[2026-01-15], ~D[2026-01-16])
      result = Jason.decode!(json)

      days = result["projects"]["my_project"]["days"]
      dates = Enum.map(days, & &1["date"])
      assert dates == ["2026-01-15", "2026-01-16"]
    end

    test "handles multiple projects" do
      stretches = [
        %{repo: "proj_a", start: 1_768_467_600, stop: 1_768_469_400},
        %{repo: "proj_b", start: 1_768_485_600, stop: 1_768_489_200}
      ]

      json = Report.format_json(stretches, ~D[2026-01-15], ~D[2026-01-15])
      result = Jason.decode!(json)

      assert Map.has_key?(result["projects"], "proj_a")
      assert Map.has_key?(result["projects"], "proj_b")
      assert result["projects"]["proj_a"]["total_hours"] == 0.5
      assert result["projects"]["proj_b"]["total_hours"] == 1.0
    end

    test "returns empty projects map for empty stretches" do
      json = Report.format_json([], ~D[2026-01-15], ~D[2026-01-15])
      result = Jason.decode!(json)

      assert result["projects"] == %{}
      assert result["start_date"] == "2026-01-15"
      assert result["end_date"] == "2026-01-15"
    end
  end
end
