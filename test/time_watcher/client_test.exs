defmodule TimeWatcher.ClientTest do
  use ExUnit.Case, async: false

  alias TimeWatcher.Client

  describe "path expansion" do
    test "expand_path converts relative paths to absolute" do
      # Save current dir
      {:ok, cwd} = File.cwd()

      assert Client.expand_path(".") == cwd
      assert Client.expand_path("./subdir") == Path.join(cwd, "subdir")
      assert Client.expand_path("~") == System.user_home()
    end

    test "expand_path preserves absolute paths" do
      assert Client.expand_path("/tmp/foo") == "/tmp/foo"
      assert Client.expand_path("/home/user/projects") == "/home/user/projects"
    end
  end

  describe "connection error handling" do
    # In test environment without epmd, distribution fails to start
    # The important thing is that these don't crash and return an error tuple

    test "add_directory returns error when daemon not available" do
      result = Client.add_directory("/tmp/some_dir")
      assert {:error, reason} = result
      assert reason in [:daemon_not_running, :distribution_failed]
    end

    test "list_directories returns error when daemon not available" do
      result = Client.list_directories()
      assert {:error, reason} = result
      assert reason in [:daemon_not_running, :distribution_failed]
    end

    test "remove_directory returns error when daemon not available" do
      result = Client.remove_directory("/tmp/some_dir")
      assert {:error, reason} = result
      assert reason in [:daemon_not_running, :distribution_failed]
    end
  end
end
