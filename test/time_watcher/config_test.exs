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
      {:watch, dirs, opts} = CLI.parse_args(["watch"])
      assert dirs == ["~/projects/foo", "~/projects/bar"]
      assert Keyword.get(opts, :dirs_from_config) == true
    end

    test "watch with explicit dirs ignores config" do
      Application.put_env(:time_watcher, :dirs, ["~/projects/foo", "~/projects/bar"])
      {:watch, dirs, opts} = CLI.parse_args(["watch", "/tmp/explicit"])
      assert dirs == ["/tmp/explicit"]
      refute Keyword.get(opts, :dirs_from_config)
    end

    test "watch with no dirs and no config falls back to current directory" do
      Application.delete_env(:time_watcher, :dirs)
      {:watch, dirs, opts} = CLI.parse_args(["watch"])
      assert dirs == ["."]
      assert Keyword.get(opts, :dirs_from_config) == true
    end

    test "watch with no dirs and empty config falls back to current directory" do
      Application.put_env(:time_watcher, :dirs, [])
      {:watch, dirs, opts} = CLI.parse_args(["watch"])
      assert dirs == ["."]
      assert Keyword.get(opts, :dirs_from_config) == true
    end

    test "watch with verbose flag and config dirs" do
      Application.put_env(:time_watcher, :dirs, ["~/projects/foo"])
      {:watch, dirs, opts} = CLI.parse_args(["watch", "-v"])
      assert dirs == ["~/projects/foo"]
      assert Keyword.get(opts, :verbose) == true
      assert Keyword.get(opts, :dirs_from_config) == true
    end
  end

  describe "parse_args/1 with config verbose" do
    setup do
      original_verbose = Application.get_env(:time_watcher, :verbose)
      original_dirs = Application.get_env(:time_watcher, :dirs)

      on_exit(fn ->
        Application.put_env(:time_watcher, :verbose, original_verbose)
        Application.put_env(:time_watcher, :dirs, original_dirs)
      end)

      :ok
    end

    test "watch uses verbose from config when no -v flag" do
      Application.put_env(:time_watcher, :verbose, true)
      Application.delete_env(:time_watcher, :dirs)
      {:watch, dirs, opts} = CLI.parse_args(["watch"])
      assert dirs == ["."]
      assert Keyword.get(opts, :verbose) == true
    end

    test "watch without -v and config verbose: false has no verbose" do
      Application.put_env(:time_watcher, :verbose, false)
      Application.delete_env(:time_watcher, :dirs)
      {:watch, dirs, opts} = CLI.parse_args(["watch"])
      assert dirs == ["."]
      assert Keyword.get(opts, :verbose) == false
    end

    test "watch -v flag overrides config verbose: false" do
      Application.put_env(:time_watcher, :verbose, false)
      Application.delete_env(:time_watcher, :dirs)
      {:watch, dirs, opts} = CLI.parse_args(["watch", "-v"])
      assert dirs == ["."]
      assert Keyword.get(opts, :verbose) == true
    end

    test "watch -v flag with config verbose: true still verbose" do
      Application.put_env(:time_watcher, :verbose, true)
      Application.delete_env(:time_watcher, :dirs)
      {:watch, dirs, opts} = CLI.parse_args(["watch", "-v"])
      assert dirs == ["."]
      assert Keyword.get(opts, :verbose) == true
    end

    test "watch with no verbose config defaults to not verbose" do
      Application.delete_env(:time_watcher, :verbose)
      Application.delete_env(:time_watcher, :dirs)
      {:watch, dirs, opts} = CLI.parse_args(["watch"])
      assert dirs == ["."]
      assert Keyword.get(opts, :verbose) == false
    end
  end

  describe "parse_args/1 with config ignore_patterns" do
    setup do
      original_patterns = Application.get_env(:time_watcher, :ignore_patterns)
      original_dirs = Application.get_env(:time_watcher, :dirs)

      on_exit(fn ->
        if original_patterns do
          Application.put_env(:time_watcher, :ignore_patterns, original_patterns)
        else
          Application.delete_env(:time_watcher, :ignore_patterns)
        end

        Application.put_env(:time_watcher, :dirs, original_dirs)
      end)

      :ok
    end

    test "watch uses ignore_patterns from config" do
      Application.put_env(:time_watcher, :ignore_patterns, [".watchman-cookie-*", "*.swp"])
      Application.delete_env(:time_watcher, :dirs)
      {:watch, _dirs, opts} = CLI.parse_args(["watch"])
      assert Keyword.get(opts, :ignore_patterns) == [".watchman-cookie-*", "*.swp"]
    end

    test "watch with no ignore_patterns config has empty list" do
      Application.delete_env(:time_watcher, :ignore_patterns)
      Application.delete_env(:time_watcher, :dirs)
      {:watch, _dirs, opts} = CLI.parse_args(["watch"])
      assert Keyword.get(opts, :ignore_patterns) == []
    end

    test "watch with empty ignore_patterns config has empty list" do
      Application.put_env(:time_watcher, :ignore_patterns, [])
      Application.delete_env(:time_watcher, :dirs)
      {:watch, _dirs, opts} = CLI.parse_args(["watch"])
      assert Keyword.get(opts, :ignore_patterns) == []
    end
  end

  describe "parse_args/1 with config cooldown" do
    setup do
      original_cooldown = Application.get_env(:time_watcher, :cooldown)

      on_exit(fn ->
        Application.put_env(:time_watcher, :cooldown, original_cooldown)
      end)

      :ok
    end

    test "report uses cooldown from config when no --cooldown flag" do
      Application.put_env(:time_watcher, :cooldown, 10)

      assert CLI.parse_args(["report"]) ==
               {:report, Date.to_string(Date.utc_today()), [cooldown: 10]}
    end

    test "report with date uses cooldown from config" do
      Application.put_env(:time_watcher, :cooldown, 15)
      assert CLI.parse_args(["report", "2026-02-25"]) == {:report, "2026-02-25", [cooldown: 15]}
    end

    test "report --cooldown flag overrides config cooldown" do
      Application.put_env(:time_watcher, :cooldown, 10)

      assert CLI.parse_args(["report", "--cooldown", "20"]) ==
               {:report, Date.to_string(Date.utc_today()), [cooldown: 20]}
    end

    test "report with no cooldown config has no cooldown opt" do
      Application.delete_env(:time_watcher, :cooldown)
      assert CLI.parse_args(["report"]) == {:report, Date.to_string(Date.utc_today()), []}
    end

    test "report --days uses cooldown from config" do
      Application.put_env(:time_watcher, :cooldown, 10)

      assert CLI.parse_args(["report", "--days", "7"]) ==
               {:report, :multi_day, [cooldown: 10, days: 7]}
    end

    test "report --from/--to uses cooldown from config" do
      Application.put_env(:time_watcher, :cooldown, 10)

      assert {:report, :date_range, opts} =
               CLI.parse_args(["report", "--from", "2026-02-20", "--to", "2026-02-27"])

      assert Keyword.get(opts, :cooldown) == 10
    end
  end
end
