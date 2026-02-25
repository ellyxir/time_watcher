defmodule TimeWatcher.EventTest do
  use ExUnit.Case, async: true

  alias TimeWatcher.Event

  describe "new/3" do
    test "creates event with hashed path" do
      event = Event.new("/home/user/project/lib/foo.ex", "my_project", :modified)

      assert event.repo == "my_project"
      assert event.event_type == :modified

      assert event.hashed_path ==
               :crypto.hash(:sha256, "/home/user/project/lib/foo.ex")
               |> Base.encode16(case: :lower)

      assert is_integer(event.timestamp)
    end

    test "accepts :created event type" do
      event = Event.new("/path", "repo", :created)
      assert event.event_type == :created
    end

    test "accepts :deleted event type" do
      event = Event.new("/path", "repo", :deleted)
      assert event.event_type == :deleted
    end

    test "rejects invalid event type" do
      assert_raise FunctionClauseError, fn ->
        Event.new("/path", "repo", :unknown)
      end
    end
  end

  describe "JSON round-trip" do
    test "to_json/1 produces valid JSON" do
      event = Event.new("/some/path", "my_repo", :modified)
      json = Event.to_json(event)
      assert {:ok, decoded} = Jason.decode(json)
      assert decoded["repo"] == "my_repo"
      assert decoded["event_type"] == "modified"
      assert decoded["timestamp"] == event.timestamp
    end

    test "from_json/1 reconstructs event" do
      original = Event.new("/some/path", "my_repo", :modified)
      json = Event.to_json(original)
      {:ok, restored} = Event.from_json(json)

      assert restored.timestamp == original.timestamp
      assert restored.repo == original.repo
      assert restored.hashed_path == original.hashed_path
      assert restored.event_type == original.event_type
    end

    test "from_json/1 returns error for invalid JSON" do
      assert {:error, _} = Event.from_json("not json")
    end

    test "from_json/1 returns error for invalid event_type" do
      json = Jason.encode!(%{timestamp: 123, repo: "r", hashed_path: "abc", event_type: "bad"})
      assert {:error, :invalid_event_type} = Event.from_json(json)
    end
  end
end
