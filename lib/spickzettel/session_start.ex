defmodule Spickzettel.SessionStart do
  @moduledoc """
  The text the SessionStart hook puts into a local session: the cross-project hub and the
  project's hub, rendered like `view` without the notes' summaries. Over the hook's context limit,
  the longer hub loses its oldest entry until the text fits, so neither hub is emptied first.
  """

  alias Spickzettel.{Lookup, MemoryPath, Reply, View}

  @limit 10_000
  @preface "Memory hubs, loaded at session start; view their notes with the memory tool."

  @spec text(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def text(project) do
    text(project,
      index: Spickzettel.Index,
      outline: Spickzettel.Outline,
      global_hub: Application.fetch_env!(:spickzettel, :global_hub)
    )
  end

  @spec text(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def text(project, deps) do
    deps = Map.new(deps)

    with {:ok, global, notes} <- Lookup.hub({:hub, deps.global_hub}, deps),
         {:ok, project_hub} <- project_hub(project, deps) do
      global = section(global, notes)

      case project_hub do
        {hub, notes} -> {:ok, fit([global, section(hub, notes)], nil)}
        :none -> {:ok, fit([global], missing(project))}
      end
    end
  end

  defp project_hub(name, deps) do
    case Lookup.index({:hub, name}, deps) do
      {:ok, hub} ->
        with {:ok, notes} <- Reply.outline(deps.outline.list_documents(hub.id)),
             do: {:ok, {hub, notes}}

      {:error, :not_found} ->
        {:ok, :none}

      error ->
        Reply.outline(error)
    end
  end

  defp section(hub, notes) do
    [heading | entries] = View.hub_lines(hub, notes, summary: false)
    %{path: MemoryPath.hub(hub.title), heading: heading, entries: entries}
  end

  defp missing(project),
    do: "No hub #{MemoryPath.hub(project)}, so only the cross-project hub is loaded."

  defp fit(sections, notice), do: fit(sections, Enum.map(sections, &length(&1.entries)), notice)

  defp fit(sections, kept, notice) do
    text = render(sections, kept, notice)

    with false <- utf16_length(text) < @limit,
         {_length, index} <- longest(sections, kept) do
      fit(sections, List.update_at(kept, index, &(&1 - 1)), notice)
    else
      _fits_or_empty -> text
    end
  end

  defp longest(sections, kept) do
    Enum.zip(sections, kept)
    |> Enum.with_index()
    |> Enum.filter(fn {{_section, keep}, _index} -> keep > 0 end)
    |> Enum.map(fn {{section, keep}, index} -> {utf16_length(block(section, keep)), index} end)
    |> Enum.max(&>=/2, fn -> nil end)
  end

  # Hook clients count the limit in UTF-16 code units, in which an emoji takes two or more.
  defp utf16_length(text),
    do: byte_size(:unicode.characters_to_binary(text, :utf8, :utf16)) |> div(2)

  defp render(sections, kept, notice) do
    blocks = Enum.zip_with(sections, kept, &block/2) ++ List.wrap(notice)
    Enum.join([@preface | blocks], "\n\n") <> "\n"
  end

  defp block(section, keep) do
    hidden = length(section.entries) - keep
    pointer = if hidden > 0, do: [pointer(hidden, section.path)], else: []
    Enum.join([section.heading | Enum.take(section.entries, keep)] ++ pointer, "\n")
  end

  defp pointer(1, path), do: "- … 1 more note: memory view #{path}"
  defp pointer(hidden, path), do: "- … #{hidden} more notes: memory view #{path}"
end
