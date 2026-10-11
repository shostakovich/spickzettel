defmodule Spickzettel.SessionStartTest do
  use ExUnit.Case, async: true

  import Mox

  alias Spickzettel.{Document, IndexMock, OutlineMock, SessionStart}

  setup :verify_on_exit!

  @deps [index: IndexMock, outline: OutlineMock, global_hub: "General"]
  @global %Document{id: "hub-general", title: "General", icon: "📒", text: nil}
  @project %Document{id: "hub-project", title: "spickzettel", text: nil}
  @long String.duplicate("x", 200)

  defp note(n, stand, padding \\ "") do
    %Document{
      id: "note-#{n}",
      title: String.trim("Note #{n} #{padding}"),
      text: "`name: note-#{n}` · `typ: project` · `stand: #{stand}`\n\n**Kurz:** Short."
    }
  end

  defp shown(text, hub) do
    text
    |> String.split("\n\n")
    |> Enum.find(&String.contains?(&1, "· /memories/#{hub}\n"))
    |> then(&length(Regex.scan(~r/^- Note \d+ /m, &1)))
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

  test "renders the cross-project hub, then the project hub, without summaries" do
    hubs([note(1, "2026-10-01")], [note(2, "2026-10-02")])

    assert SessionStart.text("spickzettel", @deps) ==
             {:ok,
              """
              Memory hubs, loaded at session start; view their notes with the memory tool.

              # 📒 General · /memories/General
              - Note 1 · note-1 · 2026-10-01

              # spickzettel · /memories/spickzettel
              - Note 2 · note-2 · 2026-10-02
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

  test "shortens the longer hub over budget, oldest notes first" do
    project_notes = for n <- 1..60, do: note(n, Date.add(~D[2026-01-01], n), @long)
    hubs([note(0, "2026-10-01")], project_notes)

    assert {:ok, text} = SessionStart.text("spickzettel", @deps)

    assert utf16_length(text) < 10_000
    assert text =~ "- Note 0 · note-0"
    assert text =~ "· note-60 ·"
    refute text =~ "· note-1 ·"

    shown = shown(text, "spickzettel")
    assert text =~ ~r/\n- … #{60 - shown} more notes: memory view \/memories\/spickzettel\n$/
  end

  test "keeps a small project hub complete while the big cross-project hub is shortened" do
    global_notes = for n <- 1..60, do: note(n, Date.add(~D[2026-01-01], n), @long)
    hubs(global_notes, for(n <- 61..63, do: note(n, "2026-10-01")))

    assert {:ok, text} = SessionStart.text("spickzettel", @deps)

    assert utf16_length(text) < 10_000
    assert shown(text, "spickzettel") == 3
    refute text =~ "memory view /memories/spickzettel"
    assert text =~ "· note-60 ·"
    refute text =~ "· note-1 ·"

    shown = shown(text, "General")
    assert text =~ "\n- … #{60 - shown} more notes: memory view /memories/General\n\n"
  end

  test "shortens both hubs alike when both are big" do
    hubs(
      for(n <- 1..60, do: note(n, "2026-10-01", @long)),
      for(n <- 61..120, do: note(n, "2026-10-01", @long))
    )

    assert {:ok, text} = SessionStart.text("spickzettel", @deps)

    assert utf16_length(text) < 10_000
    assert text =~ "more notes: memory view /memories/General\n"
    assert text =~ "more notes: memory view /memories/spickzettel\n"
    assert abs(shown(text, "General") - shown(text, "spickzettel")) <= 1
  end

  test "counts the budget in UTF-16 code units, in which an emoji takes two" do
    emoji = String.duplicate("🧪", 120)
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
