defmodule Spickzettel.Similar do
  @moduledoc """
  Finds notes similar to a new one with Outline's full-text search. Outline joins search words
  with AND, so the query asks for any of the title's and summary's words instead and lets the
  ranking put notes sharing the most words first.
  """

  alias Spickzettel.MemoryPath

  @count 3
  @search_limit 10
  @stopwords ~w(
    and are but can for from has have its not the this that was with you your all any into
    out use when what which who how only also more than then them they their there here
    der die das den dem des ein eine einen einem einer eines und oder aber auch auf aus bei
    bis für mit nach von vor zum zur ist sind war wird werden wie wenn als nur nicht noch
    schon sich sie wir ich man was wer hat haben kein keine über unter durch gegen ohne
  )

  @doc "Paths of the best matching notes, or nothing when the search fails."
  @spec paths(String.t(), map()) :: [String.t()]
  def paths(text, deps) do
    with [_ | _] = terms <- terms(text),
         {:ok, documents} <- deps.outline.search_documents(terms, @search_limit) do
      documents
      |> Stream.reject(&is_nil(&1.parent_id))
      |> Stream.flat_map(&path(&1, deps))
      |> Enum.take(@count)
    else
      _ -> []
    end
  end

  @spec terms(String.t()) :: [String.t()]
  def terms(text) do
    ~r/[\p{L}\p{N}]{3,}/u
    |> Regex.scan(text)
    |> List.flatten()
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in @stopwords))
  end

  defp path(document, deps) do
    case deps.index.path(document.id) do
      {:ok, path} -> [MemoryPath.to_string(path)]
      _error -> []
    end
  end
end
