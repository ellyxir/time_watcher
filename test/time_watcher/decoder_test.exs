defmodule TimeWatcher.DecoderTest do
  use ExUnit.Case, async: true

  alias TimeWatcher.{Decoder, Event}

  setup do
    repo_dir =
      Path.join(System.tmp_dir!(), "tw_decoder_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(repo_dir)

    on_exit(fn -> File.rm_rf!(repo_dir) end)

    %{repo_dir: repo_dir}
  end

  describe "build_hash_map/1" do
    test "builds map of hashed paths to actual paths", %{repo_dir: repo_dir} do
      # Create some test files
      file1 = Path.join(repo_dir, "foo.ex")
      file2 = Path.join(repo_dir, "bar.ex")
      File.write!(file1, "content1")
      File.write!(file2, "content2")

      hash_map = Decoder.build_hash_map(repo_dir)

      hash1 = hash_path(file1)
      hash2 = hash_path(file2)

      assert Map.get(hash_map, hash1) == file1
      assert Map.get(hash_map, hash2) == file2
    end

    test "includes files in subdirectories", %{repo_dir: repo_dir} do
      subdir = Path.join(repo_dir, "lib")
      File.mkdir_p!(subdir)
      file = Path.join(subdir, "nested.ex")
      File.write!(file, "content")

      hash_map = Decoder.build_hash_map(repo_dir)

      hash = hash_path(file)
      assert Map.get(hash_map, hash) == file
    end

    test "returns empty map for empty directory", %{repo_dir: repo_dir} do
      hash_map = Decoder.build_hash_map(repo_dir)
      assert hash_map == %{}
    end

    test "excludes directories from hash map", %{repo_dir: repo_dir} do
      subdir = Path.join(repo_dir, "subdir")
      File.mkdir_p!(subdir)

      hash_map = Decoder.build_hash_map(repo_dir)
      assert hash_map == %{}
    end
  end

  describe "decode_event/2" do
    test "adds decoded_path when hash matches", %{repo_dir: repo_dir} do
      file = Path.join(repo_dir, "test.ex")
      File.write!(file, "content")

      hash_map = Decoder.build_hash_map(repo_dir)

      event = %Event{
        timestamp: 1_740_000_000,
        repo: "test_repo",
        hashed_path: hash_path(file),
        event_type: :modified
      }

      decoded = Decoder.decode_event(event, hash_map)

      assert decoded.decoded_path == file
    end

    test "leaves decoded_path as nil when hash not found", %{repo_dir: repo_dir} do
      hash_map = Decoder.build_hash_map(repo_dir)

      event = %Event{
        timestamp: 1_740_000_000,
        repo: "test_repo",
        hashed_path: "nonexistent_hash",
        event_type: :modified
      }

      decoded = Decoder.decode_event(event, hash_map)

      assert decoded.decoded_path == nil
    end
  end

  describe "decode_events/2" do
    test "decodes multiple events", %{repo_dir: repo_dir} do
      file1 = Path.join(repo_dir, "a.ex")
      file2 = Path.join(repo_dir, "b.ex")
      File.write!(file1, "content1")
      File.write!(file2, "content2")

      hash_map = Decoder.build_hash_map(repo_dir)

      events = [
        %Event{
          timestamp: 1_740_000_000,
          repo: "test_repo",
          hashed_path: hash_path(file1),
          event_type: :modified
        },
        %Event{
          timestamp: 1_740_000_001,
          repo: "test_repo",
          hashed_path: hash_path(file2),
          event_type: :created
        }
      ]

      decoded = Decoder.decode_events(events, hash_map)

      assert length(decoded) == 2
      assert Enum.at(decoded, 0).decoded_path == file1
      assert Enum.at(decoded, 1).decoded_path == file2
    end
  end

  describe "build_hash_map/1 with relative paths" do
    test "expands relative paths to absolute for consistent hashing", %{repo_dir: repo_dir} do
      file = Path.join(repo_dir, "test.ex")
      File.write!(file, "content")

      # Build hash map using absolute path
      hash_map_absolute = Decoder.build_hash_map(repo_dir)

      # Build hash map using relative path (if we can make one)
      {:ok, original_cwd} = File.cwd()
      File.cd!(Path.dirname(repo_dir))

      relative_dir = Path.basename(repo_dir)
      hash_map_relative = Decoder.build_hash_map(relative_dir)

      File.cd!(original_cwd)

      # Both should produce the same hash map with absolute paths
      assert hash_map_absolute == hash_map_relative

      # And should match the hash of the absolute file path
      expected_hash = hash_path(file)
      assert Map.has_key?(hash_map_absolute, expected_hash)
      assert Map.get(hash_map_absolute, expected_hash) == file
    end
  end

  describe "build_hash_map/1 with multiple directories" do
    test "only includes files from the specified directory" do
      base = Path.join(System.tmp_dir!(), "tw_multi_#{System.unique_integer([:positive])}")
      dir1 = Path.join(base, "repo1")
      dir2 = Path.join(base, "repo2")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      on_exit(fn -> File.rm_rf!(base) end)

      file1 = Path.join(dir1, "file.ex")
      file2 = Path.join(dir2, "file.ex")
      File.write!(file1, "content1")
      File.write!(file2, "content2")

      hash_map1 = Decoder.build_hash_map(dir1)
      hash_map2 = Decoder.build_hash_map(dir2)

      # Each hash map should only contain files from its directory
      assert map_size(hash_map1) == 1
      assert map_size(hash_map2) == 1

      # Hashes are different because full paths are different
      hash1 = hash_path(file1)
      hash2 = hash_path(file2)
      assert hash1 != hash2

      assert Map.get(hash_map1, hash1) == file1
      assert Map.get(hash_map1, hash2) == nil

      assert Map.get(hash_map2, hash2) == file2
      assert Map.get(hash_map2, hash1) == nil
    end
  end

  # Helper to match the hashing used in the application
  defp hash_path(path) do
    :crypto.hash(:sha256, path) |> Base.encode16(case: :lower)
  end
end
