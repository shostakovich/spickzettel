defmodule Spickzettel.Lookup do
  @moduledoc "Resolves memory paths to Outline documents through the index."

  alias Spickzettel.{Document, MemoryPath, Reply}

  @doc "The index entry, without text."
  @spec entry(MemoryPath.t(), map()) :: {:ok, Document.t()} | {:error, String.t()}
  def entry(path, deps) do
    case index(path, deps) do
      {:error, :not_found} -> {:error, Reply.missing(path)}
      result -> Reply.outline(result)
    end
  end

  @doc "The document with its text."
  @spec document(MemoryPath.t(), map()) :: {:ok, Document.t()} | {:error, String.t()}
  def document(path, deps) do
    with {:ok, %{id: id}} <- entry(path, deps) do
      gone(deps.outline.get_document(id), path, deps)
    end
  end

  @doc "Fails with `:not_found` when nothing is at the path."
  @spec index(MemoryPath.t(), map()) :: {:ok, Document.t()} | {:error, term()}
  def index({:hub, name}, deps), do: deps.index.lookup(name, nil)
  def index({:note, hub, slug}, deps), do: deps.index.lookup(hub, slug)

  @doc "Refreshes the index when Outline no longer knows a document the index found."
  @spec gone(term(), MemoryPath.t(), map()) :: term()
  def gone({:error, :not_found}, path, deps) do
    deps.index.refresh()
    {:error, Reply.missing(path)}
  end

  def gone(result, _path, _deps), do: Reply.outline(result)
end
