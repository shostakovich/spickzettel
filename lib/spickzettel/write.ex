defmodule Spickzettel.Write do
  @moduledoc """
  Writes an edit to Outline as a patch against the revision it was read at. When the document
  changed in between, it reads it again and applies the edit once more.
  """

  alias Spickzettel.{Document, Edit, Note, NoteFormat, Outline}

  @attempts 2
  @max_length 15_000

  @type edit :: (String.t() -> Edit.result())
  @type option :: {:check_format, boolean()} | {:check_length, boolean()} | {:stamp, boolean()}

  @doc """
  Applies `edit` to the document. `check_format` rejects edits that make a valid note invalid,
  `check_length: false` leaves out the length warning, `stamp` sets the note's `stand` to today
  afterwards.
  """
  @spec run(String.t(), edit(), map(), [option()]) ::
          {:ok, Document.t(), [String.t()]} | {:error, String.t() | Outline.error()}
  def run(id, edit, deps, options) do
    with {:ok, written, warnings} <- patch(id, edit, deps, options, @attempts) do
      if options[:stamp],
        do: stamp_written(written, warnings, deps),
        else: {:ok, written, warnings}
    end
  end

  defp patch(id, edit, deps, options, attempts) do
    with {:ok, document} <- deps.outline.get_document(id),
         do: patch(id, document, edit, deps, options, attempts)
  end

  defp patch(id, document, edit, deps, options, attempts) do
    with {:ok, patch} <- edit.(document.text),
         edited = Edit.apply(document.text, patch),
         {:ok, warnings} <- check(document.text, edited, options) do
      case deps.outline.patch_document(id, patch, document.revision) do
        {:ok, written} ->
          with :ok <- applied(written, edited), do: {:ok, written, warnings}

        {:error, :conflict} when attempts > 1 ->
          patch(id, edit, deps, options, attempts - 1)

        {:error, :conflict} ->
          {:error, "The note changed again while writing; nothing changed. View it and retry."}

        {:error, {:rejected, _message}} = rejected when attempts > 1 ->
          retry_if_changed(id, document.revision, rejected, edit, deps, options, attempts)

        error ->
          error
      end
    end
  end

  # Outline checks findText before lastRevision, so a stale patch can come back rejected.
  defp retry_if_changed(id, revision, rejected, edit, deps, options, attempts) do
    case deps.outline.get_document(id) do
      {:ok, %{revision: current} = document} when current != revision ->
        patch(id, document, edit, deps, options, attempts - 1)

      _unchanged ->
        rejected
    end
  end

  # Outline may answer success yet store something else, e.g. when it drops blocks it cannot patch.
  defp applied(written, edited) do
    if comparable(written.text) == comparable(edited),
      do: :ok,
      else:
        {:error,
         "Outline accepted the edit but stored a different text; the edit may be missing or " <>
           "incomplete, so view the document and check it."}
  end

  # Outline re-serializes the text, escaping punctuation and normalizing bullets and blank lines.
  defp comparable(text) do
    for line <- String.split(text, "\n"), line = String.trim(line), line != "" do
      line |> String.replace(~r/\\([[:punct:]])/u, "\\1") |> String.replace(~r/^[-+] /, "* ")
    end
  end

  defp check(before, edited, options) do
    problems =
      if options[:check_format],
        do: {NoteFormat.problems(before), NoteFormat.problems(edited)},
        else: {[], []}

    case problems do
      {[], [_ | _] = new} ->
        {:error,
         "Rejected: the note would become invalid: #{Enum.join(new, "; ")}. Nothing changed."}

      {_before, []} ->
        {:ok, length_warnings(edited, options)}

      {_before, remaining} ->
        {:ok,
         [
           "Warning: the note is invalid: #{Enum.join(remaining, "; ")}."
           | length_warnings(edited, options)
         ]}
    end
  end

  defp length_warnings(text, options) do
    if Keyword.get(options, :check_length, true), do: length_warnings(text), else: []
  end

  @spec length_warnings(String.t()) :: [String.t()]
  def length_warnings(text) do
    case String.length(text) do
      length when length > @max_length ->
        [
          "Warning: the note has #{length} characters, above #{@max_length}; consider splitting it."
        ]

      _length ->
        []
    end
  end

  defp stamp_written(written, warnings, deps) do
    case stamp(written, deps, @attempts) do
      {:ok, stamped} -> {:ok, stamped, warnings}
      {:error, _reason} -> {:ok, written, warnings ++ ["Warning: stand was not updated."]}
    end
  end

  defp stamp(document, deps, attempts) do
    with {index, line} <- Note.put_stand(document.text, deps.today.()),
         {:ok, patch} <- Edit.replace_line(document.text, index, line) do
      case deps.outline.patch_document(document.id, patch, document.revision) do
        {:ok, written} ->
          with :ok <- applied(written, Edit.apply(document.text, patch)), do: {:ok, written}

        {:error, :conflict} when attempts > 1 ->
          with {:ok, current} <- deps.outline.get_document(document.id),
               do: stamp(current, deps, attempts - 1)

        result ->
          result
      end
    else
      nil -> {:ok, document}
      error -> error
    end
  end
end
