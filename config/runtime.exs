import Config

# Runtime configuration - evaluated at runtime, not compile time
config :time_watcher,
  data_dir:
    System.get_env(
      "TW_DATA_DIR",
      Path.join(
        System.get_env("XDG_DATA_HOME", Path.join(System.user_home!(), ".local/share")),
        "time_watcher"
      )
    )

# Load user config file if it exists
config_home = System.get_env("XDG_CONFIG_HOME", Path.join(System.user_home!(), ".config"))
config_path = Path.join([config_home, "time_watcher", "config.exs"])

if File.exists?(config_path) do
  user_config = Config.Reader.read!(config_path)

  case Keyword.get(user_config, :time_watcher) do
    nil -> :ok
    tw_config -> Config.config(:time_watcher, tw_config)
  end
end
