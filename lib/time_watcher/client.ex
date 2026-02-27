defmodule TimeWatcher.Client do
  @moduledoc """
  Client-side operations for communicating with the time_watcher daemon.
  """

  alias TimeWatcher.{Node, Watcher}

  @doc """
  Adds a directory to the running watcher daemon.
  """
  @spec add_directory(String.t()) ::
          :ok
          | {:error, :already_watching | :would_cause_loop | :daemon_not_running | :distribution_failed}
  def add_directory(dir) do
    expanded = expand_path(dir)
    with_daemon(fn -> Watcher.add_dir({Watcher, Node.daemon_node_name()}, expanded) end)
  end

  @doc """
  Lists all directories being watched by the daemon.
  """
  @spec list_directories() ::
          [%{path: String.t(), repo: String.t()}]
          | {:error, :daemon_not_running | :distribution_failed}
  def list_directories do
    with_daemon(fn -> Watcher.list_dirs({Watcher, Node.daemon_node_name()}) end)
  end

  @doc """
  Removes a directory from the running watcher daemon.
  """
  @spec remove_directory(String.t()) :: :ok | {:error, :not_watching | :daemon_not_running | :distribution_failed}
  def remove_directory(dir) do
    expanded = expand_path(dir)
    with_daemon(fn -> Watcher.remove_dir({Watcher, Node.daemon_node_name()}, expanded) end)
  end

  @doc """
  Expands a path to an absolute path, resolving ~, ., and relative paths.
  Must be called on the client side before sending to daemon.
  """
  @spec expand_path(String.t()) :: String.t()
  def expand_path(path) do
    Path.expand(path)
  end

  @doc """
  Ensures the client node is started and connected to the daemon.
  Returns :ok if connected, {:error, :daemon_not_running} otherwise.
  """
  @spec ensure_connected() :: :ok | {:error, :daemon_not_running}
  def ensure_connected do
    start_distribution()

    daemon_node = Node.daemon_node_name()

    case Elixir.Node.connect(daemon_node) do
      true -> :ok
      false -> {:error, :daemon_not_running}
      :ignored -> {:error, :daemon_not_running}
    end
  end

  defp start_distribution do
    if Elixir.Node.alive?() do
      :ok
    else
      cookie = Node.ensure_cookie()
      node_name = Node.client_node_name()

      case Elixir.Node.start(node_name, :shortnames) do
        {:ok, _pid} ->
          Elixir.Node.set_cookie(cookie)
          :ok

        {:error, _reason} ->
          {:error, :distribution_failed}
      end
    end
  end

  defp with_daemon(fun) do
    case start_distribution() do
      :ok ->
        case ensure_connected() do
          :ok -> fun.()
          error -> error
        end

      error ->
        error
    end
  end
end
