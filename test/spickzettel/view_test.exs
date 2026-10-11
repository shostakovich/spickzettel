defmodule Spickzettel.ViewTest do
  use ExUnit.Case, async: true

  alias Spickzettel.{Document, View}

  defp note(title, icon, text), do: %Document{id: title, title: title, icon: icon, text: text}

  test "lists the hubs" do
    hubs = [note("General", "📒", nil), note("spickzettel", nil, nil)]

    assert View.hubs(hubs) == "# /memories\n- 📒 General\n- spickzettel"
  end

  test "lists a hub's notes, newest stand first, then by title" do
    hub = note("project", "📝", "Intro.")

    notes = [
      note("b old", nil, "`name: b-old` · `stand: 2026-01-01`\n\n**Kurz:** Old."),
      note("Undated", "📎", "No header here."),
      note("a new", "🧪", "`name: a-new` · `stand: 2026-10-09`\n\n**Kurz:** New."),
      note("A also new", nil, "`name: also` · `stand: 2026-10-09`\n")
    ]

    assert View.hub(hub, notes) == """
           # 📝 project · /memories/project
           - A also new · also · 2026-10-09
           - 🧪 a new · a-new · 2026-10-09 — New.
           - b old · b-old · 2026-01-01 — Old.
           - 📎 Undated · undated — No header here.\
           """
  end

  test "gives a hub's heading and entries as lines" do
    hub = note("project", nil, "")
    notes = [note("Tests", nil, "`name: tests` · `stand: 2026-10-09`\n\n**Kurz:** Fast.")]

    assert View.hub_lines(hub, notes) ==
             ["# project · /memories/project", "- Tests · tests · 2026-10-09 — Fast."]
  end

  test "leaves out the summaries on request" do
    hub = note("project", nil, "")
    notes = [note("Tests", "🧪", "`name: tests` · `stand: 2026-10-09`\n\n**Kurz:** Fast.")]

    assert View.hub_lines(hub, notes, summary: false) ==
             ["# project · /memories/project", "- 🧪 Tests · tests · 2026-10-09"]
  end

  test "shows a hub without notes as its heading" do
    assert View.hub(note("empty", nil, ""), []) == "# empty · /memories/empty"
  end

  test "shows a note with its title" do
    assert View.note(note("Tests", "🧪", "`name: tests`\n\nBody.\n\n")) ==
             "# 🧪 Tests\n`name: tests`\n\nBody."
  end
end
