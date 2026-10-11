defmodule Spickzettel.Memory do
  @moduledoc "The `memory` tool."

  @behaviour Spickzettel.Tool

  import Spickzettel.MemoryPath, only: [is_note: 1]

  alias Spickzettel.{DreamLog, Edit, Lifecycle, Lookup, MemoryPath, Note, Reply, View, Write}

  @commands ["view", "create", "str_replace", "insert", "delete", "rename", "confirm"]
  @edits ["str_replace", "insert", "confirm"]

  @impl true
  def definition do
    %{
      name: "memory",
      description:
        "Read and edit the user's long-term memory. `view` a path: /memories lists the hubs, " <>
          "/memories/<hub> lists a hub's notes, /memories/<hub>/<slug> shows a note. " <>
          "Narrow a note with `section` (a heading) or `view_range` (lines of the note below its title). " <>
          "`create` makes the note at `path` from `title`, `typ`, `file_text` (the summary line of " <>
          "at most 160 characters and content; the server adds the header line) and an optional " <>
          "emoji `icon`, and links it in its " <>
          "hub under the section for its typ, or under `section`, which `user` notes, pitfalls and the " <>
          "cross-project hub require; " <>
          "it reports similar notes. `create` at /memories/<hub> makes a project hub described by " <>
          "`file_text` and links it under `section` of the cross-project hub. " <>
          "`str_replace` replaces the unique `old_str` with `new_str`; `insert` adds `insert_text` " <>
          "after line `insert_line`, counted below the title like `view_range` (0 for the top); " <>
          "both work on notes and hubs and set the note's stand. " <>
          "`rename` moves a note from `old_path` to `new_path`, to a new slug, hub or both; `delete` " <>
          "removes a note. Both keep the hubs' links in sync. " <>
          "`confirm` counts one more session in a note's evidence line when the note proved right.",
      inputSchema: %{
        type: "object",
        properties: %{
          command: %{type: "string", enum: @commands},
          path: %{
            type: "string",
            description: "/memories, /memories/<hub> or /memories/<hub>/<slug>"
          },
          section: %{
            type: "string",
            description:
              "view: heading of the section to show; create, rename: hub section for the link"
          },
          view_range: %{
            type: "array",
            items: %{type: "integer"},
            minItems: 2,
            maxItems: 2,
            description: "[first, last] line, 1-based; last -1 means to the end"
          },
          title: %{type: "string", description: "Short, specific title of the new note"},
          typ: %{type: "string", enum: Spickzettel.NoteFormat.typs()},
          icon: %{type: "string", description: "Emoji hinting at the topic"},
          file_text: %{type: "string", description: "Summary line and content of the new note"},
          old_str: %{type: "string", description: "Text to replace; must occur exactly once"},
          new_str: %{type: "string", description: "Replacement text"},
          insert_line: %{
            type: "integer",
            description:
              "Line to insert after, 1-based below the title like view_range; 0 inserts at the top"
          },
          insert_text: %{
            type: "string",
            description:
              "Markdown to insert; separate paragraphs with a blank line, also from the lines around it"
          },
          old_path: %{type: "string", description: "/memories/<hub>/<slug> of the note to rename"},
          new_path: %{type: "string", description: "Its new /memories/<hub>/<slug>"}
        },
        required: ["command"]
      }
    }
  end

  @impl true
  def call(arguments),
    do: call(arguments, index: Spickzettel.Index, outline: Spickzettel.Outline, today: &today/0)

  @spec call(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def call(arguments, deps),
    do: run(without_nils(arguments), Map.merge(settings(), Map.new(deps)))

  defp run(%{"command" => "view"} = arguments, deps) do
    with {:ok, path} <- fetch_path(arguments),
         {:ok, scope} <- fetch_scope(arguments) do
      view(path, scope, deps)
    end
  end

  defp run(%{"command" => "create"} = arguments, deps) do
    with {:ok, path} <- fetch_path(arguments),
         {:ok, new} <- fetch_new(arguments) do
      if path == :root,
        do: {:error, "create applies to notes and hubs only."},
        else: Lifecycle.create(path, new, deps)
    end
  end

  defp run(%{"command" => "rename"} = arguments, deps) do
    with {:ok, from} <- fetch_path(arguments, "old_path"),
         {:ok, to} <- fetch_path(arguments, "new_path"),
         {:ok, section} <- fetch_optional(arguments, "section") do
      if is_note(from) and is_note(to),
        do: Lifecycle.rename(from, to, section, deps),
        else: {:error, "rename applies to notes only."}
    end
  end

  defp run(%{"command" => "delete"} = arguments, deps) do
    with {:ok, path} <- fetch_path(arguments) do
      if is_note(path),
        do: Lifecycle.delete(path, deps),
        else: {:error, "delete applies to notes only."}
    end
  end

  defp run(%{"command" => command} = arguments, deps) when command in @edits do
    with {:ok, path} <- fetch_path(arguments),
         {:ok, edit} <- fetch_edit(command, arguments, deps) do
      write(path, command, edit, deps)
    end
  end

  defp run(%{"command" => command}, _deps) when is_binary(command),
    do: {:error, "Unknown command #{inspect(command)}. Commands: #{Enum.join(@commands, ", ")}."}

  defp run(_arguments, _deps),
    do: {:error, "Missing command. Commands: #{Enum.join(@commands, ", ")}."}

  defp without_nils(arguments) when is_map(arguments),
    do: Map.reject(arguments, fn {_key, value} -> is_nil(value) end)

  defp without_nils(arguments), do: arguments

  defp settings do
    config = Application.get_all_env(:spickzettel)

    %{
      global_hub: config[:global_hub],
      sections: Map.new(config[:sections], fn {typ, section} -> {to_string(typ), section} end),
      dream_log: config[:dream_log],
      dream_log_archive: config[:dream_log_archive]
    }
  end

  defp fetch_path(arguments, key \\ "path") do
    case Map.get(arguments, key) do
      path when is_binary(path) -> parse_path(path, key)
      _missing -> {:error, "Missing #{key}."}
    end
  end

  defp parse_path(path, key) do
    case MemoryPath.parse(path) do
      {:ok, parsed} ->
        {:ok, parsed}

      :error ->
        {:error,
         "Invalid #{key} #{inspect(path)}. Use /memories, /memories/<hub> or /memories/<hub>/<slug>."}
    end
  end

  defp fetch_new(arguments) do
    with {:ok, title} <- fetch_optional(arguments, "title"),
         {:ok, typ} <- fetch_optional(arguments, "typ"),
         {:ok, icon} <- fetch_optional(arguments, "icon"),
         {:ok, section} <- fetch_optional(arguments, "section") do
      case arguments do
        %{"file_text" => text} when is_binary(text) ->
          {:ok, %{title: title, typ: typ, icon: icon, text: text, section: section}}

        _arguments ->
          {:error, "create needs file_text as string."}
      end
    end
  end

  defp fetch_optional(arguments, key) do
    case Map.get(arguments, key) do
      nil -> {:ok, nil}
      value when is_binary(value) -> {:ok, present(String.trim(value))}
      _value -> {:error, "#{key} must be a string."}
    end
  end

  defp present(""), do: nil
  defp present(value), do: value

  defp fetch_edit("str_replace", %{"old_str" => old, "new_str" => new}, _deps)
       when is_binary(old) and is_binary(new),
       do: {:ok, &Edit.str_replace(&1, old, new)}

  defp fetch_edit("insert", %{"insert_line" => line, "insert_text" => text}, _deps)
       when is_integer(line) and is_binary(text),
       do: {:ok, &Edit.insert(&1, line, text)}

  defp fetch_edit("confirm", _arguments, deps),
    do: {:ok, &Edit.confirm(&1, deps.today.())}

  defp fetch_edit("str_replace", _arguments, _deps),
    do: {:error, "str_replace needs old_str and new_str as strings."}

  defp fetch_edit("insert", _arguments, _deps),
    do: {:error, "insert needs insert_line as integer and insert_text as string."}

  defp fetch_scope(%{"section" => _, "view_range" => _}),
    do: {:error, "Use either section or view_range, not both."}

  defp fetch_scope(%{"section" => section}) when is_binary(section) and section != "",
    do: {:ok, {:section, section}}

  defp fetch_scope(%{"section" => _}), do: {:error, "section must be a heading."}

  defp fetch_scope(%{"view_range" => [first, last]})
       when is_integer(first) and is_integer(last) and first >= 1 and
              (last == -1 or last >= first),
       do: {:ok, {:range, first, last}}

  defp fetch_scope(%{"view_range" => _}),
    do: {:error, "view_range must be [first, last] with 1 <= first <= last, or last = -1."}

  defp fetch_scope(_arguments), do: {:ok, :all}

  defp view(path, scope, _deps) when scope != :all and not is_note(path),
    do: {:error, "section and view_range apply to notes only."}

  defp view(:root, :all, deps) do
    with {:ok, hubs} <- Reply.outline(deps.index.hubs()) do
      {:ok, View.hubs(hubs)}
    end
  end

  defp view({:hub, _name} = path, :all, deps) do
    with {:ok, hub, notes} <- Lookup.hub(path, deps), do: {:ok, View.hub(hub, notes)}
  end

  defp view({:note, _hub, _slug} = path, scope, deps) do
    with {:ok, note} <- Lookup.document(path, deps) do
      narrow(note, scope, MemoryPath.to_string(path))
    end
  end

  defp write(path, "confirm", _edit, _deps) when not is_note(path),
    do: {:error, "confirm applies to notes only."}

  defp write(:root, command, _edit, _deps),
    do: {:error, "#{command} applies to notes and hubs only."}

  defp write(path, command, edit, deps) do
    options = [
      check_format: is_note(path),
      check_length: path != deps.dream_log,
      stamp: command != "confirm"
    ]

    with {:ok, entry} <- Lookup.entry(path, deps),
         edit = keep_slug(path, entry, command, edit),
         {:ok, written, warnings} <-
           Lookup.gone(Write.run(entry.id, edit, deps, options), path, deps) do
      archived = DreamLog.archive(path, written, deps)
      deps.index.refresh()
      {:ok, Reply.written(written_path(path, written), written, warnings ++ archived)}
    end
  end

  defp keep_slug({:note, _hub, _slug}, entry, command, edit) when command != "confirm" do
    fn text ->
      with {:ok, patch} <- edit.(text) do
        if Note.slug(%{entry | text: Edit.apply(text, patch)}) == Note.slug(%{entry | text: text}),
          do: {:ok, patch},
          else:
            {:error,
             "#{command} must not change the note's name, which is its slug; use rename. Nothing changed."}
      end
    end
  end

  defp keep_slug(_path, _entry, _command, edit), do: edit

  defp written_path({:note, hub, _slug}, document),
    do: MemoryPath.to_string({:note, hub, Note.slug(document)})

  defp written_path(hub, _document), do: MemoryPath.to_string(hub)

  defp today, do: NaiveDateTime.local_now() |> NaiveDateTime.to_date()

  defp narrow(note, :all, _path), do: {:ok, View.note(note)}

  defp narrow(note, {:section, section}, path) do
    case Note.section(note.text, section) do
      {:ok, text} ->
        {:ok, text}

      :error ->
        {:error, "No section #{inspect(section)} in #{path}. " <> sections(note.text)}
    end
  end

  defp narrow(note, {:range, first, last}, path) do
    case Note.line_range(note.text, first, last) do
      {:ok, text} -> {:ok, text}
      :error -> {:error, "#{path} has #{Note.line_count(note.text)} lines."}
    end
  end

  defp sections(text) do
    case Note.headings(text) do
      [] -> "It has no sections."
      headings -> "Sections: #{Enum.join(headings, ", ")}."
    end
  end
end
