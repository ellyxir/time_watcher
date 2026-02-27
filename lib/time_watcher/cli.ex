defmodule TimeWatcher.CLI do
  @moduledoc """
  CLI entry point for the time watcher.
  """

  alias TimeWatcher.{Client, Daemon, Decoder, Report, Storage}

  @typep command ::
           {:report, String.t() | :multi_day | :date_range, keyword()}
           | {:watch, [String.t()], [atom()]}
           | :stop
           | :list
           | {:remove, [String.t()]}
           | :commit
           | {:commit, String.t()}
           | {:reset, String.t() | :all}
           | {:decode, String.t(), String.t()}
           | :version
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
    dirs = if dirs == [], do: default_dirs(), else: dirs
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

  def parse_args(["commit"]) do
    :commit
  end

  def parse_args(["commit", "-m", message]) do
    {:commit, message}
  end

  def parse_args(["commit", "--message", message]) do
    {:commit, message}
  end

  def parse_args(["reset"]) do
    {:reset, Date.to_string(Date.utc_today())}
  end

  def parse_args(["reset", "--all"]) do
    {:reset, :all}
  end

  def parse_args(["reset", date]) do
    {:reset, date}
  end

  def parse_args(["decode", repo_path]) do
    {:decode, repo_path, Date.to_string(Date.utc_today())}
  end

  def parse_args(["decode", repo_path, date]) do
    {:decode, repo_path, date}
  end

  def parse_args(["--version"]) do
    :version
  end

  def parse_args(["-V"]) do
    :version
  end

  def parse_args(_) do
    :help
  end

  @spec version() :: String.t()
  def version do
    Application.spec(:time_watcher, :vsn) |> to_string()
  end

  @spec parse_report_args([String.t()]) ::
          {String.t() | :multi_day | :date_range, keyword()} | {:error, String.t()}
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

        "--from", {date, opts} ->
          {date, [{:pending_from, true} | opts]}

        arg, {date, [{:pending_from, true} | rest]} ->
          {date, [{:from, arg} | rest]}

        "--to", {date, opts} ->
          {date, [{:pending_to, true} | opts]}

        arg, {date, [{:pending_to, true} | rest]} ->
          {date, [{:to, arg} | rest]}

        "--md", {date, opts} ->
          {date, [{:md, true} | opts]}

        arg, {nil, opts} ->
          {arg, opts}

        _arg, acc ->
          acc
      end)

    opts =
      opts
      |> Keyword.delete(:pending_cooldown)
      |> Keyword.delete(:pending_days)
      |> Keyword.delete(:pending_from)
      |> Keyword.delete(:pending_to)

    validate_report_args(date, opts)
  end

  @spec validate_report_args(String.t() | nil, keyword()) ::
          {String.t() | :multi_day | :date_range, keyword()} | {:error, String.t()}
  defp validate_report_args(date, opts) do
    has_from = Keyword.has_key?(opts, :from)
    has_to = Keyword.has_key?(opts, :to)
    has_days = Keyword.has_key?(opts, :days)

    # Apply config cooldown if no CLI cooldown was provided
    opts = apply_config_cooldown(opts)

    cond do
      has_from or has_to -> validate_date_range_args(date, opts, has_from, has_to, has_days)
      has_days -> validate_days_args(date, opts)
      true -> {date || Date.to_string(Date.utc_today()), opts}
    end
  end

  @spec apply_config_cooldown(keyword()) :: keyword()
  defp apply_config_cooldown(opts) do
    if Keyword.has_key?(opts, :cooldown) do
      opts
    else
      case Application.get_env(:time_watcher, :cooldown) do
        nil -> opts
        cooldown when is_integer(cooldown) -> [{:cooldown, cooldown} | opts]
      end
    end
  end

  @spec validate_date_range_args(String.t() | nil, keyword(), boolean(), boolean(), boolean()) ::
          {:date_range, keyword()} | {:error, String.t()}
  defp validate_date_range_args(date, opts, has_from, has_to, has_days) do
    cond do
      has_from and not has_to -> {:error, "--from requires --to (and vice versa)"}
      has_to and not has_from -> {:error, "--from requires --to (and vice versa)"}
      has_days -> {:error, "--from/--to cannot be combined with --days"}
      date != nil -> {:error, "--from/--to cannot be combined with a date argument"}
      true -> validate_date_range_order(opts)
    end
  end

  @spec validate_date_range_order(keyword()) :: {:date_range, keyword()} | {:error, String.t()}
  defp validate_date_range_order(opts) do
    from_str = Keyword.fetch!(opts, :from)
    to_str = Keyword.fetch!(opts, :to)
    from_date = Date.from_iso8601!(from_str)
    to_date = Date.from_iso8601!(to_str)

    if Date.compare(from_date, to_date) == :gt do
      {:error, "--from date must be before or equal to --to date"}
    else
      {:date_range, opts}
    end
  end

  @spec validate_days_args(String.t() | nil, keyword()) ::
          {:multi_day, keyword()} | {:error, String.t()}
  defp validate_days_args(date, opts) do
    cond do
      date != nil -> {:error, "--days cannot be combined with a date argument"}
      Keyword.get(opts, :days) <= 0 -> {:error, "--days must be a positive integer"}
      true -> {:multi_day, opts}
    end
  end

  @spec parse_watch_args([String.t()]) :: {[String.t()], [atom()]}
  defp parse_watch_args(args) do
    {dirs, opts, has_verbose_flag} =
      Enum.reduce(args, {[], [], false}, fn
        "-v", {dirs, opts, _} -> {dirs, [:verbose | opts], true}
        "--verbose", {dirs, opts, _} -> {dirs, [:verbose | opts], true}
        dir, {dirs, opts, has_flag} -> {dirs ++ [dir], opts, has_flag}
      end)

    # Apply config verbose if no CLI flag was given
    opts =
      cond do
        has_verbose_flag -> opts
        Application.get_env(:time_watcher, :verbose, false) -> [:verbose | opts]
        true -> opts
      end

    {dirs, opts}
  end

  @spec default_dirs() :: [String.t()]
  defp default_dirs do
    case Application.get_env(:time_watcher, :dirs) do
      nil -> ["."]
      [] -> ["."]
      dirs when is_list(dirs) -> dirs
    end
  end

  defp run({:error, message}) do
    IO.puts("Error: #{message}")
  end

  defp run({:report, :multi_day, opts}) do
    days = Keyword.fetch!(opts, :days)
    dates = generate_date_list(days)
    run_multi_day_report(dates, opts)
  end

  defp run({:report, :date_range, opts}) do
    from_str = Keyword.fetch!(opts, :from)
    to_str = Keyword.fetch!(opts, :to)
    dates = generate_date_range(from_str, to_str)
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

  defp run(:commit) do
    run_commit("sync activity data")
  end

  defp run({:commit, message}) do
    run_commit(message)
  end

  defp run({:reset, :all}) do
    run_reset_all()
  end

  defp run({:reset, date}) do
    run_reset_date(date)
  end

  defp run({:decode, repo_path, date}) do
    run_decode(repo_path, date)
  end

  defp run(:version) do
    IO.puts("tw #{version()}")
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
      tw commit [-m "message"]                Commit event data to git
      tw reset [YYYY-MM-DD]                   Delete events for date (default: today)
      tw reset --all                          Delete all events
      tw decode <repo-path> [YYYY-MM-DD]      Show events with decoded file paths

    Options:
      -v, --verbose      Print events as they are recorded
      --cooldown N       Minutes of inactivity to count as continuous (default: 5)
      --md               Output report in markdown format
      --days N           Show last N days of activity (including today)
      --from DATE        Start of date range (requires --to)
      --to DATE          End of date range (requires --from)
    """)
  end

  defp run_commit(message) do
    case Storage.git_commit(message) do
      :ok ->
        IO.puts("Committed: #{message}")

      {:error, reason} ->
        IO.puts("Commit failed: #{inspect(reason)}")
    end
  end

  defp run_reset_date(date) do
    with {:ok, count} when count > 0 <- Storage.delete_events(date),
         :ok <- Storage.git_stage_all() do
      IO.puts("Deleted #{count} event(s) for #{date}. Run 'tw commit' to finalize.")
    else
      {:ok, 0} -> IO.puts("No events found for #{date}")
      {:error, reason} -> IO.puts("Failed to stage deletions: #{inspect(reason)}")
    end
  end

  defp run_reset_all do
    with {:ok, count} when count > 0 <- Storage.delete_all_events(),
         :ok <- Storage.git_stage_all() do
      IO.puts("Deleted #{count} event(s). Run 'tw commit' to finalize.")
    else
      {:ok, 0} -> IO.puts("No events found")
      {:error, reason} -> IO.puts("Failed to stage deletions: #{inspect(reason)}")
    end
  end

  defp run_decode(repo_path, date) do
    expanded_path = Path.expand(repo_path)
    repo_name = Path.basename(expanded_path)

    events =
      date
      |> Storage.load_events()
      |> Enum.filter(&(&1.repo == repo_name))

    if events == [] do
      IO.puts("No events found for #{repo_name} on #{date}")
    else
      hash_map = Decoder.build_hash_map(expanded_path)
      decoded_events = Decoder.decode_events(events, hash_map)

      IO.puts("Events for #{repo_name} on #{date}:\n")

      Enum.each(decoded_events, fn event ->
        time = event.timestamp |> DateTime.from_unix!() |> Calendar.strftime("%H:%M:%S")
        path = format_decoded_path(event.decoded_path, expanded_path)
        IO.puts("  [#{time}] #{event.event_type} #{path}")
      end)

      decoded_count = Enum.count(decoded_events, & &1.decoded_path)
      total_count = length(decoded_events)

      IO.puts("\nDecoded #{decoded_count}/#{total_count} file paths")
    end
  end

  defp format_decoded_path(nil, _repo_path), do: "(unknown file)"

  defp format_decoded_path(path, repo_path) do
    Path.relative_to(path, repo_path)
  end

  @spec generate_date_list(pos_integer()) :: [String.t()]
  defp generate_date_list(days) do
    today = Date.utc_today()

    (days - 1)..0//-1
    |> Enum.map(fn offset -> today |> Date.add(-offset) |> Date.to_string() end)
  end

  @spec generate_date_range(String.t(), String.t()) :: [String.t()]
  defp generate_date_range(from_str, to_str) do
    from_date = Date.from_iso8601!(from_str)
    to_date = Date.from_iso8601!(to_str)
    diff = Date.diff(to_date, from_date)

    0..diff
    |> Enum.map(fn offset -> from_date |> Date.add(offset) |> Date.to_string() end)
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
