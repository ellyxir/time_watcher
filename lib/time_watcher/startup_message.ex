defmodule TimeWatcher.StartupMessage do
  @moduledoc """
  Formats the daemon startup message showing watched directories and config info.
  """

  @doc """
  Returns the config file path if it exists, nil otherwise.
  """
  @spec config_path() :: String.t() | nil
  def config_path do
    path = config_path_location()
    if File.exists?(path), do: path, else: nil
  end

  @doc """
  Returns the expected config file path location (regardless of whether it exists).
  """
  @spec config_path_location() :: String.t()
  def config_path_location do
    config_home = System.get_env("XDG_CONFIG_HOME", Path.join(System.user_home!(), ".config"))
    Path.join([config_home, "time_watcher", "config.exs"])
  end

  @doc """
  Prints the startup message, parsing dirs from TW_ARGV environment variable.
  Used by the shell script for background daemon mode.
  """
  @spec print_startup() :: :ok
  def print_startup do
    {dirs, dirs_from_config} = parse_watch_args_from_env()
    IO.puts(build(dirs, dirs_from_config: dirs_from_config))
  end

  @doc """
  Builds the startup message, determining config path automatically.

  ## Options
    * `:dirs_from_config` - Whether dirs came from the config file (default: false)
  """
  @spec build([String.t()], keyword()) :: String.t()
  def build(dirs, opts \\ []) do
    dirs_from_config = Keyword.get(opts, :dirs_from_config, false)

    config_path =
      if dirs_from_config do
        config_path()
      else
        nil
      end

    format(dirs, config_path: config_path)
  end

  @spec parse_watch_args_from_env() :: {[String.t()], boolean()}
  defp parse_watch_args_from_env do
    args = System.get_env("TW_ARGV", "") |> String.split("\n", trim: true)

    case args do
      ["watch" | rest] ->
        dirs =
          rest
          |> Enum.reject(&(&1 in ["-v", "--verbose"]))

        if dirs == [] do
          {default_dirs(), true}
        else
          {dirs, false}
        end

      _ ->
        {default_dirs(), true}
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

  @doc """
  Formats the startup message.

  ## Options
    * `:config_path` - The config file path if dirs came from config, nil otherwise
  """
  @spec format([String.t()], keyword()) :: String.t()
  def format(dirs, opts \\ []) do
    config_path = Keyword.get(opts, :config_path)
    repos = Enum.map_join(dirs, ", ", &extract_repo_name/1)

    if config_path do
      "Daemon started (config: #{display_path(config_path)}), watching: #{repos}"
    else
      "Daemon started, watching: #{repos}"
    end
  end

  @spec extract_repo_name(String.t()) :: String.t()
  defp extract_repo_name("."), do: "."

  defp extract_repo_name(path) do
    Path.basename(path)
  end

  @spec display_path(String.t()) :: String.t()
  defp display_path(path) do
    home = System.user_home!()

    if String.starts_with?(path, home) do
      "~" <> String.trim_leading(path, home)
    else
      path
    end
  end
end
