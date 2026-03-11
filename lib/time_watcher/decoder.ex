defmodule TimeWatcher.Decoder do
  @moduledoc """
  Decodes event path IDs back to actual file paths.

  Hashed path IDs are looked up by rehashing files in the repository.
  Plaintext path IDs are returned directly without decoding.
  """

  alias TimeWatcher.Event

  @type hash_map :: %{String.t() => String.t()}

  @doc """
  Builds a map of hashed paths to actual file paths for all files in the given directory.
  """
  @spec build_hash_map(String.t()) :: hash_map()
  def build_hash_map(repo_dir) do
    expanded_dir = Path.expand(repo_dir)

    expanded_dir
    |> list_all_files()
    |> Map.new(fn path -> {hash_path(path), path} end)
  end

  @doc """
  Returns true if the path_id is a SHA-256 hash (64 lowercase hex characters).
  """
  @spec hashed?(String.t()) :: boolean()
  def hashed?(path_id) do
    byte_size(path_id) == 64 and String.match?(path_id, ~r/^[0-9a-f]+$/)
  end

  @doc """
  Decodes an event by looking up its path_id in the hash map.
  Plaintext path_ids are used directly as decoded_path.
  Hashed path_ids are looked up in the hash map.
  """
  @spec decode_event(Event.t(), hash_map()) :: Event.t()
  def decode_event(%Event{} = event, hash_map) do
    decoded_path =
      if hashed?(event.path_id) do
        Map.get(hash_map, event.path_id)
      else
        event.path_id
      end

    %{event | decoded_path: decoded_path}
  end

  @doc """
  Decodes a list of events using the given hash map.
  """
  @spec decode_events([Event.t()], hash_map()) :: [Event.t()]
  def decode_events(events, hash_map) do
    Enum.map(events, &decode_event(&1, hash_map))
  end

  defp list_all_files(dir) do
    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
  end

  defp hash_path(path) do
    :crypto.hash(:sha256, path) |> Base.encode16(case: :lower)
  end
end
