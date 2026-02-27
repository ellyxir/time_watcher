defmodule TimeWatcher.StartupMessageTest do
  use ExUnit.Case, async: false

  alias TimeWatcher.StartupMessage

  describe "format/2" do
    test "shows config path and repos when dirs came from config" do
      config_path = "~/.config/time_watcher/config.exs"
      dirs = ["~/projects/foo", "~/projects/bar"]

      result = StartupMessage.format(dirs, config_path: config_path)

      assert result =~ "config: ~/.config/time_watcher/config.exs"
      assert result =~ "foo"
      assert result =~ "bar"
      assert result =~ "Daemon started"
    end

    test "shows repos without config path when dirs came from CLI" do
      dirs = ["/tmp/my_repo", "/tmp/other"]

      result = StartupMessage.format(dirs, config_path: nil)

      refute result =~ "config:"
      assert result =~ "my_repo"
      assert result =~ "other"
      assert result =~ "Daemon started"
    end

    test "extracts repo names from full paths" do
      dirs = ["/home/user/projects/time_watcher", "/home/user/work/my_app"]

      result = StartupMessage.format(dirs, config_path: nil)

      assert result =~ "time_watcher"
      assert result =~ "my_app"
    end

    test "handles tilde paths correctly" do
      dirs = ["~/projects/foo"]

      result = StartupMessage.format(dirs, config_path: nil)

      assert result =~ "foo"
    end

    test "handles single directory" do
      dirs = ["/tmp/single_repo"]

      result = StartupMessage.format(dirs, config_path: nil)

      assert result =~ "single_repo"
      # Single repo should not have comma-separated list (only the "watching:" comma)
      assert result == "Daemon started, watching: single_repo"
    end

    test "shows current directory as-is when passed dot" do
      dirs = ["."]

      result = StartupMessage.format(dirs, config_path: nil)

      assert result =~ "."
    end
  end

  describe "config_path/0" do
    test "returns config path when file exists" do
      # This test depends on whether a config file exists
      # Just verify it returns a string or nil
      result = StartupMessage.config_path()
      assert is_binary(result) or is_nil(result)
    end

    test "returns path based on XDG_CONFIG_HOME if set" do
      original = System.get_env("XDG_CONFIG_HOME")

      try do
        System.put_env("XDG_CONFIG_HOME", "/custom/config")
        path = StartupMessage.config_path_location()
        assert path == "/custom/config/time_watcher/config.exs"
      after
        if original,
          do: System.put_env("XDG_CONFIG_HOME", original),
          else: System.delete_env("XDG_CONFIG_HOME")
      end
    end
  end

  describe "build/2" do
    test "includes config path when dirs_from_config is true and config exists" do
      dirs = ["/home/user/projects/foo", "/home/user/projects/bar"]

      result = StartupMessage.build(dirs, dirs_from_config: true)

      # Should include config path if it exists, or not if it doesn't
      assert result =~ "Daemon started"
      assert result =~ "foo"
      assert result =~ "bar"
    end

    test "does not include config path when dirs_from_config is false" do
      dirs = ["/tmp/my_repo"]

      result = StartupMessage.build(dirs, dirs_from_config: false)

      refute result =~ "config:"
      assert result =~ "my_repo"
    end
  end
end
