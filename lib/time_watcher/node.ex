defmodule TimeWatcher.Node do
  @moduledoc """
  Pure functions for node naming and cookie management for distributed IPC.
  """

  @doc """
  Returns the deterministic daemon node name.
  """
  @spec daemon_node_name() :: atom()
  def daemon_node_name do
    :tw_watcher@localhost
  end

  @doc """
  Returns a unique client node name for ephemeral connections.
  """
  @spec client_node_name() :: atom()
  def client_node_name do
    unique_id = System.unique_integer([:positive])
    :"tw_client_#{unique_id}@localhost"
  end

  @doc """
  Returns the path to the cookie file.
  """
  @spec cookie_path() :: String.t()
  def cookie_path do
    home = System.user_home() || "/tmp"
    data_dir = System.get_env("XDG_DATA_HOME", Path.join(home, ".local/share"))
    Path.join([data_dir, "time_watcher", ".erlang.cookie"])
  end

  @doc """
  Generates a cryptographically secure cookie value.
  """
  @spec generate_cookie_value() :: String.t()
  def generate_cookie_value do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  @doc """
  Ensures a cookie exists at the given path, creating one if necessary.
  Returns the cookie as an atom.
  """
  @spec ensure_cookie(String.t()) :: atom()
  def ensure_cookie(path \\ cookie_path()) do
    case File.read(path) do
      {:ok, content} ->
        content |> String.trim() |> String.to_atom()

      {:error, :enoent} ->
        cookie_value = generate_cookie_value()
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, cookie_value)
        File.chmod!(path, 0o600)
        String.to_atom(cookie_value)
    end
  end
end
