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
  Formats stretches as human-readable text lines.
  """
  @spec format([stretch()]) :: String.t()
  def format(stretches) do
    Enum.map_join(stretches, "\n", fn s ->
      {start_time, stop_time, duration} = format_stretch_parts(s)
      "  #{start_time} - #{stop_time}  #{s.repo}  (#{duration})"
    end)
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
    duration_seconds = s.stop - s.start
    hours = div(duration_seconds, 3600)
    minutes = div(rem(duration_seconds, 3600), 60)
    {start_time, stop_time, "#{hours}h #{minutes}m"}
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
