defmodule Spickzettel.MemoryTest do
  use ExUnit.Case, async: true

  import Mox

  alias Spickzettel.{Document, Edit, IndexMock, Memory, OutlineMock}

  setup :verify_on_exit!

  @deps [index: IndexMock, outline: OutlineMock]
  @hub %Document{id: "hub-1", title: "project", icon: "📝", text: nil}
  @note %Document{
    id: "note-1",
    title: "Tests",
    icon: "🧪",
    parent_id: "hub-1",
    text: "`name: tests` · `stand: 2026-10-09`\n\n**Kurz:** Fast.\n\n## Mocks\n\nMox.\n"
  }

  defp view(arguments), do: Memory.call(Map.put(arguments, "command", "view"), @deps)

  test "defines the memory tool with its commands" do
    definition = Memory.definition()

    assert definition.name == "memory"

    assert definition.inputSchema.properties.command.enum ==
             ["view", "str_replace", "insert", "confirm"]
  end

  test "says that insert_line counts lines below the title, like view_range" do
    definition = Memory.definition()

    assert definition.description =~ "`insert_line`, counted below the title like `view_range`"
    assert definition.inputSchema.properties.insert_line.description =~ "below the title"
  end

  test "says that insert_text is Markdown with paragraphs separated by blank lines" do
    assert Memory.definition().inputSchema.properties.insert_text.description =~
             "Markdown to insert; separate paragraphs with a blank line"
  end

  test "lists the hubs at /memories" do
    expect(IndexMock, :hubs, fn -> {:ok, [@hub]} end)

    assert view(%{"path" => "/memories"}) == {:ok, "# /memories\n- 📝 project"}
  end

  test "lists a hub's notes" do
    expect(IndexMock, :lookup, fn "project", nil -> {:ok, @hub} end)
    expect(OutlineMock, :list_documents, fn "hub-1" -> {:ok, [@note]} end)

    assert view(%{"path" => "/memories/project"}) ==
             {:ok, "# 📝 project · /memories/project\n- 🧪 Tests · tests · 2026-10-09 — Fast."}
  end

  test "shows a note in full" do
    expect(IndexMock, :lookup, fn "project", "tests" -> {:ok, %{@note | text: nil}} end)
    expect(OutlineMock, :get_document, fn "note-1" -> {:ok, @note} end)

    assert {:ok, "# 🧪 Tests\n`name: tests`" <> _} = view(%{"path" => "/memories/project/tests"})
  end

  test "shows a section of a note" do
    stub(IndexMock, :lookup, fn "project", "tests" -> {:ok, @note} end)
    stub(OutlineMock, :get_document, fn "note-1" -> {:ok, @note} end)

    assert view(%{"path" => "/memories/project/tests", "section" => "Mocks"}) ==
             {:ok, "## Mocks\n\nMox."}

    assert view(%{"path" => "/memories/project/tests", "section" => "Other"}) ==
             {:error, ~s(No section "Other" in /memories/project/tests. Sections: Mocks.)}
  end

  test "shows a line range of a note" do
    stub(IndexMock, :lookup, fn "project", "tests" -> {:ok, @note} end)
    stub(OutlineMock, :get_document, fn "note-1" -> {:ok, @note} end)

    assert view(%{"path" => "/memories/project/tests", "view_range" => [3, 3]}) ==
             {:ok, "**Kurz:** Fast."}

    assert view(%{"path" => "/memories/project/tests", "view_range" => [9, -1]}) ==
             {:error, "/memories/project/tests has 7 lines."}
  end

  test "reports unknown hubs and notes" do
    stub(IndexMock, :lookup, fn _hub, _slug -> {:error, :not_found} end)

    assert view(%{"path" => "/memories/nope"}) ==
             {:error, "No hub at /memories/nope. View /memories to list the hubs."}

    assert view(%{"path" => "/memories/nope/x"}) ==
             {:error, "No note at /memories/nope/x. View /memories/nope to list its notes."}
  end

  test "refreshes the index when a known note is gone in Outline" do
    expect(IndexMock, :lookup, fn "project", "tests" -> {:ok, @note} end)
    expect(OutlineMock, :get_document, fn "note-1" -> {:error, :not_found} end)
    expect(IndexMock, :refresh, fn -> :ok end)

    assert {:error, "No note at /memories/project/tests." <> _} =
             view(%{"path" => "/memories/project/tests"})
  end

  test "reports Outline failures" do
    expect(IndexMock, :hubs, fn -> {:error, {:status, 500}} end)

    expect(IndexMock, :lookup, fn "project", nil ->
      {:error, %Req.TransportError{reason: :econnrefused}}
    end)

    assert view(%{"path" => "/memories"}) == {:error, "Outline answered with status 500."}

    assert view(%{"path" => "/memories/project"}) ==
             {:error, "Outline is unreachable: connection refused"}
  end

  test "rejects invalid arguments" do
    assert Memory.call(%{}, @deps) ==
             {:error, "Missing command. Commands: view, str_replace, insert, confirm."}

    assert Memory.call(%{"command" => "create"}, @deps) ==
             {:error, ~s(Unknown command "create". Commands: view, str_replace, insert, confirm.)}

    assert view(%{}) == {:error, "Missing path."}
    assert {:error, "Invalid path \"/notes\"." <> _} = view(%{"path" => "/notes"})

    assert view(%{"path" => "/memories/p/n", "section" => "A", "view_range" => [1, 2]}) ==
             {:error, "Use either section or view_range, not both."}

    assert view(%{"path" => "/memories/p/n", "section" => ""}) ==
             {:error, "section must be a heading."}

    for range <- [[0, 2], [3, 2], [1], ["1", "2"]] do
      assert {:error, "view_range must be" <> _} =
               view(%{"path" => "/memories/p/n", "view_range" => range})
    end

    assert view(%{"path" => "/memories/p", "section" => "A"}) ==
             {:error, "section and view_range apply to notes only."}
  end

  describe "writes" do
    @write_deps [index: IndexMock, outline: OutlineMock, today: &__MODULE__.today/0]
    @valid %{
      @note
      | revision: 12,
        text:
          "`name: tests` · `typ: feedback` · `stand: 2026-10-09`\n\n**Kurz:** Fast.\n\n" <>
            "**Why:** Speed.\n\n**How to apply:** Mox.\n"
    }

    def today, do: ~D[2026-10-11]

    defp write(command, arguments) do
      arguments
      |> Map.merge(%{"command" => command, "path" => "/memories/project/tests"})
      |> Memory.call(@write_deps)
    end

    defp patched(document, patch, revision),
      do: %{document | text: Edit.apply(document.text, patch), revision: revision}

    defp found_note(_context) do
      stub(IndexMock, :lookup, fn "project", "tests" -> {:ok, %{@valid | text: nil}} end)
      :ok
    end

    setup :found_note

    test "patches the note, sets stand, refreshes the index and answers in one line" do
      expect(OutlineMock, :get_document, fn "note-1" -> {:ok, @valid} end)

      expect(OutlineMock, :patch_document, fn "note-1", {"Fast.", "Quick."} = patch, 12 ->
        {:ok, patched(@valid, patch, 13)}
      end)

      expect(OutlineMock, :patch_document, fn "note-1", {header, stamped} = patch, 13 ->
        assert header =~ "`stand: 2026-10-09`"
        assert stamped =~ "`stand: 2026-10-11`"
        {:ok, patched(patched(@valid, {"Fast.", "Quick."}, 13), patch, 14)}
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert write("str_replace", %{"old_str" => "Fast.", "new_str" => "Quick."}) ==
               {:ok, "ok · /memories/project/tests · 2026-10-11"}
    end

    test "re-reads the note once on a conflict and fails on a second one" do
      expect(OutlineMock, :get_document, 2, fn "note-1" -> {:ok, @valid} end)
      expect(OutlineMock, :patch_document, 2, fn "note-1", _patch, 12 -> {:error, :conflict} end)

      assert write("str_replace", %{"old_str" => "Fast.", "new_str" => "Quick."}) ==
               {:error,
                "The note changed again while writing; nothing changed. View it and retry."}
    end

    test "answers with the new path when the edit renames the note" do
      renamed = %{@valid | text: String.replace(@valid.text, "name: tests", "name: mocks")}
      expect(OutlineMock, :get_document, fn "note-1" -> {:ok, @valid} end)
      expect(OutlineMock, :patch_document, fn "note-1", _patch, 12 -> {:ok, renamed} end)

      expect(OutlineMock, :patch_document, fn "note-1", _patch, _revision ->
        {:error, :conflict}
      end)

      expect(OutlineMock, :get_document, fn "note-1" -> {:error, {:status, 500}} end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert write("str_replace", %{"old_str" => "name: tests", "new_str" => "name: mocks"}) ==
               {:ok, "ok · /memories/project/mocks · 2026-10-09\nWarning: stand was not updated."}
    end

    test "rejects an edit that makes a valid note invalid without writing" do
      expect(OutlineMock, :get_document, fn "note-1" -> {:ok, @valid} end)

      assert write("str_replace", %{"old_str" => "**Why:** Speed.\n\n", "new_str" => ""}) ==
               {:error,
                "Rejected: the note would become invalid: no **Why:** line. Nothing changed."}
    end

    test "warns about long notes" do
      long = %{@valid | text: @valid.text <> String.duplicate("x", 15_000)}
      expect(OutlineMock, :get_document, fn "note-1" -> {:ok, long} end)

      expect(OutlineMock, :patch_document, 2, fn "note-1", patch, revision ->
        {:ok, patched(long, patch, revision + 1)}
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert {:ok, "ok · /memories/project/tests · 2026-10-11\nWarning: the note has 15" <> _} =
               write("str_replace", %{"old_str" => "Fast.", "new_str" => "Quick."})
    end

    test "confirm leaves stand alone" do
      expect(OutlineMock, :get_document, fn "note-1" -> {:ok, @valid} end)

      expect(OutlineMock, :patch_document, fn "note-1", {_find, replace} = patch, 12 ->
        assert replace =~ "**Evidence:** 1 session, last 2026-10-11"
        {:ok, patched(@valid, patch, 13)}
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert write("confirm", %{}) == {:ok, "ok · /memories/project/tests · 2026-10-09"}
    end

    test "edits hubs without a format check" do
      hub = %{@hub | revision: 2, text: "Hub links.\n"}
      expect(IndexMock, :lookup, fn "project", nil -> {:ok, hub} end)
      expect(OutlineMock, :get_document, fn "hub-1" -> {:ok, hub} end)

      expect(OutlineMock, :patch_document, fn "hub-1", patch, 2 ->
        {:ok, patched(hub, patch, 3)}
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert Memory.call(
               %{
                 "command" => "str_replace",
                 "path" => "/memories/project",
                 "old_str" => "links",
                 "new_str" => "notes"
               },
               @write_deps
             ) == {:ok, "ok · /memories/project"}
    end

    test "reports a note that is gone and refreshes the index" do
      expect(OutlineMock, :get_document, fn "note-1" -> {:error, :not_found} end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert {:error, "No note at /memories/project/tests." <> _} = write("confirm", %{})
    end

    test "re-reads the note once when Outline rejects a patch to a revision that moved" do
      moved = %{@valid | revision: 13, text: String.replace(@valid.text, "Fast.", "Fast!")}
      expect(OutlineMock, :get_document, fn "note-1" -> {:ok, @valid} end)
      expect(OutlineMock, :get_document, fn "note-1" -> {:ok, moved} end)

      expect(OutlineMock, :patch_document, fn "note-1", {"Speed.", "Pace."}, 12 ->
        {:error, {:rejected, "The specified text was not found in the document"}}
      end)

      expect(OutlineMock, :patch_document, fn "note-1", {"Speed.", "Pace."} = patch, 13 ->
        {:ok, patched(moved, patch, 14)}
      end)

      expect(OutlineMock, :patch_document, fn "note-1", stamp, 14 ->
        {:ok, patched(patched(moved, {"Speed.", "Pace."}, 14), stamp, 15)}
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert write("str_replace", %{"old_str" => "Speed.", "new_str" => "Pace."}) ==
               {:ok, "ok · /memories/project/tests · 2026-10-11"}
    end

    test "reports patches Outline rejects" do
      expect(OutlineMock, :get_document, 2, fn "note-1" -> {:ok, @valid} end)

      expect(OutlineMock, :patch_document, fn "note-1", _patch, 12 ->
        {:error, {:rejected, "The specified text was not found in the document"}}
      end)

      assert write("str_replace", %{"old_str" => "Fast.", "new_str" => "Quick."}) ==
               {:error,
                "Outline rejected the edit (The specified text was not found in the document); nothing changed."}
    end

    test "rejects invalid write arguments" do
      assert write("str_replace", %{"old_str" => "x"}) ==
               {:error, "str_replace needs old_str and new_str as strings."}

      assert write("insert", %{"insert_line" => "1", "insert_text" => "x"}) ==
               {:error, "insert needs insert_line as integer and insert_text as string."}

      assert Memory.call(%{"command" => "confirm", "path" => "/memories/project"}, @write_deps) ==
               {:error, "confirm applies to notes only."}

      assert Memory.call(
               %{
                 "command" => "insert",
                 "path" => "/memories",
                 "insert_line" => 0,
                 "insert_text" => "x"
               },
               @write_deps
             ) ==
               {:error, "insert applies to notes and hubs only."}
    end
  end
end
