defmodule TimeWatcher.CLITest do
  use ExUnit.Case, async: true

  alias TimeWatcher.CLI

  describe "parse_args/1" do
    test "parses 'report' with date" do
      assert CLI.parse_args(["report", "2026-02-25"]) == {:report, "2026-02-25", []}
    end

    test "parses 'report' without date defaults to today" do
      assert CLI.parse_args(["report"]) == {:report, Date.to_string(Date.utc_today()), []}
    end

    test "parses 'report' with --cooldown option" do
      assert CLI.parse_args(["report", "--cooldown", "15"]) ==
               {:report, Date.to_string(Date.utc_today()), [cooldown: 15]}
    end

    test "parses 'report' with date and --cooldown option" do
      assert CLI.parse_args(["report", "2026-02-25", "--cooldown", "20"]) ==
               {:report, "2026-02-25", [cooldown: 20]}
    end

    test "parses 'report' with --cooldown before date" do
      assert CLI.parse_args(["report", "--cooldown", "10", "2026-02-25"]) ==
               {:report, "2026-02-25", [cooldown: 10]}
    end

    test "parses 'report' with --md flag" do
      assert CLI.parse_args(["report", "--md"]) ==
               {:report, Date.to_string(Date.utc_today()), [md: true]}
    end

    test "parses 'report' with date and --md flag" do
      assert CLI.parse_args(["report", "2026-02-25", "--md"]) ==
               {:report, "2026-02-25", [md: true]}
    end

    test "parses 'report' with --md and --cooldown flags" do
      assert CLI.parse_args(["report", "2026-02-25", "--md", "--cooldown", "15"]) ==
               {:report, "2026-02-25", [cooldown: 15, md: true]}
    end

    test "parses 'report' with --md before date" do
      assert CLI.parse_args(["report", "--md", "2026-02-25"]) ==
               {:report, "2026-02-25", [md: true]}
    end

    test "parses 'report' with --days flag" do
      assert CLI.parse_args(["report", "--days", "7"]) ==
               {:report, :multi_day, [days: 7]}
    end

    test "parses 'report' with --days and --md flags" do
      assert CLI.parse_args(["report", "--days", "7", "--md"]) ==
               {:report, :multi_day, [md: true, days: 7]}
    end

    test "parses 'report' with --days and --cooldown flags" do
      assert CLI.parse_args(["report", "--days", "7", "--cooldown", "10"]) ==
               {:report, :multi_day, [cooldown: 10, days: 7]}
    end

    test "parses 'report' with --days, --md, and --cooldown flags" do
      assert CLI.parse_args(["report", "--days", "5", "--md", "--cooldown", "15"]) ==
               {:report, :multi_day, [cooldown: 15, md: true, days: 5]}
    end

    test "report --days with date argument returns error" do
      assert CLI.parse_args(["report", "--days", "7", "2026-02-25"]) ==
               {:error, "--days cannot be combined with a date argument"}
    end

    test "report --days 0 returns error" do
      assert CLI.parse_args(["report", "--days", "0"]) ==
               {:error, "--days must be a positive integer"}
    end

    test "report --days negative returns error" do
      assert CLI.parse_args(["report", "--days", "-1"]) ==
               {:error, "--days must be a positive integer"}
    end

    test "parses 'report' with --from and --to flags" do
      assert {:report, :date_range, opts} =
               CLI.parse_args(["report", "--from", "2026-02-20", "--to", "2026-02-27"])

      assert Keyword.get(opts, :from) == "2026-02-20"
      assert Keyword.get(opts, :to) == "2026-02-27"
    end

    test "parses 'report' with --from, --to, and --md flags" do
      assert {:report, :date_range, opts} =
               CLI.parse_args(["report", "--from", "2026-02-20", "--to", "2026-02-27", "--md"])

      assert Keyword.get(opts, :from) == "2026-02-20"
      assert Keyword.get(opts, :to) == "2026-02-27"
      assert Keyword.get(opts, :md) == true
    end

    test "parses 'report' with --from, --to, and --cooldown flags" do
      assert {:report, :date_range, opts} =
               CLI.parse_args([
                 "report",
                 "--from",
                 "2026-02-20",
                 "--to",
                 "2026-02-27",
                 "--cooldown",
                 "10"
               ])

      assert Keyword.get(opts, :from) == "2026-02-20"
      assert Keyword.get(opts, :to) == "2026-02-27"
      assert Keyword.get(opts, :cooldown) == 10
    end

    test "parses 'report' with --from, --to, --md, and --cooldown flags" do
      assert {:report, :date_range, opts} =
               CLI.parse_args([
                 "report",
                 "--from",
                 "2026-02-20",
                 "--to",
                 "2026-02-27",
                 "--md",
                 "--cooldown",
                 "15"
               ])

      assert Keyword.get(opts, :from) == "2026-02-20"
      assert Keyword.get(opts, :to) == "2026-02-27"
      assert Keyword.get(opts, :md) == true
      assert Keyword.get(opts, :cooldown) == 15
    end

    test "report --from without --to returns error" do
      assert CLI.parse_args(["report", "--from", "2026-02-20"]) ==
               {:error, "--from requires --to (and vice versa)"}
    end

    test "report --to without --from returns error" do
      assert CLI.parse_args(["report", "--to", "2026-02-27"]) ==
               {:error, "--from requires --to (and vice versa)"}
    end

    test "report --from date after --to date returns error" do
      assert CLI.parse_args(["report", "--from", "2026-02-27", "--to", "2026-02-20"]) ==
               {:error, "--from date must be before or equal to --to date"}
    end

    test "report --from equals --to is valid (single day)" do
      assert {:report, :date_range, opts} =
               CLI.parse_args(["report", "--from", "2026-02-25", "--to", "2026-02-25"])

      assert Keyword.get(opts, :from) == "2026-02-25"
      assert Keyword.get(opts, :to) == "2026-02-25"
    end

    test "report --from/--to with --days returns error" do
      assert CLI.parse_args([
               "report",
               "--from",
               "2026-02-20",
               "--to",
               "2026-02-27",
               "--days",
               "7"
             ]) ==
               {:error, "--from/--to cannot be combined with --days"}
    end

    test "report --from/--to with date argument returns error" do
      assert CLI.parse_args([
               "report",
               "--from",
               "2026-02-20",
               "--to",
               "2026-02-27",
               "2026-02-25"
             ]) ==
               {:error, "--from/--to cannot be combined with a date argument"}
    end

    test "parses 'watch' with directories" do
      assert CLI.parse_args(["watch", "/tmp/dir1", "/tmp/dir2"]) ==
               {:watch, ["/tmp/dir1", "/tmp/dir2"], []}
    end

    test "watch with no dirs defaults to current directory" do
      assert CLI.parse_args(["watch"]) == {:watch, ["."], []}
    end

    test "watch with -v flag enables verbose" do
      assert CLI.parse_args(["watch", "-v"]) == {:watch, ["."], [:verbose]}
    end

    test "watch with --verbose flag enables verbose" do
      assert CLI.parse_args(["watch", "--verbose"]) == {:watch, ["."], [:verbose]}
    end

    test "watch with dirs and -v flag" do
      assert CLI.parse_args(["watch", "-v", "/tmp/dir1"]) == {:watch, ["/tmp/dir1"], [:verbose]}
      assert CLI.parse_args(["watch", "/tmp/dir1", "-v"]) == {:watch, ["/tmp/dir1"], [:verbose]}
    end

    test "parses 'stop'" do
      assert CLI.parse_args(["stop"]) == :stop
    end

    test "parses 'list'" do
      assert CLI.parse_args(["list"]) == :list
    end

    test "parses 'remove' with directories" do
      assert CLI.parse_args(["remove", "/tmp/dir1", "/tmp/dir2"]) ==
               {:remove, ["/tmp/dir1", "/tmp/dir2"]}
    end

    test "remove with no dirs returns help" do
      assert CLI.parse_args(["remove"]) == :help
    end

    test "unknown command returns help" do
      assert CLI.parse_args(["unknown"]) == :help
    end

    test "empty args returns help" do
      assert CLI.parse_args([]) == :help
    end

    test "parses 'commit'" do
      assert CLI.parse_args(["commit"]) == :commit
    end

    test "parses 'commit' with custom message" do
      assert CLI.parse_args(["commit", "-m", "my message"]) == {:commit, "my message"}
    end

    test "parses 'commit' with --message flag" do
      assert CLI.parse_args(["commit", "--message", "my message"]) == {:commit, "my message"}
    end

    test "commit with -m but no message returns help" do
      assert CLI.parse_args(["commit", "-m"]) == :help
    end

    test "parses 'reset' defaults to today" do
      assert CLI.parse_args(["reset"]) == {:reset, Date.to_string(Date.utc_today())}
    end

    test "parses 'reset' with specific date" do
      assert CLI.parse_args(["reset", "2026-02-25"]) == {:reset, "2026-02-25"}
    end

    test "parses 'reset --all'" do
      assert CLI.parse_args(["reset", "--all"]) == {:reset, :all}
    end
  end
end
