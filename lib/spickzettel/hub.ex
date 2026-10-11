defmodule Spickzettel.Hub do
  @moduledoc """
  The link lines a hub keeps for its notes, one list item per note under a section, which is a
  level-2 heading.
  """

  alias Spickzettel.{Document, Edit, Note}

  @spec sections(String.t() | nil) :: [String.t()]
  def sections(text), do: for({_index, 2, title} <- Note.heading_lines(text), do: title)

  @doc "The cross-project hub links a note only under an existing section the caller names."
  @spec cross_project_section(String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, :unnamed | :unknown}
  def cross_project_section(_text, nil), do: {:error, :unnamed}

  def cross_project_section(text, named) do
    with :error <- existing(text, named), do: {:error, :unknown}
  end

  @doc "A project hub links a note under the named section, else under the one for its typ."
  @spec project_section(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, String.t()} | {:error, :unnamed}
  def project_section(_text, nil, nil), do: {:error, :unnamed}

  def project_section(text, named, default) do
    wanted = named || default

    case existing(text, wanted) do
      {:ok, section} -> {:ok, section}
      :error -> {:ok, wanted}
    end
  end

  @spec link(Document.t(), String.t() | nil) :: String.t()
  def link(%Document{} = document, summary) do
    label =
      [document.icon, "[#{document.title}](#{document.url})"]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")

    if summary, do: "* #{label} — #{summary}", else: "* #{label}"
  end

  @doc "Adds the link line at the end of the section, appending the section if it is missing."
  @spec add_link(String.t(), String.t(), String.t()) :: Edit.result()
  def add_link(text, section, line) do
    lines = Note.lines(text)

    case Enum.find(Note.heading_lines(text), &match?({_index, 2, ^section}, &1)) do
      nil ->
        Edit.append(text, "## #{section}\n\n#{line}")

      {start, _level, _title} ->
        last = last_line(lines, start, section_end(text, start, length(lines)))
        separator = if list_item?(Enum.at(lines, last)), do: "", else: "\n"
        Edit.insert(text, last + 1, separator <> line)
    end
  end

  @doc "Removes the first list item whose first link points to the document."
  @spec remove_link(String.t(), String.t() | nil) :: Edit.result()
  def remove_link(text, url_id) when is_binary(url_id) do
    pattern = ~r{^\s*[*-]\s+[^\[]*\[[^\]]*\]\([^)\s]*/doc/(?:[^)\s]*-)?#{Regex.escape(url_id)}\)}u

    case text |> String.split("\n") |> Enum.find_index(&Regex.match?(pattern, &1)) do
      index when is_integer(index) and index > 0 -> Edit.remove_line(text, index)
      _none -> {:error, "it has no link line for the note."}
    end
  end

  def remove_link(_text, nil), do: {:error, "the note has no link address."}

  defp existing(text, wanted) do
    normalized = Note.normalize(wanted)

    case Enum.find(sections(text), &(Note.normalize(&1) == normalized)) do
      nil -> :error
      section -> {:ok, section}
    end
  end

  defp section_end(text, start, count) do
    Enum.find_value(Note.heading_lines(text), count, fn {index, level, _title} ->
      if index > start and level <= 2, do: index
    end)
  end

  defp last_line(lines, start, finish) do
    Enum.find((finish - 1)..start//-1, &(String.trim(Enum.at(lines, &1)) != ""))
  end

  defp list_item?(line), do: Regex.match?(~r/^\s*[*-]\s/, line)
end
