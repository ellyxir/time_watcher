defmodule TimeWatcher.Application do
  @moduledoc false
  use Application

  alias TimeWatcher.{Node, StartupMessage, Storage, Watcher}

  @impl true
  def start(_type, _args) do
    if daemon_mode?() do
      start_daemon()
    else
      Supervisor.start_link([], strategy: :one_for_one, name: TimeWatcher.Supervisor)
    end
  end

  defp start_daemon do
    case start_distribution() do
      :ok -> start_watcher_supervisor()
      {:error, _reason} -> daemon_already_running_error()
    end
  end

  defp start_watcher_supervisor do
    {dirs, verbose, dirs_from_config} = parse_watch_args()
    data_dir = Storage.data_dir()
    File.mkdir_p!(data_dir)

    if verbose do
      IO.puts(StartupMessage.build(dirs, dirs_from_config: dirs_from_config))
    end

    children = [{Watcher, dirs: dirs, data_dir: data_dir, verbose: verbose, name: Watcher}]
    Supervisor.start_link(children, strategy: :one_for_one, name: TimeWatcher.Supervisor)
  end

  @spec daemon_already_running_error() :: no_return()
  defp daemon_already_running_error do
    IO.puts("Error: Another daemon is already running.")
    IO.puts("Use 'tw watch <dir>' to add directories to the running daemon.")
    System.halt(1)
  end

  defp daemon_mode? do
    # When started via 'start' command, TW_ARGV contains "watch" as first arg
    case System.get_env("TW_ARGV", "") |> String.split("\n", trim: true) do
      ["watch" | _] -> true
      _ -> false
    end
  end

  @spec parse_watch_args() :: {[String.t()], boolean(), boolean()}
  defp parse_watch_args do
    args = System.get_env("TW_ARGV", "") |> String.split("\n", trim: true)

    case args do
      ["watch" | rest] ->
        {dirs, verbose, has_verbose_flag} =
          Enum.reduce(rest, {[], false, false}, fn
            "-v", {dirs, _, _} -> {dirs, true, true}
            "--verbose", {dirs, _, _} -> {dirs, true, true}
            dir, {dirs, verbose, has_flag} -> {dirs ++ [dir], verbose, has_flag}
          end)

        # Apply config verbose if no CLI flag was given
        verbose =
          if has_verbose_flag do
            verbose
          else
            Application.get_env(:time_watcher, :verbose, false)
          end

        {dirs, dirs_from_config} =
          if dirs == [] do
            {default_dirs(), true}
          else
            {dirs, false}
          end

        {dirs, verbose, dirs_from_config}

      _ ->
        {default_dirs(), Application.get_env(:time_watcher, :verbose, false), true}
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
