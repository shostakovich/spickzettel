defmodule Spickzettel.View do
  @moduledoc "Renders hubs and notes as compact Markdown."

  alias Spickzettel.{Document, MemoryPath, Note}

  @spec hubs([Document.t()]) :: String.t()
  def hubs(hubs) do
    lines(["# /memories" | Enum.map(hubs, &("- " <> labelled(&1)))])
  end

  @spec hub(Document.t(), [Document.t()]) :: String.t()
  def hub(hub, notes) do
    entries =
      notes
      |> Enum.map(&{&1, Note.stand(&1.text)})
      |> Enum.sort_by(fn {note, _stand} -> String.downcase(note.title) end)
      |> Enum.sort_by(fn {_note, stand} -> stand end, :desc)
      |> Enum.map(fn {note, stand} -> entry(note, stand) end)

    lines(["# #{labelled(hub)} · #{MemoryPath.hub(hub.title)}" | entries])
  end

  @spec note(Document.t()) :: String.t()
  def note(note), do: "# #{labelled(note)}\n" <> String.trim_trailing(note.text)

  defp entry(note, stand) do
    details = Enum.reject([labelled(note), Note.slug(note), stand], &is_nil/1)

    case Note.summary(note.text) do
      nil -> "- " <> Enum.join(details, " · ")
      summary -> "- " <> Enum.join(details, " · ") <> " — " <> summary
    end
  end

  defp labelled(%Document{icon: nil, title: title}), do: title
  defp labelled(%Document{icon: "", title: title}), do: title
  defp labelled(%Document{icon: icon, title: title}), do: icon <> " " <> title

  defp lines(lines), do: Enum.join(lines, "\n")
end
