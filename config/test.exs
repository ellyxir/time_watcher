import Config

config :time_watcher,
  data_dir: Path.join(System.tmp_dir!(), "time_watcher_test_#{System.pid()}")
