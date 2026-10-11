defmodule Spickzettel.NoteFormat do
  @moduledoc """
  The note format: header line `name · typ · stand`, then the summary line, its text at most 160
  characters; feedback and project notes also carry Why and How to apply.
  """

  alias Spickzettel.Note

  @typs ~w(user feedback project reference)
  @reasoned ~w(feedback project)
  @summary_limit 160

  @spec typs() :: [String.t()]
  def typs, do: @typs

  @spec problems(String.t()) :: [String.t()]
  def problems(text) do
    if Note.header?(text),
      do: header_problems(text) ++ summary_problems(text) ++ reason_problems(text),
      else: ["no header line"]
  end

  defp header_problems(text) do
    missing =
      for {field, present?} <- [
            name: Note.name(text) != nil,
            typ: Note.typ(text) in @typs,
            stand: Note.stand(text) != nil
          ],
          not present?,
          do: field

    if missing == [], do: [], else: ["header line lacks #{Enum.join(missing, ", ")}"]
  end

  defp summary_problems(text) do
    summary = Note.summary(text)

    cond do
      summary == nil ->
        ["no summary line"]

      String.length(summary) > @summary_limit ->
        ["summary has #{String.length(summary)} characters, above #{@summary_limit}"]

      true ->
        []
    end
  end

  defp reason_problems(text) do
    if Note.typ(text) in @reasoned do
      for label <- ["Why", "How to apply"],
          not Regex.match?(~r/^\s*\*\*#{label}:\*\*/m, text),
          do: "no **#{label}:** line"
    else
      []
    end
  end
end
