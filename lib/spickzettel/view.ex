defmodule Spickzettel.View do
  @moduledoc "Renders hubs and notes as compact Markdown."

  alias Spickzettel.{Document, MemoryPath, Note}

  @spec hubs([Document.t()]) :: String.t()
  def hubs(hubs) do
    lines(["# /memories" | Enum.map(hubs, &("- " <> labelled(&1)))])
  end

  @spec hub(Document.t(), [Document.t()]) :: String.t()
  def hub(hub, notes), do: lines(hub_lines(hub, notes))

  @doc """
  The hub's heading, then one line per note, newest `stand` first. `summary: false` leaves out
  the notes' summaries.
  """
  @spec hub_lines(Document.t(), [Document.t()], keyword()) :: [String.t()]
  def hub_lines(hub, notes, options \\ []) do
    summary? = Keyword.get(options, :summary, true)

    entries =
      notes
      |> Enum.map(&{&1, Note.stand(&1.text)})
      |> Enum.sort_by(fn {note, _stand} -> String.downcase(note.title) end)
      |> Enum.sort_by(fn {_note, stand} -> stand end, :desc)
      |> Enum.map(fn {note, stand} -> entry(note, stand, summary?) end)

    ["# #{labelled(hub)} · #{MemoryPath.hub(hub.title)}" | entries]
  end

  @spec note(Document.t()) :: String.t()
  def note(note), do: "# #{labelled(note)}\n" <> String.trim_trailing(note.text)

  defp entry(note, stand, summary?) do
    details = Enum.reject([labelled(note), Note.slug(note), stand], &is_nil/1)
    line = "- " <> Enum.join(details, " · ")

    case summary? && Note.summary(note.text) do
      summary when is_binary(summary) -> line <> " — " <> summary
      _none -> line
    end
  end

  defp labelled(%Document{icon: nil, title: title}), do: title
  defp labelled(%Document{icon: "", title: title}), do: title
  defp labelled(%Document{icon: icon, title: title}), do: icon <> " " <> title

  defp lines(lines), do: Enum.join(lines, "\n")
end
