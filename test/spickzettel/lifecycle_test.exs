defmodule Spickzettel.LifecycleTest do
  use ExUnit.Case, async: true

  import Mox
  import Spickzettel.TestHelpers, only: [compact: 1]

  alias Spickzettel.{Document, Edit, IndexMock, Lifecycle, OutlineMock}

  setup :verify_on_exit!

  @deps %{
    index: IndexMock,
    outline: OutlineMock,
    today: &__MODULE__.today/0,
    global_hub: "General",
    sections: %{"feedback" => "Working style", "project" => "Project knowledge"}
  }

  @general %Document{
    id: "hub-0",
    title: "General",
    revision: 9,
    text:
      "Rules.\n\n## Code\n\n* 🇬🇧 [English](http://outline.test/doc/ENG1) — English.\n\n" <>
        "## Projects\n\n* [project](http://outline.test/doc/PRJ1) — The project.\n"
  }

  @project %Document{
    id: "hub-1",
    title: "project",
    revision: 4,
    text: "The project.\n\n## Working style\n\n* [Old](http://outline.test/doc/OLD1) — Old.\n"
  }

  @other %Document{id: "hub-2", title: "other", revision: 2, text: "Another project.\n"}

  @note %Document{
    id: "note-1",
    title: "Mocks",
    icon: "🎭",
    parent_id: "hub-1",
    url_id: "MCK1",
    url: "http://outline.test/doc/MCK1",
    revision: 7,
    text:
      "`name: mocks` · `typ: feedback` · `stand: 2026-10-01`\n\n**Kurz:** Use Mox.\n\n" <>
        "**Why:** Speed.\n\n**How to apply:** Mock collaborators.\n"
  }

  @new %{
    title: "Mocks",
    typ: "feedback",
    icon: "🎭",
    section: nil,
    text: "**Kurz:** Use Mox.\n\n**Why:** Speed.\n\n**How to apply:** Mock collaborators.\n"
  }

  def today, do: ~D[2026-10-11]

  defp hubs(documents) do
    stub(IndexMock, :lookup, fn
      name, nil ->
        case Enum.find(documents, &(&1.title == name)) do
          nil -> {:error, :not_found}
          hub -> {:ok, compact(hub)}
        end

      _hub, _slug ->
        {:error, :not_found}
    end)

    stub(OutlineMock, :get_document, fn id -> {:ok, Enum.find(documents, &(&1.id == id))} end)
  end

  defp expect_patch(%Document{id: id, revision: revision} = document, check) do
    expect(OutlineMock, :patch_document, fn ^id, patch, ^revision ->
      text = Edit.apply(document.text, patch)
      check.(text)
      {:ok, %{document | text: text, revision: revision + 1}}
    end)
  end

  describe "create" do
    setup do
      hubs([@general, @project])
      stub(OutlineMock, :search_documents, fn _terms, 10 -> {:ok, []} end)
      :ok
    end

    test "adds the header line, links the note under its typ's section, answers in one line" do
      expect(OutlineMock, :create_document, fn %{
                                                 title: "Mocks",
                                                 icon: "🎭",
                                                 parent_id: "hub-1",
                                                 text: text
                                               } ->
        assert text == String.replace(@note.text, "2026-10-01", "2026-10-11")
        {:ok, %{@note | text: text}}
      end)

      expect_patch(@project, fn text ->
        assert text ==
                 @project.text <>
                   "* 🎭 [Mocks](http://outline.test/doc/MCK1) — Use Mox.\n"
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.create({:note, "project", "mocks"}, @new, @deps) ==
               {:ok, "ok · /memories/project/mocks · 2026-10-11"}
    end

    test "appends the typ's section when the hub lacks it" do
      expect(OutlineMock, :create_document, fn new -> {:ok, %{@note | text: new.text}} end)

      expect_patch(@project, fn text ->
        assert String.ends_with?(
                 text,
                 "— Old.\n\n## Project knowledge\n\n* 🎭 [Mocks]" <>
                   "(http://outline.test/doc/MCK1) — Use Mox.\n"
               )
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.create({:note, "project", "mocks"}, %{@new | typ: "project"}, @deps) ==
               {:ok,
                "ok · /memories/project/mocks · 2026-10-11\n" <>
                  ~s(Warning: added new section "Project knowledge" to /memories/project.)}
    end

    test "warns about a note above 15,000 characters" do
      long = %{@new | text: @new.text <> String.duplicate("x", 15_000)}
      expect(OutlineMock, :create_document, fn new -> {:ok, %{@note | text: new.text}} end)
      expect_patch(@project, fn _text -> :ok end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert {:ok,
              "ok · /memories/project/mocks · 2026-10-11\n" <>
                "Warning: the note has 15" <> _} =
               Lifecycle.create({:note, "project", "mocks"}, long, @deps)
    end

    test "reports the three best similar notes, leaving out hubs" do
      expect(OutlineMock, :search_documents, fn ["mocks", "mox"], 10 ->
        notes = for id <- ~w(a b c d), do: %Document{id: id, title: id, parent_id: "hub-2"}
        {:ok, [@project | notes]}
      end)

      expect(IndexMock, :path, 3, fn id -> {:ok, {:note, "other", id}} end)
      expect(OutlineMock, :create_document, fn new -> {:ok, %{@note | text: new.text}} end)
      expect_patch(@project, fn _text -> :ok end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.create({:note, "project", "mocks"}, @new, @deps) ==
               {:ok,
                "ok · /memories/project/mocks · 2026-10-11\n" <>
                  "Similar notes: /memories/other/a, /memories/other/b, /memories/other/c"}
    end

    test "creates the note even when its hub link fails, and warns" do
      expect(OutlineMock, :create_document, fn new -> {:ok, %{@note | text: new.text}} end)
      expect(OutlineMock, :patch_document, fn "hub-1", _patch, 4 -> {:error, {:status, 500}} end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.create({:note, "project", "mocks"}, @new, @deps) ==
               {:ok,
                "ok · /memories/project/mocks · 2026-10-11\n" <>
                  "Warning: no link added to /memories/project: Outline answered with status 500."}
    end

    test "warns instead of claiming a new section when Outline drops the appended section" do
      expect(OutlineMock, :create_document, fn new -> {:ok, %{@note | text: new.text}} end)

      expect(OutlineMock, :patch_document, fn "hub-1", {:append, _block}, 4 ->
        {:ok, %{@project | revision: 5}}
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert {:ok,
              "ok · /memories/project/mocks · 2026-10-11\n" <>
                "Warning: no link added to /memories/project: Outline accepted the edit but " <>
                "stored a different text" <> _} =
               Lifecycle.create({:note, "project", "mocks"}, %{@new | typ: "project"}, @deps)
    end

    test "in the cross-project hub, links under the named section only" do
      expect(OutlineMock, :create_document, fn %{parent_id: "hub-0"} = new ->
        {:ok, %{@note | text: new.text}}
      end)

      expect_patch(@general, fn text ->
        assert text =~
                 "English.\n* 🎭 [Mocks](http://outline.test/doc/MCK1) — Use Mox.\n\n## Projects"
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert {:ok, _reply} =
               Lifecycle.create({:note, "General", "mocks"}, %{@new | section: "code"}, @deps)
    end

    test "rejects a note in the cross-project hub without an existing section" do
      assert Lifecycle.create({:note, "General", "mocks"}, @new, @deps) ==
               {:error,
                "Name the section of /memories/General for the link in `section`. " <>
                  "Sections: Code, Projects. Nothing changed."}

      assert Lifecycle.create({:note, "General", "mocks"}, %{@new | section: "Tools"}, @deps) ==
               {:error,
                ~s(No section "Tools" in /memories/General. Sections: Code, Projects. Nothing changed.)}
    end

    test "needs a section for a user note in a project hub" do
      assert {:error, "Name the section of /memories/project" <> _} =
               Lifecycle.create({:note, "project", "me"}, %{@new | typ: "user"}, @deps)
    end

    test "rejects existing paths, bad slugs and invalid notes" do
      expect(IndexMock, :lookup, fn "project", "old" -> {:ok, compact(@note)} end)

      assert Lifecycle.create({:note, "project", "old"}, @new, @deps) ==
               {:error, "/memories/project/old already exists; nothing changed."}

      assert {:error, ~s(The slug "Mocks" must be kebab-case) <> _} =
               Lifecycle.create({:note, "project", "Mocks"}, @new, @deps)

      assert Lifecycle.create({:note, "project", "mocks"}, %{@new | title: nil}, @deps) ==
               {:error, "create needs a title."}

      assert Lifecycle.create({:note, "project", "mocks"}, %{@new | typ: "idea"}, @deps) ==
               {:error, "create needs typ: user, feedback, project, reference."}

      assert Lifecycle.create({:note, "project", "mocks"}, %{@new | text: @note.text}, @deps) ==
               {:error, "Leave out the header line; the server adds it from path and typ."}

      assert Lifecycle.create({:note, "project", "mocks"}, %{@new | text: "**Kurz:** x\n"}, @deps) ==
               {:error,
                "Rejected: the note would be invalid: no **Why:** line; no **How to apply:** line."}
    end

    test "rejects a note in a missing hub" do
      assert {:error, "No hub at /memories/nope." <> _} =
               Lifecycle.create({:note, "nope", "mocks"}, @new, @deps)
    end

    test "creates a project hub and links it under the named section of the cross-project hub" do
      hub = %Document{id: "hub-3", title: "new", icon: "🆕", url: "http://outline.test/doc/NEW1"}

      expect(OutlineMock, :create_document, fn %{
                                                 title: "new",
                                                 icon: "🆕",
                                                 parent_id: nil,
                                                 text: "A new project.\n"
                                               } = new ->
        {:ok, %{hub | text: new.text}}
      end)

      expect_patch(@general, fn text ->
        assert String.ends_with?(
                 text,
                 "The project.\n* 🆕 [new](http://outline.test/doc/NEW1) — A new project.\n"
               )
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      new_hub = %{
        @new
        | typ: nil,
          title: nil,
          icon: "🆕",
          text: "A new project.",
          section: "Projects"
      }

      assert Lifecycle.create({:hub, "new"}, new_hub, @deps) == {:ok, "ok · /memories/new"}

      assert {:error, "Name the section of /memories/General" <> _} =
               Lifecycle.create({:hub, "new"}, %{new_hub | section: nil}, @deps)

      assert Lifecycle.create({:hub, "new"}, %{new_hub | text: " "}, @deps) ==
               {:error, "create needs file_text with a one-line description of the hub."}
    end
  end

  describe "rename" do
    @link "* 🎭 [Mocks](http://outline.test/doc/MCK1) — Use Mox.\n"
    @linked %{@project | text: @project.text <> @link}

    setup do
      hubs([@linked, @other])

      stub(IndexMock, :lookup, fn
        "project", "mocks" -> {:ok, compact(@note)}
        "project", nil -> {:ok, compact(@linked)}
        "other", nil -> {:ok, compact(@other)}
        "other", "taken" -> {:ok, compact(@note)}
        _hub, _slug -> {:error, :not_found}
      end)

      stub(OutlineMock, :get_document, fn
        "note-1" -> {:ok, @note}
        "hub-1" -> {:ok, @linked}
        "hub-2" -> {:ok, @other}
      end)

      :ok
    end

    defp expect_note_writes do
      Process.put(:note, @note)

      expect(OutlineMock, :patch_document, 2, fn "note-1", patch, revision ->
        %{revision: ^revision} = note = Process.get(:note)
        note = %{note | text: Edit.apply(note.text, patch), revision: revision + 1}
        Process.put(:note, note)
        {:ok, note}
      end)
    end

    test "across hubs: sets the new name and stand, moves the note and its link" do
      expect_note_writes()
      expect(OutlineMock, :move_document, fn "note-1", "hub-2" -> :ok end)

      expect_patch(@other, fn text ->
        assert text == @other.text <> "\n## Working style\n\n" <> @link
      end)

      expect_patch(@linked, fn text -> assert text == @project.text end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.rename({:note, "project", "mocks"}, {:note, "other", "stubs"}, nil, @deps) ==
               {:ok,
                "ok · /memories/other/stubs · 2026-10-11\n" <>
                  ~s(Warning: added new section "Working style" to /memories/other.)}
    end

    test "across hubs: keeps the old link when the new one fails" do
      expect_note_writes()
      expect(OutlineMock, :move_document, fn "note-1", "hub-2" -> :ok end)
      expect(OutlineMock, :patch_document, fn "hub-2", _patch, 2 -> {:error, {:status, 500}} end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.rename({:note, "project", "mocks"}, {:note, "other", "stubs"}, nil, @deps) ==
               {:ok,
                "ok · /memories/other/stubs · 2026-10-11\n" <>
                  "Warning: no link added to /memories/other: Outline answered with status 500. " <>
                  "The link in /memories/project stays."}
    end

    test "within a hub only renames, without touching links" do
      expect_note_writes()
      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.rename(
               {:note, "project", "mocks"},
               {:note, "project", "stubs"},
               nil,
               @deps
             ) ==
               {:ok, "ok · /memories/project/stubs · 2026-10-11"}
    end

    test "rejects a section when the note stays in its hub" do
      assert Lifecycle.rename(
               {:note, "project", "mocks"},
               {:note, "project", "stubs"},
               "Working style",
               @deps
             ) ==
               {:error,
                "section applies only when rename moves the note to another hub. Nothing changed."}
    end

    test "moves without writing the note when the slug stays" do
      expect(OutlineMock, :move_document, fn "note-1", "hub-2" -> :ok end)
      expect_patch(@other, fn _text -> :ok end)
      expect_patch(@linked, fn _text -> :ok end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert {:ok, "ok · /memories/other/mocks · 2026-10-01\n" <> _warning} =
               Lifecycle.rename(
                 {:note, "project", "mocks"},
                 {:note, "other", "mocks"},
                 nil,
                 @deps
               )
    end

    test "reports a failed move after the rename" do
      expect_note_writes()
      expect(OutlineMock, :move_document, fn "note-1", "hub-2" -> {:error, {:status, 500}} end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.rename({:note, "project", "mocks"}, {:note, "other", "stubs"}, nil, @deps) ==
               {:error,
                "Not moved to /memories/other: Outline answered with status 500. " <>
                  "The note is at /memories/project/stubs."}
    end

    test "rejects the same path, a taken path and a new slug without header line" do
      assert Lifecycle.rename(
               {:note, "project", "mocks"},
               {:note, "project", "mocks"},
               nil,
               @deps
             ) ==
               {:error, "old_path and new_path are the same."}

      assert Lifecycle.rename({:note, "project", "mocks"}, {:note, "other", "taken"}, nil, @deps) ==
               {:error, "/memories/other/taken already exists; nothing changed."}

      expect(OutlineMock, :get_document, fn "note-1" -> {:ok, %{@note | text: "Plain.\n"}} end)

      assert {:error, "/memories/project/mocks has no header line with a name" <> _} =
               Lifecycle.rename(
                 {:note, "project", "mocks"},
                 {:note, "project", "plain"},
                 nil,
                 @deps
               )
    end
  end

  describe "delete" do
    setup do
      stub(IndexMock, :lookup, fn
        "project", "mocks" -> {:ok, compact(@note)}
        "project", nil -> {:ok, compact(@project)}
      end)

      :ok
    end

    test "deletes the note and removes its link from the hub" do
      linked = %{
        @project
        | text: @project.text <> "* 🎭 [Mocks](http://outline.test/doc/MCK1) — Use Mox.\n"
      }

      expect(OutlineMock, :list_documents, fn "note-1" -> {:ok, []} end)
      expect(OutlineMock, :delete_document, fn "note-1" -> :ok end)
      expect(OutlineMock, :get_document, fn "hub-1" -> {:ok, linked} end)

      expect(OutlineMock, :patch_document, fn "hub-1", patch, 4 ->
        assert Edit.apply(linked.text, patch) == @project.text
        {:ok, @project}
      end)

      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.delete({:note, "project", "mocks"}, @deps) ==
               {:ok, "ok · deleted /memories/project/mocks"}
    end

    test "warns when the hub has no link to the note" do
      expect(OutlineMock, :list_documents, fn "note-1" -> {:ok, []} end)
      expect(OutlineMock, :delete_document, fn "note-1" -> :ok end)
      expect(OutlineMock, :get_document, fn "hub-1" -> {:ok, @project} end)
      expect(IndexMock, :refresh, fn -> :ok end)

      assert Lifecycle.delete({:note, "project", "mocks"}, @deps) ==
               {:ok,
                "ok · deleted /memories/project/mocks\n" <>
                  "Warning: no link removed from /memories/project: it has no link line for the note."}
    end

    test "rejects a note with nested documents" do
      expect(OutlineMock, :list_documents, fn "note-1" -> {:ok, [@other]} end)

      assert Lifecycle.delete({:note, "project", "mocks"}, @deps) ==
               {:error,
                "/memories/project/mocks has 1 nested documents; move or delete them first. Nothing changed."}
    end
  end
end
