defmodule TimeWatcher.Application do
  @moduledoc false
  use Application

  alias TimeWatcher.{Node, Storage, Watcher}

  @impl true
  def start(_type, _args) do
    if daemon_mode?() do
      case start_distribution() do
        :ok ->
          dirs = parse_watch_dirs()
          data_dir = Storage.data_dir()
          File.mkdir_p!(data_dir)

          IO.puts("Daemon started, watching: #{Enum.join(dirs, ", ")}")

          children = [{Watcher, dirs: dirs, data_dir: data_dir, name: Watcher}]
          opts = [strategy: :one_for_one, name: TimeWatcher.Supervisor]
          Supervisor.start_link(children, opts)

        {:error, _reason} ->
          IO.puts("Error: Another daemon is already running.")
          IO.puts("Use 'tw add <dir>' to add directories to the running daemon.")
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

  defp parse_watch_dirs do
    case System.get_env("TW_ARGV", "") |> String.split("\n", trim: true) do
      ["watch"] -> ["."]
      ["watch" | dirs] -> dirs
      _ -> ["."]
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
