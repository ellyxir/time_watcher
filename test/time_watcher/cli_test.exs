defmodule TimeWatcher.CLITest do
  use ExUnit.Case, async: true

  alias TimeWatcher.CLI

  describe "parse_args/1" do
    test "parses 'report' with date" do
      assert CLI.parse_args(["report", "2026-02-25"]) == {:report, "2026-02-25"}
    end

    test "parses 'report' without date defaults to today" do
      assert CLI.parse_args(["report"]) == {:report, Date.to_string(Date.utc_today())}
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

    test "parses 'add' with directories" do
      assert CLI.parse_args(["add", "/tmp/dir1", "/tmp/dir2"]) ==
               {:add, ["/tmp/dir1", "/tmp/dir2"]}
    end

    test "add with no dirs returns help" do
      assert CLI.parse_args(["add"]) == :help
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
  end
end
