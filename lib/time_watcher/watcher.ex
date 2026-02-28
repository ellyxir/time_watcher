defmodule TimeWatcher.Watcher do
  @moduledoc """
  GenServer that watches filesystem changes and records debounced events.
  """

  use GenServer
  require Logger

  alias TimeWatcher.{Event, Storage}

  @default_debounce_seconds 60

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec detect_repo(String.t()) :: String.t()
  def detect_repo(path) do
    path |> Path.expand() |> Path.basename()
  end

  @spec map_event_type([atom()]) :: :created | :modified | :deleted
  def map_event_type(types) do
    cond do
      :created in types -> :created
      :removed in types -> :deleted
      :deleted in types -> :deleted
      :modified in types -> :modified
      true -> :modified
    end
  end

  @spec add_dir(GenServer.server(), String.t()) ::
          :ok
          | {:error,
             :already_watching
             | :would_cause_loop
             | :directory_not_found
             | :filesystem_backend_unavailable}
  def add_dir(server, dir) do
    GenServer.call(server, {:add_dir, dir})
  end

  @spec list_dirs(GenServer.server()) :: [%{path: String.t(), repo: String.t()}]
  def list_dirs(server) do
    GenServer.call(server, :list_dirs)
  end

  @spec remove_dir(GenServer.server(), String.t()) :: :ok | {:error, :not_watching}
  def remove_dir(server, dir) do
    GenServer.call(server, {:remove_dir, dir})
  end

  @spec stop(GenServer.server()) :: :ok
  def stop(server) do
    GenServer.call(server, :stop)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    dirs = Keyword.fetch!(opts, :dirs)
    data_dir = Keyword.get(opts, :data_dir, Storage.data_dir())
    expanded_data_dir = Path.expand(data_dir)
    debounce_seconds = Keyword.get(opts, :debounce_seconds, @default_debounce_seconds)
    verbose = Keyword.get(opts, :verbose, false)
    ignore_patterns = Keyword.get(opts, :ignore_patterns, [])

    # Filter out directories that would cause infinite loops
    safe_dirs =
      dirs
      |> Enum.map(&Path.expand/1)
      |> Enum.reject(&would_cause_loop?(&1, expanded_data_dir))

    if length(safe_dirs) < length(dirs) do
      Logger.warning(
        "Some directories were excluded to prevent infinite loops with data directory"
      )
    end

    # Start file watchers, tracking which directories successfully started
    {watcher_pids, active_dirs} =
      Enum.reduce(safe_dirs, {%{}, []}, fn expanded, acc ->
        maybe_start_watcher(expanded, acc)
      end)

    dir_repo_map =
      Map.new(active_dirs, fn expanded ->
        {expanded, detect_repo(expanded)}
      end)

    if verbose do
      repos = dir_repo_map |> Map.values() |> Enum.sort() |> Enum.join(", ")
      IO.puts("Watching: #{repos}")
    end

    {:ok,
     %{
       dir_repo_map: dir_repo_map,
       data_dir: data_dir,
       debounce_seconds: debounce_seconds,
       last_event_at: %{},
       watcher_pids: watcher_pids,
       verbose: verbose,
       ignore_patterns: ignore_patterns
     }}
  end

  @impl true
  def handle_call({:add_dir, dir}, _from, state) do
    expanded = Path.expand(dir)
    data_dir = Path.expand(state.data_dir)

    cond do
      Map.has_key?(state.dir_repo_map, expanded) ->
        {:reply, {:error, :already_watching}, state}

      not File.dir?(expanded) ->
        {:reply, {:error, :directory_not_found}, state}

      would_cause_loop?(expanded, data_dir) ->
        {:reply, {:error, :would_cause_loop}, state}

      true ->
        start_watcher_for_dir(expanded, state)
    end
  end

  @impl true
  def handle_call(:list_dirs, _from, state) do
    dirs =
      state.dir_repo_map
      |> Enum.map(fn {path, repo} -> %{path: path, repo: repo} end)
      |> Enum.sort_by(& &1.path)

    {:reply, dirs, state}
  end

  @impl true
  def handle_call({:remove_dir, dir}, _from, state) do
    expanded = Path.expand(dir)

    case Map.get(state.watcher_pids, expanded) do
      nil ->
        {:reply, {:error, :not_watching}, state}

      pid ->
        # Safely stop the watcher - it may already be dead
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5000)

        new_state = %{
          state
          | dir_repo_map: Map.delete(state.dir_repo_map, expanded),
            watcher_pids: Map.delete(state.watcher_pids, expanded)
        }

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    # Schedule application stop after reply is sent
    spawn(fn ->
      Process.sleep(100)
      :init.stop()
    end)

    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    now = System.system_time(:second)
    repo = find_repo(path, state.dir_repo_map)

    if repo && !ignored_path?(path, state.ignore_patterns) && !debounced?(path, now, state) do
      event = build_event(path, events, repo, now)
      save_event(event, path, state)
      {:noreply, %{state | last_event_at: Map.put(state.last_event_at, path, now)}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, :stop}, state) do
    Logger.warning("File watcher stopped")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up all file watchers on shutdown
    Enum.each(state.watcher_pids, fn {_dir, pid} ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5000)
    end)

    :ok
  end

  defp start_watcher_for_dir(expanded, state) do
    case FileSystem.start_link(dirs: [expanded]) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        repo = detect_repo(expanded)
        if state.verbose, do: IO.puts("Added: #{repo}")

        new_state = %{
          state
          | dir_repo_map: Map.put(state.dir_repo_map, expanded, repo),
            watcher_pids: Map.put(state.watcher_pids, expanded, pid)
        }

        {:reply, :ok, new_state}

      :ignore ->
        {:reply, {:error, :filesystem_backend_unavailable}, state}

      {:error, reason} ->
        Logger.error("Failed to start file watcher for #{expanded}: #{inspect(reason)}")
        {:reply, {:error, :filesystem_backend_unavailable}, state}
    end
  end

  defp maybe_start_watcher(expanded, {pids, dirs}) do
    if File.dir?(expanded) do
      start_watcher_process(expanded, {pids, dirs})
    else
      Logger.warning("Directory #{expanded} does not exist, skipping")
      {pids, dirs}
    end
  end

  defp start_watcher_process(expanded, {pids, dirs}) do
    case FileSystem.start_link(dirs: [expanded]) do
      {:ok, pid} ->
        FileSystem.subscribe(pid)
        {Map.put(pids, expanded, pid), [expanded | dirs]}

      :ignore ->
        Logger.warning(
          "FileSystem backend not available for #{expanded}. " <>
            "Install inotify-tools (Linux) or ensure fswatch is available (macOS)."
        )

        {pids, dirs}

      {:error, reason} ->
        Logger.error("Failed to start file watcher for #{expanded}: #{inspect(reason)}")
        {pids, dirs}
    end
  end

  defp debounced?(path, now, state) do
    case Map.get(state.last_event_at, path) do
      nil -> false
      last_at -> now - last_at < state.debounce_seconds
    end
  end

  @spec ignored_path?(String.t(), [String.t()]) :: boolean()
  defp ignored_path?(_path, []), do: false

  defp ignored_path?(path, patterns) do
    filename = Path.basename(path)
    Enum.any?(patterns, &match_glob?(filename, &1))
  end

  @spec match_glob?(String.t(), String.t()) :: boolean()
  defp match_glob?(filename, pattern) do
    regex = glob_to_regex(pattern)
    Regex.match?(regex, filename)
  end

  @spec glob_to_regex(String.t()) :: Regex.t()
  defp glob_to_regex(pattern) do
    pattern
    |> Regex.escape()
    |> String.replace("\\*", ".*")
    |> String.replace("\\?", ".")
    |> then(&Regex.compile!("^#{&1}$"))
  end

  defp build_event(path, events, repo, now) do
    %Event{
      timestamp: now,
      repo: repo,
      hashed_path: hash_path(path),
      event_type: map_event_type(events)
    }
  end

  defp save_event(event, path, state) do
    case Storage.save_event(event, state.data_dir) do
      :ok ->
        if state.verbose, do: print_event(event, path)

      {:error, reason} ->
        Logger.warning("Failed to save event: #{inspect(reason)}")
    end
  end

  defp find_repo(path, dir_repo_map) do
    # Find the most specific (longest) matching directory
    dir_repo_map
    |> Enum.filter(fn {dir, _repo} -> String.starts_with?(path, dir <> "/") end)
    |> Enum.max_by(fn {dir, _repo} -> String.length(dir) end, fn -> nil end)
    |> case do
      {_dir, repo} -> repo
      nil -> nil
    end
  end

  defp hash_path(path) do
    :crypto.hash(:sha256, path) |> Base.encode16(case: :lower)
  end

  @spec print_event(Event.t(), String.t()) :: :ok
  defp print_event(event, path) do
    time = event.timestamp |> DateTime.from_unix!() |> Calendar.strftime("%H:%M:%S")
    IO.puts("[#{time}] #{event.event_type} #{event.repo}: #{Path.basename(path)}")
  end

  defp would_cause_loop?(watch_dir, data_dir) do
    # Check if watch_dir is the data_dir, contains it, or is inside it
    # Use path segments to avoid false positives (e.g., /foo/bar vs /foo/bar_other)
    watch_parts = Path.split(watch_dir)
    data_parts = Path.split(data_dir)
    List.starts_with?(watch_parts, data_parts) or List.starts_with?(data_parts, watch_parts)
  end
end
