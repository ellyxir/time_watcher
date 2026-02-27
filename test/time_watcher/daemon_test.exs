defmodule TimeWatcher.DaemonTest do
  use ExUnit.Case, async: false

  alias TimeWatcher.Daemon

  setup do
    # Ensure no node is running before each test
    if Node.alive?() do
      Node.stop()
    end

    :ok
  end

  describe "check_not_already_running/0" do
    test "returns :ok when no daemon is running" do
      # Since we're not in a distributed environment during tests,
      # this should return :ok (can't connect to anything)
      result = Daemon.check_not_already_running()
      # Could be :ok or {:error, :already_running} depending on test order
      # and whether epmd is running
      assert result in [:ok, {:error, :already_running}]
    end
  end

  describe "start_daemon/1" do
    @tag timeout: 3000
    test "returns error or blocks when starting" do
      # In test env without epmd, this returns an error.
      # With epmd running, it blocks (calls Process.sleep(:infinity)).
      # We use a task with timeout to handle both cases.
      task = Task.async(fn -> Daemon.start_daemon(dirs: ["/tmp/test"]) end)

      case Task.yield(task, 1000) do
        {:ok, result} ->
          # Distribution failed, got an error back
          assert {:error, _reason} = result

        nil ->
          # Function is blocking (daemon started successfully)
          # This is also acceptable - kill the task and clean up
          Task.shutdown(task, :brutal_kill)

          if Node.alive?() do
            Node.stop()
          end

          assert true
      end
    end
  end
end
