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
               {:watch, ["/tmp/dir1", "/tmp/dir2"]}
    end

    test "watch with no dirs defaults to current directory" do
      assert CLI.parse_args(["watch"]) == {:watch, ["."]}
    end

    test "unknown command returns help" do
      assert CLI.parse_args(["unknown"]) == :help
    end

    test "empty args returns help" do
      assert CLI.parse_args([]) == :help
    end
  end
end
