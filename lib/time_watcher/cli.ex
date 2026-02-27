defmodule TimeWatcher.CLI do
  @moduledoc """
  CLI entry point for the time watcher.
  """

  alias TimeWatcher.{Client, Daemon, Report, Storage}

  @typep command ::
           {:report, String.t() | :multi_day, keyword()}
           | {:watch, [String.t()], [atom()]}
           | :stop
           | :list
           | {:remove, [String.t()]}
           | :help
           | {:error, String.t()}

  @spec main([String.t()]) :: :ok
  def main(args) do
    args |> parse_args() |> run()
  end

  @spec parse_args([String.t()]) :: command()
  def parse_args(["report" | rest]) do
    case parse_report_args(rest) do
      {:error, _} = error -> error
      {date, opts} -> {:report, date, opts}
    end
  end

  def parse_args(["watch" | rest]) do
    {dirs, opts} = parse_watch_args(rest)
    dirs = if dirs == [], do: ["."], else: dirs
    {:watch, dirs, opts}
  end

  def parse_args(["stop"]) do
    :stop
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

  @spec parse_report_args([String.t()]) ::
          {String.t() | :multi_day, keyword()} | {:error, String.t()}
  defp parse_report_args(args) do
    {date, opts} =
      Enum.reduce(args, {nil, []}, fn
        "--cooldown", {date, opts} ->
          {date, [{:pending_cooldown, true} | opts]}

        arg, {date, [{:pending_cooldown, true} | rest]} ->
          {date, [{:cooldown, String.to_integer(arg)} | rest]}

        "--days", {date, opts} ->
          {date, [{:pending_days, true} | opts]}

        arg, {date, [{:pending_days, true} | rest]} ->
          {date, [{:days, String.to_integer(arg)} | rest]}

        "--md", {date, opts} ->
          {date, [{:md, true} | opts]}

        arg, {nil, opts} ->
          {arg, opts}

        _arg, acc ->
          acc
      end)

    opts = opts |> Keyword.delete(:pending_cooldown) |> Keyword.delete(:pending_days)

    cond do
      Keyword.has_key?(opts, :days) and date != nil ->
        {:error, "--days cannot be combined with a date argument"}

      Keyword.has_key?(opts, :days) and Keyword.get(opts, :days) <= 0 ->
        {:error, "--days must be a positive integer"}

      Keyword.has_key?(opts, :days) ->
        {:multi_day, opts}

      true ->
        date = date || Date.to_string(Date.utc_today())
        {date, opts}
    end
  end

  @spec parse_watch_args([String.t()]) :: {[String.t()], [atom()]}
  defp parse_watch_args(args) do
    Enum.reduce(args, {[], []}, fn
      "-v", {dirs, opts} -> {dirs, [:verbose | opts]}
      "--verbose", {dirs, opts} -> {dirs, [:verbose | opts]}
      dir, {dirs, opts} -> {dirs ++ [dir], opts}
    end)
  end

  defp run({:error, message}) do
    IO.puts("Error: #{message}")
  end

  defp run({:report, :multi_day, opts}) do
    days = Keyword.fetch!(opts, :days)
    dates = generate_date_list(days)
    run_multi_day_report(dates, opts)
  end

  defp run({:report, date, opts}) do
    events = Storage.load_events(date)
    report_opts = build_report_opts(opts)
    stretches = Report.stretches(events, report_opts)
    markdown? = Keyword.get(opts, :md, false)

    if stretches == [] do
      IO.puts("No activity recorded for #{date}")
    else
      total_seconds = Enum.reduce(stretches, 0, fn s, acc -> acc + (s.stop - s.start) end)
      hours = div(total_seconds, 3600)
      minutes = div(rem(total_seconds, 3600), 60)

      if markdown? do
        IO.puts("## Activity for #{date}\n")
        IO.puts(Report.format_markdown(stretches))
        IO.puts("\n**Total: #{hours}h #{minutes}m**")
      else
        IO.puts("Activity for #{date}:\n")
        IO.puts(Report.format(stretches))
        IO.puts("\nTotal: #{hours}h #{minutes}m")
      end
    end
  end

  defp run({:watch, dirs, opts}) do
    verbose = :verbose in opts

    case Daemon.start_daemon(dirs: dirs, verbose: verbose) do
      :ok ->
        :ok

      {:error, :already_running} ->
        # Daemon already running - add the directories to it
        add_directories(dirs)

      {:error, reason} ->
        IO.puts("Error starting daemon: #{inspect(reason)}")
    end
  end

  defp run(:stop) do
    case Client.stop_daemon() do
      :ok ->
        IO.puts("Daemon stopped.")

      {:error, :daemon_not_running} ->
        IO.puts("Daemon is not running.")

      {:error, reason} ->
        IO.puts("Error stopping daemon: #{inspect(reason)}")
    end
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
      tw watch [-v] [dir1 dir2 ...]           Start daemon or add directories to it
      tw stop                                 Stop the daemon
      tw list                                 List watched directories
      tw remove <dir1 dir2 ...>               Remove directories from daemon
      tw report [YYYY-MM-DD] [options]        Show activity report (default: today)

    Options:
      -v, --verbose      Print events as they are recorded
      --cooldown N       Minutes of inactivity to count as continuous (default: 5)
      --md               Output report in markdown format
      --days N           Show last N days of activity (including today)
    """)
  end

  @spec generate_date_list(pos_integer()) :: [String.t()]
  defp generate_date_list(days) do
    today = Date.utc_today()

    (days - 1)..0//-1
    |> Enum.map(fn offset -> today |> Date.add(-offset) |> Date.to_string() end)
  end

  @spec run_multi_day_report([String.t()], keyword()) :: :ok
  defp run_multi_day_report(dates, opts) do
    report_opts = build_report_opts(opts)
    markdown? = Keyword.get(opts, :md, false)

    day_results =
      dates
      |> Enum.map(fn date ->
        events = Storage.load_events(date)
        stretches = Report.stretches(events, report_opts)
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

  @spec print_grand_total(pos_integer(), non_neg_integer(), boolean()) :: :ok
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

  @spec sum_stretches([Report.stretch()]) :: non_neg_integer()
  defp sum_stretches(stretches) do
    Enum.reduce(stretches, 0, fn s, acc -> acc + (s.stop - s.start) end)
  end

  @spec print_day_report(String.t(), [Report.stretch()], boolean()) :: :ok
  defp print_day_report(date, stretches, markdown?) do
    day_total = sum_stretches(stretches)
    day_hours = div(day_total, 3600)
    day_minutes = div(rem(day_total, 3600), 60)

    if markdown? do
      IO.puts("## Activity for #{date}\n")
      IO.puts(Report.format_markdown(stretches))
      IO.puts("\n**Day total: #{day_hours}h #{day_minutes}m**\n")
    else
      IO.puts("Activity for #{date}:\n")
      IO.puts(Report.format(stretches))
      IO.puts("\nDay total: #{day_hours}h #{day_minutes}m\n")
    end
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

  @spec add_directories([String.t()]) :: :ok
  defp add_directories(dirs) do
    Enum.each(dirs, fn dir ->
      case Client.add_directory(dir) do
        :ok ->
          IO.puts("Added: #{dir}")

        {:error, :already_watching} ->
          IO.puts("Already watching: #{dir}")

        {:error, :would_cause_loop} ->
          IO.puts(
            "Cannot watch #{dir}: would cause infinite loop (contains or is inside data directory)"
          )

        {:error, reason} ->
          IO.puts("Error adding #{dir}: #{inspect(reason)}")
      end
    end)
  end
end
