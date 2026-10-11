defmodule Spickzettel.Memory do
  @moduledoc "The `memory` tool."

  @behaviour Spickzettel.Tool

  import Spickzettel.MemoryPath, only: [is_note: 1]

  alias Spickzettel.{Edit, MemoryPath, Note, View, Write}

  @commands ["view", "str_replace", "insert", "confirm"]

  @impl true
  def definition do
    %{
      name: "memory",
      description:
        "Read and edit the user's long-term memory. `view` a path: /memories lists the hubs, " <>
          "/memories/<hub> lists a hub's notes, /memories/<hub>/<slug> shows a note. " <>
          "Narrow a note with `section` (a heading) or `view_range` (lines of the note below its title). " <>
          "`str_replace` replaces the unique `old_str` with `new_str`; `insert` adds `insert_text` " <>
          "after line `insert_line`, counted below the title like `view_range` (0 for the top); " <>
          "both work on notes and hubs and set the note's stand. " <>
          "`confirm` counts one more session in a note's evidence line when the note proved right.",
      inputSchema: %{
        type: "object",
        properties: %{
          command: %{type: "string", enum: @commands},
          path: %{
            type: "string",
            description: "/memories, /memories/<hub> or /memories/<hub>/<slug>"
          },
          section: %{type: "string", description: "Heading of the section to show"},
          view_range: %{
            type: "array",
            items: %{type: "integer"},
            minItems: 2,
            maxItems: 2,
            description: "[first, last] line, 1-based; last -1 means to the end"
          },
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
          }
        },
        required: ["command", "path"]
      }
    }
  end

  @impl true
  def call(arguments),
    do: call(arguments, index: Spickzettel.Index, outline: Spickzettel.Outline, today: &today/0)

  @spec call(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def call(%{"command" => "view"} = arguments, deps) do
    with {:ok, path} <- fetch_path(arguments),
         {:ok, scope} <- fetch_scope(arguments) do
      view(path, scope, Map.new(deps))
    end
  end

  def call(%{"command" => command} = arguments, deps)
      when command in ["str_replace", "insert", "confirm"] do
    deps = Map.new(deps)

    with {:ok, path} <- fetch_path(arguments),
         {:ok, edit} <- fetch_edit(command, arguments, deps) do
      write(path, command, edit, deps)
    end
  end

  def call(%{"command" => command}, _deps) when is_binary(command),
    do: {:error, "Unknown command #{inspect(command)}. Commands: #{Enum.join(@commands, ", ")}."}

  def call(_arguments, _deps),
    do: {:error, "Missing command. Commands: #{Enum.join(@commands, ", ")}."}

  defp fetch_path(%{"path" => path}) when is_binary(path) do
    case MemoryPath.parse(path) do
      {:ok, parsed} ->
        {:ok, parsed}

      :error ->
        {:error,
         "Invalid path #{inspect(path)}. Use /memories, /memories/<hub> or /memories/<hub>/<slug>."}
    end
  end

  defp fetch_path(_arguments), do: {:error, "Missing path."}

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
    with {:ok, hubs} <- outline_result(deps.index.hubs()) do
      {:ok, View.hubs(hubs)}
    end
  end

  defp view({:hub, _name} = path, :all, deps) do
    with {:ok, hub} <- found(lookup(path, deps), missing(path)),
         {:ok, notes} <- outline_result(deps.outline.list_documents(hub.id)) do
      {:ok, View.hub(hub, notes)}
    end
  end

  defp view({:note, _hub, _slug} = path, scope, deps) do
    with {:ok, %{id: id}} <- found(lookup(path, deps), missing(path)),
         {:ok, note} <- gone(deps.outline.get_document(id), path, deps) do
      narrow(note, scope, MemoryPath.to_string(path))
    end
  end

  defp write(path, "confirm", _edit, _deps) when not is_note(path),
    do: {:error, "confirm applies to notes only."}

  defp write(:root, command, _edit, _deps),
    do: {:error, "#{command} applies to notes and hubs only."}

  defp write(path, command, edit, deps) do
    options = [check_format: match?({:note, _hub, _slug}, path), stamp: command != "confirm"]

    with {:ok, %{id: id}} <- found(lookup(path, deps), missing(path)),
         {:ok, written, warnings} <- gone(Write.run(id, edit, deps, options), path, deps) do
      deps.index.refresh()
      {:ok, written_reply(path, written, warnings)}
    end
  end

  defp lookup({:hub, name}, deps), do: deps.index.lookup(name, nil)
  defp lookup({:note, hub, slug}, deps), do: deps.index.lookup(hub, slug)

  defp written_reply(path, document, warnings) do
    path =
      case path do
        {:note, hub, _slug} -> MemoryPath.to_string({:note, hub, Note.slug(document)})
        hub -> MemoryPath.to_string(hub)
      end

    line = Enum.join(["ok", path | List.wrap(Note.stand(document.text))], " · ")
    Enum.join([line | warnings], "\n")
  end

  defp gone({:error, :not_found}, path, deps) do
    deps.index.refresh()
    {:error, missing(path)}
  end

  defp gone(result, _path, _deps), do: outline_result(result)

  defp missing({:hub, name}),
    do: "No hub at #{MemoryPath.hub(name)}. View /memories to list the hubs."

  defp missing({:note, hub, _slug} = path),
    do: "No note at #{MemoryPath.to_string(path)}. View #{MemoryPath.hub(hub)} to list its notes."

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

  defp found({:error, :not_found}, message), do: {:error, message}
  defp found(result, _message), do: outline_result(result)

  defp outline_result({:ok, _value} = result), do: result
  defp outline_result({:ok, _value, _warnings} = result), do: result
  defp outline_result({:error, message}) when is_binary(message), do: {:error, message}

  defp outline_result({:error, {:rejected, message}}),
    do: {:error, "Outline rejected the edit (#{message}); nothing changed."}

  defp outline_result({:error, {:status, status}}),
    do: {:error, "Outline answered with status #{status}."}

  defp outline_result({:error, %{__exception__: true} = exception}),
    do: {:error, "Outline is unreachable: #{Exception.message(exception)}"}

  defp outline_result({:error, reason}),
    do: {:error, "Outline request failed: #{inspect(reason)}"}
end
