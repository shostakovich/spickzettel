defmodule Spickzettel.Reply do
  @moduledoc "The texts the memory tool answers with."

  alias Spickzettel.{Document, MemoryPath, Note}

  @doc "One line `ok · path · stand`, then any further lines."
  @spec written(String.t(), Document.t(), [String.t()]) :: String.t()
  def written(path, document, lines) do
    line = Enum.join(["ok", path | List.wrap(Note.stand(document.text))], " · ")
    Enum.join([line | lines], "\n")
  end

  @doc "One line `ok · deleted path`, then any further lines."
  @spec deleted(String.t(), [String.t()]) :: String.t()
  def deleted(path, lines), do: Enum.join(["ok · deleted #{path}" | lines], "\n")

  @spec missing(MemoryPath.t()) :: String.t()
  def missing({:hub, name}),
    do: "No hub at #{MemoryPath.hub(name)}. View /memories to list the hubs."

  def missing({:note, hub, _slug} = path),
    do: "No note at #{MemoryPath.to_string(path)}. View #{MemoryPath.hub(hub)} to list its notes."

  @doc "Passes results on and turns Outline errors into messages."
  @spec outline(term()) :: :ok | {:ok, term()} | {:ok, term(), term()} | {:error, String.t()}
  def outline(:ok), do: :ok
  def outline({:ok, _value} = result), do: result
  def outline({:ok, _value, _warnings} = result), do: result
  def outline({:error, message}) when is_binary(message), do: {:error, message}

  def outline({:error, {:rejected, message}}),
    do: {:error, "Outline rejected the edit (#{message}); nothing changed."}

  def outline({:error, {:status, status}}),
    do: {:error, "Outline answered with status #{status}."}

  def outline({:error, %{__exception__: true} = exception}),
    do: {:error, "Outline is unreachable: #{Exception.message(exception)}"}

  def outline({:error, reason}),
    do: {:error, "Outline request failed: #{inspect(reason)}"}
end
