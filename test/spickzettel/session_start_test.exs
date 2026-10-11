defmodule Spickzettel.SessionStartTest do
  use ExUnit.Case, async: true

  import Mox

  alias Spickzettel.{Document, IndexMock, OutlineMock, SessionStart}

  setup :verify_on_exit!

  @deps [index: IndexMock, outline: OutlineMock, global_hub: "General"]
  @global %Document{id: "hub-general", title: "General", icon: "📒", text: nil}
  @project %Document{id: "hub-project", title: "spickzettel", text: nil}

  defp note(n, stand, summary \\ "Short.") do
    %Document{
      id: "note-#{n}",
      title: "Note #{n}",
      text: "`name: note-#{n}` · `typ: project` · `stand: #{stand}`\n\n**Kurz:** #{summary}"
    }
  end

  defp utf16_length(text),
    do: byte_size(:unicode.characters_to_binary(text, :utf8, :utf16)) |> div(2)

  defp hubs(global_notes, project_notes) do
    stub(IndexMock, :lookup, fn
      "General", nil -> {:ok, @global}
      "spickzettel", nil -> {:ok, @project}
    end)

    stub(OutlineMock, :list_documents, fn
      "hub-general" -> {:ok, global_notes}
      "hub-project" -> {:ok, project_notes}
    end)
  end

  test "renders the cross-project hub, then the project hub" do
    hubs([note(1, "2026-10-01")], [note(2, "2026-10-02")])

    assert SessionStart.text("spickzettel", @deps) ==
             {:ok,
              """
              Memory hubs, loaded at session start; view their notes with the memory tool.

              # 📒 General · /memories/General
              - Note 1 · note-1 · 2026-10-01 — Short.

              # spickzettel · /memories/spickzettel
              - Note 2 · note-2 · 2026-10-02 — Short.
              """}
  end

  test "renders only the cross-project hub and says so without a matching hub" do
    stub(IndexMock, :lookup, fn
      "General", nil -> {:ok, @global}
      "unknown", nil -> {:error, :not_found}
    end)

    expect(OutlineMock, :list_documents, fn "hub-general" -> {:ok, []} end)

    assert SessionStart.text("unknown", @deps) ==
             {:ok,
              """
              Memory hubs, loaded at session start; view their notes with the memory tool.

              # 📒 General · /memories/General

              No hub /memories/unknown, so only the cross-project hub is loaded.
              """}
  end

  test "shortens the project hub's list over budget, oldest notes first" do
    long = String.duplicate("x", 200)
    project_notes = for n <- 1..60, do: note(n, Date.add(~D[2026-01-01], n), long)
    hubs([note(0, "2026-10-01")], project_notes)

    assert {:ok, text} = SessionStart.text("spickzettel", @deps)

    assert utf16_length(text) < 10_000
    assert text =~ "- Note 0 · note-0"
    assert text =~ "- Note 60 · note-60"
    refute text =~ "- Note 1 · note-1 "

    shown = length(Regex.scan(~r/^- Note \d+ · /m, text)) - 1
    assert text =~ ~r/\n- … #{60 - shown} more notes: memory view \/memories\/spickzettel\n$/
  end

  test "shortens the cross-project hub too when it alone is over budget" do
    long = String.duplicate("x", 200)
    hubs(for(n <- 1..60, do: note(n, "2026-10-01", long)), [note(61, "2026-10-01")])

    assert {:ok, text} = SessionStart.text("spickzettel", @deps)

    assert utf16_length(text) < 10_000
    assert text =~ ~r/\n- … \d+ more notes: memory view \/memories\/General\n/
    assert text =~ "\n- … 1 more note: memory view /memories/spickzettel\n"
  end

  test "counts the budget in UTF-16 code units, in which an emoji takes two" do
    emoji = String.duplicate("🧪", 100)
    hubs([note(0, "2026-10-01")], for(n <- 1..60, do: note(n, "2026-10-01", emoji)))

    assert {:ok, text} = SessionStart.text("spickzettel", @deps)

    assert utf16_length(text) < 10_000
    assert text =~ ~r/more notes: memory view \/memories\/spickzettel\n$/
  end

  test "fails when Outline fails" do
    stub(IndexMock, :lookup, fn "General", nil -> {:error, {:status, 500}} end)

    assert SessionStart.text("spickzettel", @deps) ==
             {:error, "Outline answered with status 500."}
  end
end
