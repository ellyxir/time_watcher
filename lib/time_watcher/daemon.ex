defmodule TimeWatcher.Daemon do
  @moduledoc """
  Daemon lifecycle management for the time_watcher distributed node.

  Note: In release mode, the daemon is started by Application.start/2 when
  the release is started via `tw watch`. This module provides helper functions
  for checking daemon status and for use in non-release (mix) environments.
  """

  alias TimeWatcher.{Node, Storage, Watcher}

  @doc """
  Starts the watcher as a distributed daemon node.
  Used in non-release (mix) environments.
  """
  @spec start_daemon(keyword()) :: :ok | {:error, term()}
  def start_daemon(opts) do
    dirs = Keyword.get(opts, :dirs, ["."])
    data_dir = Keyword.get(opts, :data_dir, Storage.data_dir())
    verbose = Keyword.get(opts, :verbose, false)

    with :ok <- check_not_already_running(),
         :ok <- start_distribution() do
      File.mkdir_p!(data_dir)

      {:ok, _pid} =
        Watcher.start_link(
          dirs: dirs,
          data_dir: data_dir,
          verbose: verbose,
          name: Watcher
        )

      IO.puts("Daemon started, watching: #{Enum.join(dirs, ", ")}")

      # Keep the process alive
      Process.sleep(:infinity)
    end
  end

  @doc """
  Checks if a daemon is already running at the expected node name.
  Returns :ok if no daemon is running, {:error, :already_running} otherwise.
  """
  @spec check_not_already_running() :: :ok | {:error, :already_running}
  def check_not_already_running do
    daemon_node = Node.daemon_node_name()

    # Try to ping the daemon node - if it responds, one is already running
    # We need to be distributed first to ping, so we try a temporary connection
    case start_temporary_distribution() do
      :ok ->
        result =
          case Elixir.Node.ping(daemon_node) do
            :pong -> {:error, :already_running}
            :pang -> :ok
          end

        # Stop the temporary node
        Elixir.Node.stop()
        result

      {:error, _} ->
        # Can't start distribution, assume no daemon is running
        :ok
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
        {:error, {:distribution_failed, reason}}
    end
  end

  defp start_temporary_distribution do
    if Elixir.Node.alive?() do
      :ok
    else
      cookie = Node.ensure_cookie()
      temp_node = Node.client_node_name()

      case Elixir.Node.start(temp_node, :shortnames) do
        {:ok, _pid} ->
          Elixir.Node.set_cookie(cookie)
          :ok

        {:error, reason} ->
          {:error, {:distribution_failed, reason}}
      end
    end
  end
end
