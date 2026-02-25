defmodule TimeWatcher.Event do
  @moduledoc """
  Pure data struct representing a filesystem change event.
  """

  @valid_types [:created, :modified, :deleted]

  @enforce_keys [:timestamp, :repo, :hashed_path, :event_type]
  defstruct [:timestamp, :repo, :hashed_path, :event_type]

  @type t :: %__MODULE__{
          timestamp: integer(),
          repo: String.t(),
          hashed_path: String.t(),
          event_type: :created | :modified | :deleted
        }

  @spec new(String.t(), String.t(), :created | :modified | :deleted) :: t()
  def new(path, repo, event_type) when event_type in @valid_types do
    %__MODULE__{
      timestamp: System.system_time(:second),
      repo: repo,
      hashed_path: hash_path(path),
      event_type: event_type
    }
  end

  @spec to_json(t()) :: String.t()
  def to_json(%__MODULE__{} = event) do
    %{
      timestamp: event.timestamp,
      repo: event.repo,
      hashed_path: event.hashed_path,
      event_type: Atom.to_string(event.event_type)
    }
    |> Jason.encode!()
  end

  @spec from_json(String.t()) :: {:ok, t()} | {:error, term()}
  def from_json(json) do
    with {:ok, map} <- Jason.decode(json),
         {:ok, event_type} <- parse_event_type(map["event_type"]) do
      {:ok,
       %__MODULE__{
         timestamp: map["timestamp"],
         repo: map["repo"],
         hashed_path: map["hashed_path"],
         event_type: event_type
       }}
    end
  end

  defp parse_event_type(type) when type in ["created", "modified", "deleted"] do
    {:ok, String.to_existing_atom(type)}
  end

  defp parse_event_type(_), do: {:error, :invalid_event_type}

  defp hash_path(path) do
    :crypto.hash(:sha256, path) |> Base.encode16(case: :lower)
  end
end
