defmodule TimeWatcher.ConfigTest do
  use ExUnit.Case, async: false

  alias TimeWatcher.CLI

  describe "parse_args/1 with config dirs" do
    setup do
      # Save original config
      original_dirs = Application.get_env(:time_watcher, :dirs)
      on_exit(fn -> Application.put_env(:time_watcher, :dirs, original_dirs) end)
      :ok
    end

    test "watch with no dirs uses configured dirs when present" do
      Application.put_env(:time_watcher, :dirs, ["~/projects/foo", "~/projects/bar"])
      assert CLI.parse_args(["watch"]) == {:watch, ["~/projects/foo", "~/projects/bar"], []}
    end

    test "watch with explicit dirs ignores config" do
      Application.put_env(:time_watcher, :dirs, ["~/projects/foo", "~/projects/bar"])

      assert CLI.parse_args(["watch", "/tmp/explicit"]) ==
               {:watch, ["/tmp/explicit"], []}
    end

    test "watch with no dirs and no config falls back to current directory" do
      Application.delete_env(:time_watcher, :dirs)
      assert CLI.parse_args(["watch"]) == {:watch, ["."], []}
    end

    test "watch with no dirs and empty config falls back to current directory" do
      Application.put_env(:time_watcher, :dirs, [])
      assert CLI.parse_args(["watch"]) == {:watch, ["."], []}
    end

    test "watch with verbose flag and config dirs" do
      Application.put_env(:time_watcher, :dirs, ["~/projects/foo"])
      assert CLI.parse_args(["watch", "-v"]) == {:watch, ["~/projects/foo"], [:verbose]}
    end
  end
end
