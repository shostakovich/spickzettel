defmodule Spickzettel.Note do
  @moduledoc "Reads the parts of a note's Markdown: header line, summary, sections and lines."

  alias Spickzettel.Document

  @header ~r/^`?name:/
  @name ~r/^`?name:\s*([^\s`·]+)/u
  @stand ~r/\bstand:\s*(\d{4}-\d{2}-\d{2})/
  @label ~r/^\*\*[^*]+:\*\*\s*/u
  @heading ~r/^(\#{1,6})\s+(.+)$/u
  @fence ~r/^\s*(```|~~~)/

  @spec slug(Document.t()) :: String.t()
  def slug(%Document{text: text, title: title}), do: name(text) || slugify(title)

  @spec name(String.t() | nil) :: String.t() | nil
  def name(text), do: header_value(text, @name)

  @spec stand(String.t() | nil) :: String.t() | nil
  def stand(text), do: header_value(text, @stand)

  @spec summary(String.t() | nil) :: String.t() | nil
  def summary(text) do
    paragraphs = text |> non_empty_lines() |> Enum.take(2)

    line =
      case paragraphs do
        [first, second] -> if header?(first), do: second, else: first
        [first] -> unless header?(first), do: first
        [] -> nil
      end

    line && String.replace(line, @label, "")
  end

  @spec headings(String.t() | nil) :: [String.t()]
  def headings(text) do
    for {_index, _level, title} <- heading_lines(text), do: title
  end

  @spec section(String.t() | nil, String.t()) :: {:ok, String.t()} | :error
  def section(text, wanted) do
    wanted = wanted |> String.trim_leading("#") |> normalize()
    lines = lines(text)
    headings = heading_lines(text)

    case Enum.find(headings, fn {_index, _level, title} -> normalize(title) == wanted end) do
      nil ->
        :error

      {start, level, _title} ->
        finish =
          Enum.find_value(headings, length(lines), fn {index, other_level, _title} ->
            if index > start and other_level <= level, do: index
          end)

        {:ok,
         lines |> Enum.slice(start..(finish - 1)//1) |> Enum.join("\n") |> String.trim_trailing()}
    end
  end

  @spec line_range(String.t() | nil, pos_integer(), integer()) :: {:ok, String.t()} | :error
  def line_range(text, first, last) do
    lines = lines(text)
    last = if last == -1, do: length(lines), else: last

    if first >= 1 and first <= length(lines) and last >= first do
      {:ok,
       lines |> Enum.slice((first - 1)..(min(last, length(lines)) - 1)//1) |> Enum.join("\n")}
    else
      :error
    end
  end

  @spec line_count(String.t() | nil) :: non_neg_integer()
  def line_count(text), do: text |> lines() |> length()

  defp header_value(text, regex) do
    with [first | _] <- non_empty_lines(text),
         true <- header?(first),
         [_, value] <- Regex.run(regex, first) do
      value
    else
      _ -> nil
    end
  end

  defp header?(line), do: Regex.match?(@header, line)

  defp heading_lines(text) do
    text
    |> lines()
    |> Enum.with_index()
    |> Enum.reduce({[], false}, fn {line, index}, {found, in_fence} ->
      cond do
        Regex.match?(@fence, line) ->
          {found, not in_fence}

        in_fence ->
          {found, in_fence}

        match = Regex.run(@heading, line) ->
          [_, hashes, title] = match
          {[{index, String.length(hashes), heading_title(title)} | found], in_fence}

        true ->
          {found, in_fence}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  # A closing run of #s needs whitespace before it, so "## C#" keeps its #.
  defp heading_title(raw) do
    title = String.trim(raw)
    open = String.trim_trailing(title, "#")

    cond do
      open == "" -> ""
      open != title and String.trim_trailing(open) != open -> String.trim_trailing(open)
      true -> title
    end
  end

  defp lines(nil), do: []
  defp lines(text), do: text |> String.trim_trailing() |> String.split("\n")

  defp non_empty_lines(text) do
    text |> lines() |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp normalize(title), do: title |> String.trim() |> String.downcase()

  defp slugify(title) do
    title
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
