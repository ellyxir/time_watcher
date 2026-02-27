defmodule TimeWatcher.Decoder do
  @moduledoc """
  Decodes hashed file paths back to actual paths by matching against files in a repository.
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
  Decodes an event by looking up its hashed_path in the hash map.
  Sets decoded_path if found, otherwise leaves it as nil.
  """
  @spec decode_event(Event.t(), hash_map()) :: Event.t()
  def decode_event(%Event{} = event, hash_map) do
    decoded_path = Map.get(hash_map, event.hashed_path)
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
