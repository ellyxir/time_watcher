import Config

# Compile-time config - data_dir is set at runtime in config/runtime.exs
import_config "#{config_env()}.exs"
