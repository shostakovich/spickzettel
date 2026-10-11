defmodule Spickzettel.Edit do
  @moduledoc """
  Turns edits into patches for Outline's patch mode, which replaces the first occurrence of
  `find` with `replace`.

  Edits at a line anchor on the fewest lines up to it whose first occurrence is that position,
  so the patch touches as little of the document as possible.
  """

  alias Spickzettel.Note

  @type patch :: {find :: String.t(), replace :: String.t()}
  @type result :: {:ok, patch()} | {:error, String.t()}

  @evidence ~r/^(\s*\*\*[^*]+:\*\*\s*)(\d+)\s+sessions?,\s+\S+\s+\d{4}-\d{2}-\d{2}\s*$/iu

  @spec apply(String.t(), patch()) :: String.t()
  def apply(text, {find, replace}), do: String.replace(text, find, replace, global: false)

  @spec str_replace(String.t(), String.t(), String.t()) :: result()
  def str_replace(_text, "", _new), do: {:error, "old_str must not be empty."}

  def str_replace(text, old, new) do
    case length(String.split(text, old)) - 1 do
      0 ->
        {:error, "old_str was not found in the note; nothing changed."}

      1 ->
        {:ok, {old, new}}

      count ->
        {:error,
         "old_str occurs #{count} times in the note; add context to make it unique. Nothing changed."}
    end
  end

  @spec insert(String.t(), integer(), String.t()) :: result()
  def insert(text, line, inserted) do
    count = Note.line_count(text)
    inserted = String.trim_trailing(inserted, "\n")

    cond do
      line < 0 or line > count -> {:error, "insert_line must be between 0 and #{count}."}
      inserted == "" -> {:error, "insert_text must not be empty."}
      line == 0 -> anchor_after(text, &{&1, inserted <> "\n" <> &1})
      true -> anchor_before(text, line - 1, &{&1, &1 <> "\n" <> inserted})
    end
  end

  @doc "Appends a block at the end, separated by a blank line."
  @spec append(String.t(), String.t()) :: result()
  def append(text, block), do: insert(text, Note.line_count(text), "\n" <> block)

  @doc "Replaces the line at the 0-based `index`."
  @spec replace_line(String.t(), non_neg_integer(), String.t()) :: result()
  def replace_line(text, index, line) do
    anchor_before(text, index, fn window ->
      {window, window |> String.split("\n") |> List.replace_at(-1, line) |> Enum.join("\n")}
    end)
  end

  @doc "Counts one more session in the evidence line and sets its date, adding the line if missing."
  @spec confirm(String.t(), Date.t()) :: result()
  def confirm(text, date) do
    lines = String.split(text, "\n")

    case lines |> Enum.with_index() |> Enum.filter(&evidence?/1) |> List.last() do
      {line, index} ->
        [label, count] = Regex.run(@evidence, line, capture: :all_but_first)
        replace_line(text, index, label <> evidence(String.to_integer(count) + 1, date))

      nil ->
        append(text, "**Evidence:** " <> evidence(1, date))
    end
  end

  defp evidence?({line, _index}), do: Regex.match?(@evidence, line)

  defp evidence(1, date), do: "1 session, last #{date}"
  defp evidence(count, date), do: "#{count} sessions, last #{date}"

  defp anchor_before(text, index, patch) do
    lines = String.split(text, "\n")

    Enum.find_value(index..0//-1, no_anchor(), fn first ->
      window = lines |> Enum.slice(first..index) |> Enum.join("\n")

      if not blank?(window) and first_offset(text, window) == offset(lines, first),
        do: {:ok, patch.(window)}
    end)
  end

  defp anchor_after(text, patch) do
    lines = String.split(text, "\n")

    case Enum.find_index(lines, &(not blank?(&1))) do
      nil -> no_anchor()
      last -> {:ok, patch.(lines |> Enum.take(last + 1) |> Enum.join("\n"))}
    end
  end

  defp no_anchor, do: {:error, "The note has no text to anchor the edit on."}

  defp blank?(text), do: String.trim(text) == ""

  defp first_offset(text, window) do
    {offset, _length} = :binary.match(text, window)
    offset
  end

  defp offset(lines, index) do
    lines |> Enum.take(index) |> Enum.map(&(byte_size(&1) + 1)) |> Enum.sum()
  end
end
