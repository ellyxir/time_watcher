defmodule TimeWatcher.CLI do
  @moduledoc """
  CLI entry point for the time watcher.
  """

  alias TimeWatcher.{Report, Storage, Watcher}

  @spec main([String.t()]) :: :ok
  def main(args) do
    args |> parse_args() |> run()
  end

  @spec parse_args([String.t()]) :: {:report, String.t()} | {:watch, [String.t()]} | :help
  def parse_args(["report", date]) do
    {:report, date}
  end

  def parse_args(["report"]) do
    {:report, Date.to_string(Date.utc_today())}
  end

  def parse_args(["watch" | []]) do
    {:watch, ["."]}
  end

  def parse_args(["watch" | dirs]) do
    {:watch, dirs}
  end

  def parse_args(_) do
    :help
  end

  defp run({:report, date}) do
    events = Storage.load_events(date)
    stretches = Report.stretches(events)

    if stretches == [] do
      IO.puts("No activity recorded for #{date}")
    else
      IO.puts("Activity for #{date}:\n")
      IO.puts(Report.format(stretches))

      total_seconds = Enum.reduce(stretches, 0, fn s, acc -> acc + (s.stop - s.start) end)
      hours = div(total_seconds, 3600)
      minutes = div(rem(total_seconds, 3600), 60)
      IO.puts("\nTotal: #{hours}h #{minutes}m")
    end
  end

  defp run({:watch, dirs}) do
    IO.puts("Watching: #{Enum.join(dirs, ", ")}")

    data_dir = Storage.data_dir()
    File.mkdir_p!(data_dir)

    {:ok, _pid} = Watcher.start_link(dirs: dirs, data_dir: data_dir, name: TimeWatcher.Watcher)

    # Keep the process alive
    Process.sleep(:infinity)
  end

  defp run(:help) do
    IO.puts("""
    tw - git-based time tracker

    Usage:
      tw watch [dir1 dir2 ...]   Watch directories for file changes (default: .)
      tw report [YYYY-MM-DD]     Show activity report (default: today)
    """)
  end
end
