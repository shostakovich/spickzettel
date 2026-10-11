defmodule Spickzettel.Lifecycle do
  @moduledoc """
  Creates, renames and deletes notes, and creates project hubs, keeping each one's link line in
  its hub in sync.
  """

  alias Spickzettel.{
    Document,
    Edit,
    Hub,
    Lookup,
    MemoryPath,
    Note,
    NoteFormat,
    Reply,
    Similar,
    Write
  }

  @slug ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/
  @hub_edit [check_format: false, stamp: false]

  @type new :: %{
          title: String.t() | nil,
          typ: String.t() | nil,
          icon: String.t() | nil,
          text: String.t(),
          section: String.t() | nil
        }
  @type reply :: {:ok, String.t()} | {:error, String.t()}

  @spec create(MemoryPath.t(), new(), map()) :: reply()
  def create({:note, hub_name, slug} = path, new, deps) do
    text = note_text(slug, new, deps.today.())

    with :ok <- check_slug(slug),
         :ok <- check_note(new, text),
         :ok <- vacant(path, deps),
         {:ok, hub} <- Lookup.document({:hub, hub_name}, deps),
         {:ok, section} <- section(hub, new.typ, new.section, deps),
         similar = similar(new.title, text, deps),
         {:ok, note} <-
           Reply.outline(deps.outline.create_document(new_document(new, text, hub))) do
      warnings = link(hub, section, note, text, deps) ++ Write.length_warnings(text)
      deps.index.refresh()
      {:ok, Reply.written(MemoryPath.to_string(path), note, warnings ++ similar)}
    end
  end

  def create({:hub, name} = path, new, deps) do
    text = String.trim(new.text) <> "\n"

    with :ok <- check_hub(new.text),
         :ok <- vacant(path, deps),
         {:ok, global} <- Lookup.document({:hub, deps.global_hub}, deps),
         {:ok, section} <- section(global, nil, new.section, deps),
         new_hub = %{title: name, text: text, icon: new.icon, parent_id: nil},
         {:ok, hub} <- Reply.outline(deps.outline.create_document(new_hub)) do
      warnings = link(global, section, hub, text, deps)
      deps.index.refresh()
      {:ok, Reply.written(MemoryPath.to_string(path), hub, warnings)}
    end
  end

  @doc "Gives a note a new slug, a new hub or both."
  @spec rename(MemoryPath.t(), MemoryPath.t(), String.t() | nil, map()) :: reply()
  def rename({:note, from_hub, from_slug} = from, {:note, to_hub, to_slug} = to, section, deps) do
    with :ok <- distinct(from, to),
         :ok <- check_slug(to_slug),
         {:ok, note} <- Lookup.document(from, deps),
         :ok <- renamable(note, from_slug != to_slug, from),
         :ok <- vacant(to, deps),
         {:ok, target} <- target(from_hub, to_hub, note, section, deps),
         {:ok, note, warnings} <- put_slug(note, from, to_slug, deps) do
      case move(note, target, {:note, from_hub, to_slug}, deps) do
        :ok ->
          warnings = warnings ++ relink(from_hub, target, note, deps)
          deps.index.refresh()
          {:ok, Reply.written(MemoryPath.to_string(to), note, warnings)}

        error ->
          deps.index.refresh()
          error
      end
    end
  end

  @spec delete(MemoryPath.t(), map()) :: reply()
  def delete({:note, hub, _slug} = path, deps) do
    with {:ok, note} <- Lookup.entry(path, deps),
         :ok <- childless(note, path, deps),
         :ok <- Lookup.gone(deps.outline.delete_document(note.id), path, deps) do
      warnings = unlink(hub, note, deps)
      deps.index.refresh()
      {:ok, Reply.deleted(MemoryPath.to_string(path), warnings)}
    end
  end

  defp note_text(slug, new, today) do
    "`name: #{slug}` · `typ: #{new.typ}` · `stand: #{today}`\n\n" <>
      String.trim(new.text) <> "\n"
  end

  defp new_document(new, text, hub),
    do: %{title: new.title, text: text, icon: new.icon, parent_id: hub.id}

  defp check_slug(slug) do
    if Regex.match?(@slug, slug),
      do: :ok,
      else: {:error, "The slug #{inspect(slug)} must be kebab-case, e.g. tests-london-style."}
  end

  defp check_note(new, text) do
    cond do
      new.title == nil ->
        {:error, "create needs a title."}

      new.typ not in NoteFormat.typs() ->
        {:error, "create needs typ: #{Enum.join(NoteFormat.typs(), ", ")}."}

      Note.header?(new.text) ->
        {:error, "Leave out the header line; the server adds it from path and typ."}

      (problems = NoteFormat.problems(text)) != [] ->
        {:error, "Rejected: the note would be invalid: #{Enum.join(problems, "; ")}."}

      true ->
        :ok
    end
  end

  defp check_hub(text) do
    if String.trim(text) == "",
      do: {:error, "create needs file_text with a one-line description of the hub."},
      else: :ok
  end

  defp vacant(path, deps) do
    case Lookup.index(path, deps) do
      {:error, :not_found} ->
        :ok

      {:ok, _document} ->
        {:error, "#{MemoryPath.to_string(path)} already exists; nothing changed."}

      error ->
        Reply.outline(error)
    end
  end

  defp distinct(path, path), do: {:error, "old_path and new_path are the same."}
  defp distinct(_from, _to), do: :ok

  defp renamable(note, true = _new_slug?, path) do
    if Note.name(note.text),
      do: :ok,
      else:
        {:error,
         "#{MemoryPath.to_string(path)} has no header line with a name, so its slug comes from " <>
           "the title; add the header line before changing the slug. Nothing changed."}
  end

  defp renamable(_note, false, _path), do: :ok

  defp section(%Document{title: title, text: text}, typ, named, deps) do
    result =
      if title == deps.global_hub,
        do: Hub.cross_project_section(text, named),
        else: Hub.project_section(text, named, Map.get(deps.sections, typ))

    case result do
      {:ok, section} ->
        {:ok, section}

      {:error, :unnamed} ->
        {:error,
         "Name the section of #{MemoryPath.hub(title)} for the link in `section`. " <>
           sections(text)}

      {:error, :unknown} ->
        {:error, "No section #{inspect(named)} in #{MemoryPath.hub(title)}. " <> sections(text)}
    end
  end

  defp sections(text) do
    case Hub.sections(text) do
      [] -> "It has no sections. Nothing changed."
      sections -> "Sections: #{Enum.join(sections, ", ")}. Nothing changed."
    end
  end

  defp target(hub, hub, _note, nil, _deps), do: {:ok, nil}

  defp target(hub, hub, _note, _section, _deps),
    do:
      {:error, "section applies only when rename moves the note to another hub. Nothing changed."}

  defp target(_from_hub, to_hub, note, section, deps) do
    with {:ok, hub} <- Lookup.document({:hub, to_hub}, deps),
         {:ok, section} <- section(hub, Note.typ(note.text), section, deps) do
      {:ok, {hub, section}}
    end
  end

  defp put_slug(note, {:note, _hub, slug}, slug, _deps), do: {:ok, note, []}

  defp put_slug(note, from, slug, deps) do
    rename = fn text ->
      case Note.put_name(text, slug) do
        {index, line} -> Edit.replace_line(text, index, line)
        nil -> {:error, "The note's header line changed; nothing changed. View it and retry."}
      end
    end

    Lookup.gone(Write.run(note.id, rename, deps, check_format: true, stamp: true), from, deps)
  end

  defp move(_note, nil, _current, _deps), do: :ok

  defp move(note, {hub, _section}, current, deps) do
    with {:error, message} <- Reply.outline(deps.outline.move_document(note.id, hub.id)) do
      {:error,
       "Not moved to #{MemoryPath.hub(hub.title)}: #{message} " <>
         "The note is at #{MemoryPath.to_string(current)}."}
    end
  end

  defp relink(_from_hub, nil, _note, _deps), do: []

  defp relink(from_hub, {hub, section}, note, deps),
    do: link(hub, section, note, note.text, deps) ++ unlink(from_hub, note, deps)

  defp link(hub, section, document, text, deps) do
    line = Hub.link(document, Note.summary(text))

    case Reply.outline(Write.run(hub.id, &Hub.add_link(&1, section, line), deps, @hub_edit)) do
      {:ok, _hub, _warnings} ->
        if section in Hub.sections(hub.text),
          do: [],
          else: [
            "Warning: added new section #{inspect(section)} to #{MemoryPath.hub(hub.title)}."
          ]

      {:error, message} ->
        ["Warning: no link added to #{MemoryPath.hub(hub.title)}: #{message}"]
    end
  end

  defp unlink(hub_name, note, deps) do
    with {:ok, hub} <- Lookup.entry({:hub, hub_name}, deps),
         {:ok, _hub, _warnings} <-
           Reply.outline(Write.run(hub.id, &Hub.remove_link(&1, note.url_id), deps, @hub_edit)) do
      []
    else
      {:error, message} ->
        ["Warning: no link removed from #{MemoryPath.hub(hub_name)}: #{message}"]
    end
  end

  defp similar(title, text, deps) do
    case Similar.paths(title <> " " <> (Note.summary(text) || ""), deps) do
      [] -> []
      paths -> ["Similar notes: " <> Enum.join(paths, ", ")]
    end
  end

  defp childless(note, path, deps) do
    case Reply.outline(deps.outline.list_documents(note.id)) do
      {:ok, []} ->
        :ok

      {:ok, children} ->
        {:error,
         "#{MemoryPath.to_string(path)} has #{length(children)} nested documents; " <>
           "move or delete them first. Nothing changed."}

      error ->
        error
    end
  end
end
