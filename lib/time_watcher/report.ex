defmodule TimeWatcher.Report do
  @moduledoc """
  Merges event windows into activity stretches and formats reports.
  """

  alias TimeWatcher.Event

  @default_window_minutes 10

  @type stretch :: %{repo: String.t(), start: integer(), stop: integer()}

  @spec stretches([Event.t()], keyword()) :: [stretch()]
  def stretches(events, opts \\ []) do
    window_minutes = Keyword.get(opts, :window_minutes, @default_window_minutes)
    half_window = div(window_minutes * 60, 2)

    events
    |> Enum.group_by(& &1.repo)
    |> Enum.flat_map(fn {repo, repo_events} ->
      repo_events
      |> Enum.sort_by(& &1.timestamp)
      |> Enum.map(fn e ->
        %{repo: repo, start: e.timestamp - half_window, stop: e.timestamp + half_window}
      end)
      |> merge_windows()
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

  defp merge_windows([]), do: []

  defp merge_windows([first | rest]) do
    Enum.reduce(rest, [first], fn window, [current | acc] ->
      if window.start <= current.stop do
        [%{current | stop: max(current.stop, window.stop)} | acc]
      else
        [window, current | acc]
      end
    end)
    |> Enum.reverse()
  end
end
