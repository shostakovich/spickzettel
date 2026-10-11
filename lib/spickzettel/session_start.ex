defmodule Spickzettel.SessionStart do
  @moduledoc """
  The text the SessionStart hook puts into a local session: the cross-project hub and the
  project's hub, rendered like `view`. Over the hook's context limit, the project hub's oldest
  entries go first, then the cross-project hub's.
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
    [heading | entries] = View.hub_lines(hub, notes)
    %{path: MemoryPath.hub(hub.title), heading: heading, entries: entries}
  end

  defp missing(project),
    do: "No hub #{MemoryPath.hub(project)}, so only the cross-project hub is loaded."

  defp fit(sections, notice) do
    full = Enum.map(sections, &length(&1.entries))

    kept =
      sections
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.reduce_while(full, fn {section, index}, kept ->
        if fits?(sections, kept, notice),
          do: {:halt, kept},
          else: {:cont, shorten(sections, kept, index, length(section.entries), notice)}
      end)

    render(sections, kept, notice)
  end

  defp shorten(sections, kept, index, count, notice) do
    keep =
      Enum.find(count..0//-1, 0, &fits?(sections, List.replace_at(kept, index, &1), notice))

    List.replace_at(kept, index, keep)
  end

  defp fits?(sections, kept, notice),
    do: utf16_length(render(sections, kept, notice)) < @limit

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
