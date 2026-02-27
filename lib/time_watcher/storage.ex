defmodule TimeWatcher.Storage do
  @moduledoc """
  Filesystem I/O and git operations for persisting events.
  """

  alias TimeWatcher.Event

  @spec data_dir() :: String.t()
  def data_dir do
    Application.get_env(:time_watcher, :data_dir)
  end

  @spec save_event(Event.t(), String.t()) :: :ok | {:error, term()}
  def save_event(%Event{} = event, base_dir \\ data_dir()) do
    date_str = event.timestamp |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_string()
    date_dir = Path.join(base_dir, date_str)
    File.mkdir_p!(date_dir)

    hostname = hostname()
    unique = System.unique_integer([:positive])
    filename = "#{event.timestamp}_#{hostname}_#{unique}.json"
    filepath = Path.join(date_dir, filename)

    case File.write(filepath, Event.to_json(event)) do
      :ok -> :ok
      error -> error
    end
  end

  @spec load_events(String.t(), String.t()) :: [Event.t()]
  def load_events(date_str, base_dir \\ data_dir()) do
    date_dir = Path.join(base_dir, date_str)

    case File.ls(date_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.sort()
        |> Enum.flat_map(fn file ->
          filepath = Path.join(date_dir, file)
          parse_event_file(filepath)
        end)

      {:error, :enoent} ->
        []
    end
  end

  @spec delete_events(String.t(), String.t()) :: {:ok, non_neg_integer()}
  def delete_events(date_str, base_dir \\ data_dir()) do
    date_dir = Path.join(base_dir, date_str)

    case File.ls(date_dir) do
      {:ok, files} ->
        json_files = Enum.filter(files, &String.ends_with?(&1, ".json"))

        Enum.each(json_files, fn file ->
          File.rm!(Path.join(date_dir, file))
        end)

        {:ok, length(json_files)}

      {:error, :enoent} ->
        {:ok, 0}
    end
  end

  @spec delete_all_events(String.t()) :: {:ok, non_neg_integer()}
  def delete_all_events(base_dir \\ data_dir()) do
    case File.ls(base_dir) do
      {:ok, entries} ->
        count =
          entries
          |> Enum.filter(&date_directory?(&1, base_dir))
          |> Enum.map(fn date_str ->
            {:ok, n} = delete_events(date_str, base_dir)
            n
          end)
          |> Enum.sum()

        {:ok, count}

      {:error, :enoent} ->
        {:ok, 0}
    end
  end

  @spec git_stage_all(String.t()) :: :ok | {:error, term()}
  def git_stage_all(base_dir \\ data_dir()) do
    case System.cmd("git", ["add", "-A"], cd: base_dir, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, output}
    end
  end

  @spec git_commit(String.t(), String.t()) :: :ok | {:error, term()}
  def git_commit(message, base_dir \\ data_dir()) do
    with :ok <- ensure_git_repo(base_dir),
         :ok <- git_stage_all(base_dir),
         {_, 0} <-
           System.cmd("git", ["commit", "-m", message, "--allow-empty"],
             cd: base_dir,
             stderr_to_stdout: true
           ) do
      :ok
    else
      {:error, _} = error ->
        error

      {output, _code} ->
        require Logger
        Logger.warning("git commit failed: #{output}")
        {:error, output}
    end
  end

  defp parse_event_file(filepath) do
    with {:ok, content} <- File.read(filepath),
         {:ok, event} <- Event.from_json(content) do
      [event]
    else
      _ -> []
    end
  end

  defp ensure_git_repo(base_dir) do
    if File.dir?(Path.join(base_dir, ".git")) do
      :ok
    else
      case System.cmd("git", ["init"], cd: base_dir, stderr_to_stdout: true) do
        {_, 0} -> :ok
        {output, _} -> {:error, output}
      end
    end
  end

  defp hostname do
    {:ok, name} = :inet.gethostname()
    to_string(name)
  end

  defp date_directory?(entry, base_dir) do
    path = Path.join(base_dir, entry)
    File.dir?(path) && Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, entry)
  end
end
