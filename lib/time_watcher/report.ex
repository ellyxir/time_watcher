defmodule TimeWatcher.Report do
  @moduledoc """
  Merges nearby events into activity stretches and formats reports.

  The merge window determines how close events must be to be considered part of
  the same work session. Only stretches with at least two events are reported,
  since a single event cannot establish a duration.
  """

  alias TimeWatcher.Event

  @default_merge_window_minutes 10

  @type stretch :: %{repo: String.t(), start: integer(), stop: integer()}

  @doc """
  Groups events into stretches of continuous activity.

  Events within `merge_window_minutes` of each other are merged into a single
  stretch. The stretch boundaries are the actual timestamps of the first and
  last events (no padding). Single events are excluded since they don't
  establish a measurable duration.

  ## Options

    * `:merge_window_minutes` - max gap between events to merge (default: 10)

  """
  @spec stretches([Event.t()], keyword()) :: [stretch()]
  def stretches(events, opts \\ []) do
    # Supports legacy :window_minutes for backward compatibility
    merge_window_minutes =
      Keyword.get(opts, :merge_window_minutes) ||
        Keyword.get(opts, :window_minutes, @default_merge_window_minutes)

    merge_window_seconds = merge_window_minutes * 60

    events
    |> Enum.group_by(& &1.repo)
    |> Enum.flat_map(fn {repo, repo_events} ->
      repo_events
      |> Enum.sort_by(& &1.timestamp)
      |> merge_events(repo, merge_window_seconds)
    end)
    |> Enum.sort_by(& &1.start)
  end

  @doc """
  Returns the duration of a stretch in seconds.
  """
  @spec duration(stretch()) :: non_neg_integer()
  def duration(stretch), do: stretch.stop - stretch.start

  @doc """
  Returns the total duration of all stretches in seconds.
  """
  @spec total_duration([stretch()]) :: non_neg_integer()
  def total_duration(stretches) do
    Enum.reduce(stretches, 0, fn s, acc -> acc + duration(s) end)
  end

  @doc """
  Formats stretches as human-readable text lines.
  """
  @spec format([stretch()]) :: String.t()
  def format(stretches) do
    Enum.map_join(stretches, "\n", fn s ->
      {start_time, stop_time, duration} = format_stretch_parts(s)
      "  #{start_time} - #{stop_time}  #{s.repo}  (#{duration})"
    end)
  end

  @typedoc "A tuple of project name and total duration in seconds."
  @type subtotal :: {String.t(), non_neg_integer()}

  @typedoc "A map of dates to hours worked (as decimal)."
  @type daily_hours :: %{Date.t() => float()}

  @typedoc "A map of project names to their daily hours."
  @type project_daily_hours :: %{String.t() => daily_hours()}

  @doc """
  Calculates total duration per project from stretches.

  Returns a list of `{project_name, total_seconds}` tuples sorted alphabetically
  by project name.
  """
  @spec subtotals([stretch()]) :: [subtotal()]
  def subtotals(stretches) do
    stretches
    |> Enum.group_by(& &1.repo)
    |> Enum.map(fn {repo, repo_stretches} -> {repo, total_duration(repo_stretches)} end)
    |> Enum.sort_by(fn {repo, _} -> repo end)
  end

  @doc """
  Formats subtotals as human-readable text lines.
  """
  @spec format_subtotals([subtotal()]) :: String.t()
  def format_subtotals([]), do: ""

  def format_subtotals(subtotals) do
    Enum.map_join(subtotals, "\n", fn {repo, seconds} ->
      "  #{repo}: #{format_duration(seconds)}"
    end)
  end

  @doc """
  Formats subtotals as a markdown table.
  """
  @spec format_subtotals_markdown([subtotal()]) :: String.t()
  def format_subtotals_markdown(subtotals) do
    header = "| Project | Duration |"
    separator = "|---------|----------|"

    rows =
      Enum.map(subtotals, fn {repo, seconds} ->
        "| #{repo} | #{format_duration(seconds)} |"
      end)

    Enum.join([header, separator | rows], "\n")
  end

  @doc """
  Formats stretches as a markdown table.
  """
  @spec format_markdown([stretch()]) :: String.t()
  def format_markdown(stretches) do
    header = "| Time | Project | Duration |"
    separator = "|------|---------|----------|"

    rows =
      Enum.map(stretches, fn s ->
        {start_time, stop_time, duration} = format_stretch_parts(s)
        "| #{start_time} - #{stop_time} | #{s.repo} | #{duration} |"
      end)

    Enum.join([header, separator | rows], "\n")
  end

  @spec format_stretch_parts(stretch()) :: {String.t(), String.t(), String.t()}
  defp format_stretch_parts(s) do
    start_time = DateTime.from_unix!(s.start) |> Calendar.strftime("%H:%M")
    stop_time = DateTime.from_unix!(s.stop) |> Calendar.strftime("%H:%M")
    {start_time, stop_time, format_duration(duration(s))}
  end

  @spec format_duration(non_neg_integer()) :: String.t()
  defp format_duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    "#{hours}h #{minutes}m"
  end

  @doc """
  Aggregates stretches into daily hours per project.

  Returns a map where keys are project names and values are maps of dates to
  decimal hours. Only includes days with actual activity.

  Hours are calculated as decimals (e.g., 90 minutes = 1.5 hours).
  The date is determined by the stretch's start timestamp in UTC.
  """
  @spec daily_project_hours([stretch()]) :: project_daily_hours()
  def daily_project_hours([]), do: %{}

  def daily_project_hours(stretches) do
    stretches
    |> Enum.reduce(%{}, fn stretch, acc ->
      date = DateTime.from_unix!(stretch.start) |> DateTime.to_date()
      hours = duration(stretch) / 3600.0

      acc
      |> Map.update(stretch.repo, %{date => hours}, fn dates ->
        Map.update(dates, date, hours, &(&1 + hours))
      end)
    end)
  end

  @spec merge_events([Event.t()], String.t(), integer()) :: [stretch()]
  defp merge_events([], _repo, _merge_window), do: []

  defp merge_events([first | rest], repo, merge_window) do
    initial = %{start: first.timestamp, stop: first.timestamp, count: 1}

    rest
    |> Enum.reduce([initial], fn event, [current | acc] ->
      if event.timestamp - current.stop <= merge_window do
        [%{current | stop: event.timestamp, count: current.count + 1} | acc]
      else
        [%{start: event.timestamp, stop: event.timestamp, count: 1}, current | acc]
      end
    end)
    |> Enum.filter(fn stretch -> stretch.count >= 2 end)
    |> Enum.map(fn stretch -> %{repo: repo, start: stretch.start, stop: stretch.stop} end)
    |> Enum.reverse()
  end
end
