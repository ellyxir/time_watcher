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

  # Server callbacks

  @impl true
  def init(opts) do
    dirs = Keyword.fetch!(opts, :dirs)
    data_dir = Keyword.get(opts, :data_dir, Storage.data_dir())
    debounce_seconds = Keyword.get(opts, :debounce_seconds, @default_debounce_seconds)

    dir_repo_map =
      Map.new(dirs, fn dir ->
        expanded = Path.expand(dir)
        {expanded, detect_repo(expanded)}
      end)

    watcher_pids =
      for dir <- dirs do
        {:ok, pid} = FileSystem.start_link(dirs: [dir])
        FileSystem.subscribe(pid)
        pid
      end

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

  defp debounced?(path, now, state) do
    case Map.get(state.last_event_at, path) do
      nil -> false
      last_at -> now - last_at < state.debounce_seconds
    end
  end

  defp find_repo(path, dir_repo_map) do
    Enum.find_value(dir_repo_map, fn {dir, repo} ->
      if String.starts_with?(path, dir), do: repo
    end)
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
end
