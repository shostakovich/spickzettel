defmodule Spickzettel.DreamLog do
  @moduledoc """
  Keeps the dream log below 15,000 characters. Its sections are runs, newest first, so the
  oldest sections are the last ones; they move to the top of the archive's sections.
  """

  alias Spickzettel.{Document, Edit, Lookup, MemoryPath, Note, Reply, Write}

  @limit 15_000

  @doc "Archives the oldest sections when the written document is the dream log and too long."
  @spec archive(MemoryPath.t(), Document.t(), map()) :: [String.t()]
  def archive(path, document, deps) do
    with true <- path == deps.dream_log,
         {:ok, cut, sections, count} <- overflow(document.text) do
      move(document, cut, sections, count, deps)
    else
      _ -> []
    end
  end

  @doc """
  The tail to cut so that the rest is below the limit, the sections in it and their count. The
  newest section always stays.
  """
  @spec overflow(String.t()) :: {:ok, String.t(), String.t(), pos_integer()} | :none
  def overflow(text) do
    starts = for {index, 2, _title} <- Note.heading_lines(text), do: index

    with true <- String.length(text) > @limit,
         [_newest | older] <- starts,
         [_ | _] <- older do
      lines = Note.lines(text)
      before = &(lines |> Enum.take(&1) |> Enum.join("\n") |> String.trim_trailing())
      start = Enum.find(Enum.reverse(older), hd(older), &(String.length(before.(&1)) < @limit))
      kept = byte_size(before.(start))
      cut = binary_part(text, kept, byte_size(text) - kept)

      {:ok, String.trim_trailing(cut), String.trim(cut), Enum.count(starts, &(&1 >= start))}
    else
      _ -> :none
    end
  end

  @doc "Puts the sections before the archive's first section."
  @spec prepend(String.t(), String.t()) :: Edit.result()
  def prepend(text, sections) do
    case Enum.find(Note.heading_lines(text), &match?({_index, 2, _title}, &1)) do
      {index, _level, _title} -> Edit.insert_before(text, index, sections)
      nil -> Edit.append(text, sections)
    end
  end

  defp move(dream_log, cut, sections, count, deps) do
    archive = MemoryPath.to_string(deps.dream_log_archive)
    options = [check_format: false, stamp: false]

    with {:ok, %{id: id}} <- Lookup.entry(deps.dream_log_archive, deps),
         {:ok, _archive, _warnings} <-
           Reply.outline(Write.run(id, &prepend(&1, sections), deps, options)) do
      case Reply.outline(Write.run(dream_log.id, &Edit.str_replace(&1, cut, ""), deps, options)) do
        {:ok, _dream_log, _warnings} ->
          ["Moved #{oldest(count)} of the dream log to #{archive}."]

        {:error, message} ->
          [
            "Warning: copied #{oldest(count)} to #{archive}, " <>
              "but could not remove them from the dream log: #{message}"
          ]
      end
    else
      {:error, message} -> ["Warning: the dream log was not archived: #{message}"]
    end
  end

  defp oldest(1), do: "the oldest section"
  defp oldest(count), do: "the #{count} oldest sections"
end
