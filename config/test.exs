import Config

config :time_watcher,
  data_dir: Path.join(System.tmp_dir!(), "time_watcher_test_#{System.pid()}"),
  daemon_node_name: :tw_watcher_test@localhost

# Reduce log noise during tests
config :logger, level: :error
