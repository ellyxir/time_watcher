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
      :modified in types -> :modified
      true -> :modified
    end
  end

  @spec add_dir(GenServer.server(), String.t()) :: :ok | {:error, :already_watching | :would_cause_loop}
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

  # Server callbacks

  @impl true
  def init(opts) do
    dirs = Keyword.fetch!(opts, :dirs)
    data_dir = Keyword.get(opts, :data_dir, Storage.data_dir())
    expanded_data_dir = Path.expand(data_dir)
    debounce_seconds = Keyword.get(opts, :debounce_seconds, @default_debounce_seconds)

    # Filter out directories that would cause infinite loops
    safe_dirs =
      dirs
      |> Enum.map(&Path.expand/1)
      |> Enum.reject(&would_cause_loop?(&1, expanded_data_dir))

    if length(safe_dirs) < length(dirs) do
      Logger.warning("Some directories were excluded to prevent infinite loops with data directory")
    end

    dir_repo_map =
      Map.new(safe_dirs, fn expanded ->
        {expanded, detect_repo(expanded)}
      end)

    watcher_pids =
      Map.new(safe_dirs, fn expanded ->
        {:ok, pid} = FileSystem.start_link(dirs: [expanded])
        FileSystem.subscribe(pid)
        {expanded, pid}
      end)

    {:ok,
     %{
       dir_repo_map: dir_repo_map,
       data_dir: data_dir,
       debounce_seconds: debounce_seconds,
       last_event_at: %{},
       watcher_pids: watcher_pids
     }}
  end

  @impl true
  def handle_call({:add_dir, dir}, _from, state) do
    expanded = Path.expand(dir)
    data_dir = Path.expand(state.data_dir)

    cond do
      would_cause_loop?(expanded, data_dir) ->
        {:reply, {:error, :would_cause_loop}, state}

      Map.has_key?(state.dir_repo_map, expanded) ->
        {:reply, {:error, :already_watching}, state}

      true ->
        {:ok, pid} = FileSystem.start_link(dirs: [expanded])
        FileSystem.subscribe(pid)

        new_state = %{
          state
          | dir_repo_map: Map.put(state.dir_repo_map, expanded, detect_repo(expanded)),
            watcher_pids: Map.put(state.watcher_pids, expanded, pid)
        }

        {:reply, :ok, new_state}
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
  def handle_info({:file_event, _pid, {path, events}}, state) do
    now = System.system_time(:second)
    event_type = map_event_type(events)

    repo = find_repo(path, state.dir_repo_map)

    if repo && !debounced?(path, now, state) do
      event = %Event{
        timestamp: now,
        repo: repo,
        hashed_path: hash_path(path),
        event_type: event_type
      }

      case Storage.save_event(event, state.data_dir) do
        :ok ->
          fire_and_forget_commit(state.data_dir)

        {:error, reason} ->
          Logger.warning("Failed to save event: #{inspect(reason)}")
      end

      {:noreply, %{state | last_event_at: Map.put(state.last_event_at, path, now)}}
    else
      {:noreply, state}
    end
  end

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

  defp debounced?(path, now, state) do
    case Map.get(state.last_event_at, path) do
      nil -> false
      last_at -> now - last_at < state.debounce_seconds
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

  defp fire_and_forget_commit(data_dir) do
    Task.start(fn ->
      case Storage.git_commit("auto: event recorded", data_dir) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("git commit failed: #{inspect(reason)}")
      end
    end)
  end

  defp would_cause_loop?(watch_dir, data_dir) do
    # Check if watch_dir is the data_dir, contains it, or is inside it
    # Use path segments to avoid false positives (e.g., /foo/bar vs /foo/bar_other)
    watch_parts = Path.split(watch_dir)
    data_parts = Path.split(data_dir)
    List.starts_with?(watch_parts, data_parts) or List.starts_with?(data_parts, watch_parts)
  end
end
