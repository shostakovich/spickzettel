defmodule Spickzettel.Memory do
  @moduledoc "The `memory` tool."

  @behaviour Spickzettel.Tool

  import Spickzettel.MemoryPath, only: [is_note: 1]

  alias Spickzettel.{MemoryPath, Note, View}

  @commands ["view"]

  @impl true
  def definition do
    %{
      name: "memory",
      description:
        "Read the user's long-term memory. `view` a path: /memories lists the hubs, " <>
          "/memories/<hub> lists a hub's notes, /memories/<hub>/<slug> shows a note. " <>
          "Narrow a note with `section` (a heading) or `view_range` (lines of the note below its title).",
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
          }
        },
        required: ["command", "path"]
      }
    }
  end

  @impl true
  def call(arguments), do: call(arguments, index: Spickzettel.Index, outline: Spickzettel.Outline)

  @spec call(map(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def call(%{"command" => "view"} = arguments, deps) do
    with {:ok, path} <- fetch_path(arguments),
         {:ok, scope} <- fetch_scope(arguments) do
      view(path, scope, Map.new(deps))
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

  defp view({:hub, name}, :all, deps) do
    with {:ok, hub} <-
           found(
             deps.index.lookup(name, nil),
             "No hub at #{MemoryPath.hub(name)}. View /memories to list the hubs."
           ),
         {:ok, notes} <- outline_result(deps.outline.list_documents(hub.id)) do
      {:ok, View.hub(hub, notes)}
    end
  end

  defp view({:note, hub, slug}, scope, deps) do
    path = MemoryPath.hub(hub) <> "/" <> slug
    missing = "No note at #{path}. View #{MemoryPath.hub(hub)} to list its notes."

    with {:ok, %{id: id}} <- found(deps.index.lookup(hub, slug), missing),
         {:ok, note} <- fetch_note(deps, id, missing) do
      narrow(note, scope, path)
    end
  end

  defp fetch_note(deps, id, missing) do
    case deps.outline.get_document(id) do
      {:error, :not_found} ->
        deps.index.refresh()
        {:error, missing}

      result ->
        outline_result(result)
    end
  end

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

  defp outline_result({:ok, value}), do: {:ok, value}

  defp outline_result({:error, {:status, status}}),
    do: {:error, "Outline answered with status #{status}."}

  defp outline_result({:error, %{__exception__: true} = exception}),
    do: {:error, "Outline is unreachable: #{Exception.message(exception)}"}

  defp outline_result({:error, reason}),
    do: {:error, "Outline request failed: #{inspect(reason)}"}
end
