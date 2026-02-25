import Config

config :time_watcher,
  data_dir: Path.expand("~/.local/share/time_watcher")

import_config "#{config_env()}.exs"
