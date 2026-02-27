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
