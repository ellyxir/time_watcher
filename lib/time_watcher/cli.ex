defmodule TimeWatcher.CLI do
  @moduledoc """
  CLI entry point for the time watcher.
  """

  alias TimeWatcher.{Client, Daemon, Report, Storage}

  @typep command ::
           {:report, String.t(), keyword()}
           | {:watch, [String.t()], [atom()]}
           | {:add, [String.t()]}
           | :list
           | {:remove, [String.t()]}
           | :help

  @spec main([String.t()]) :: :ok
  def main(args) do
    args |> parse_args() |> run()
  end

  @spec parse_args([String.t()]) :: command()
  def parse_args(["report" | rest]) do
    {date, opts} = parse_report_args(rest)
    {:report, date, opts}
  end

  def parse_args(["watch" | rest]) do
    {dirs, opts} = parse_watch_args(rest)
    dirs = if dirs == [], do: ["."], else: dirs
    {:watch, dirs, opts}
  end

  def parse_args(["add" | dirs]) when dirs != [] do
    {:add, dirs}
  end

  def parse_args(["list"]) do
    :list
  end

  def parse_args(["remove" | dirs]) when dirs != [] do
    {:remove, dirs}
  end

  def parse_args(_) do
    :help
  end

  @spec parse_report_args([String.t()]) :: {String.t(), keyword()}
  defp parse_report_args(args) do
    {date, opts} =
      Enum.reduce(args, {nil, []}, fn
        "--cooldown", {date, opts} ->
          {date, [{:pending_cooldown, true} | opts]}

        arg, {date, [{:pending_cooldown, true} | rest]} ->
          {date, [{:cooldown, String.to_integer(arg)} | rest]}

        arg, {nil, opts} ->
          {arg, opts}

        _arg, acc ->
          acc
      end)

    date = date || Date.to_string(Date.utc_today())
    opts = Keyword.delete(opts, :pending_cooldown)
    {date, opts}
  end

  @spec parse_watch_args([String.t()]) :: {[String.t()], [atom()]}
  defp parse_watch_args(args) do
    Enum.reduce(args, {[], []}, fn
      "-v", {dirs, opts} -> {dirs, [:verbose | opts]}
      "--verbose", {dirs, opts} -> {dirs, [:verbose | opts]}
      dir, {dirs, opts} -> {dirs ++ [dir], opts}
    end)
  end

  defp run({:report, date, opts}) do
    events = Storage.load_events(date)
    report_opts = build_report_opts(opts)
    stretches = Report.stretches(events, report_opts)

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

  defp run({:watch, dirs, opts}) do
    verbose = :verbose in opts

    case Daemon.start_daemon(dirs: dirs, verbose: verbose) do
      :ok ->
        :ok

      {:error, :already_running} ->
        IO.puts("Error: Daemon is already running. Use 'tw add' to add directories.")

      {:error, reason} ->
        IO.puts("Error starting daemon: #{inspect(reason)}")
    end
  end

  defp run({:add, dirs}) do
    Enum.each(dirs, fn dir ->
      case Client.add_directory(dir) do
        :ok ->
          IO.puts("Added: #{dir}")

        {:error, :already_watching} ->
          IO.puts("Already watching: #{dir}")

        {:error, :would_cause_loop} ->
          IO.puts("Cannot watch #{dir}: would cause infinite loop (contains or is inside data directory)")

        {:error, reason} ->
          IO.puts("Error adding #{dir}: #{inspect(reason)}")
      end
    end)
  end

  defp run(:list) do
    case Client.list_directories() do
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
        IO.puts("Is the daemon running? Start it with 'tw watch [dirs]'")

      [] ->
        IO.puts("No directories being watched.")

      dirs when is_list(dirs) ->
        IO.puts("Watched directories:")
        Enum.each(dirs, &print_dir/1)
    end
  end

  defp run({:remove, dirs}) do
    Enum.each(dirs, fn dir ->
      case Client.remove_directory(dir) do
        :ok ->
          IO.puts("Removed: #{dir}")

        {:error, :not_watching} ->
          IO.puts("Not watching: #{dir}")

        {:error, reason} ->
          IO.puts("Error removing #{dir}: #{inspect(reason)}")
      end
    end)
  end

  defp run(:help) do
    IO.puts("""
    tw - git-based time tracker

    Usage:
      tw watch [-v] [dir1 dir2 ...]           Start daemon watching directories (default: .)
      tw add <dir1 dir2 ...>                  Add directories to running daemon
      tw list                                 List watched directories
      tw remove <dir1 dir2 ...>               Remove directories from daemon
      tw report [YYYY-MM-DD] [--cooldown N]   Show activity report (default: today)

    Options:
      -v, --verbose      Print events as they are recorded
      --cooldown N       Minutes of inactivity to count as continuous (default: 5)
    """)
  end

  @spec build_report_opts(keyword()) :: keyword()
  defp build_report_opts(opts) do
    case Keyword.get(opts, :cooldown) do
      nil -> []
      minutes -> [window_minutes: minutes * 2]
    end
  end

  defp print_dir(dir) do
    IO.puts("  #{dir.path} (#{dir.repo})")
  end
end
