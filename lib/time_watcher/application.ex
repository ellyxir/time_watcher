defmodule TimeWatcher.Application do
  @moduledoc false
  use Application

  alias TimeWatcher.{Node, Storage, Watcher}

  @impl true
  def start(_type, _args) do
    if daemon_mode?() do
      case start_distribution() do
        :ok ->
          {dirs, verbose} = parse_watch_args()
          data_dir = Storage.data_dir()
          File.mkdir_p!(data_dir)

          children = [{Watcher, dirs: dirs, data_dir: data_dir, verbose: verbose, name: Watcher}]
          opts = [strategy: :one_for_one, name: TimeWatcher.Supervisor]
          Supervisor.start_link(children, opts)

        {:error, _reason} ->
          IO.puts("Error: Another daemon is already running.")
          IO.puts("Use 'tw watch <dir>' to add directories to the running daemon.")
          System.halt(1)
      end
    else
      opts = [strategy: :one_for_one, name: TimeWatcher.Supervisor]
      Supervisor.start_link([], opts)
    end
  end

  defp daemon_mode? do
    # When started via 'start' command, TW_ARGV contains "watch" as first arg
    case System.get_env("TW_ARGV", "") |> String.split("\n", trim: true) do
      ["watch" | _] -> true
      _ -> false
    end
  end

  @spec parse_watch_args() :: {[String.t()], boolean()}
  defp parse_watch_args do
    args = System.get_env("TW_ARGV", "") |> String.split("\n", trim: true)

    case args do
      ["watch" | rest] ->
        {dirs, verbose} =
          Enum.reduce(rest, {[], false}, fn
            "-v", {dirs, _} -> {dirs, true}
            "--verbose", {dirs, _} -> {dirs, true}
            dir, {dirs, verbose} -> {dirs ++ [dir], verbose}
          end)

        dirs = if dirs == [], do: default_dirs(), else: dirs
        {dirs, verbose}

      _ ->
        {default_dirs(), false}
    end
  end

  @spec default_dirs() :: [String.t()]
  defp default_dirs do
    case Application.get_env(:time_watcher, :dirs) do
      nil -> ["."]
      [] -> ["."]
      dirs when is_list(dirs) -> dirs
    end
  end

  defp start_distribution do
    cookie = Node.ensure_cookie()
    daemon_node = Node.daemon_node_name()

    case Elixir.Node.start(daemon_node, :shortnames) do
      {:ok, _pid} ->
        Elixir.Node.set_cookie(cookie)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
