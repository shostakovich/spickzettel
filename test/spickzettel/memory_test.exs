defmodule Spickzettel.MemoryTest do
  use ExUnit.Case, async: true

  import Mox

  alias Spickzettel.{Document, IndexMock, Memory, OutlineMock}

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
    assert definition.inputSchema.properties.command.enum == ["view"]
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
    assert Memory.call(%{}, @deps) == {:error, "Missing command. Commands: view."}

    assert Memory.call(%{"command" => "create"}, @deps) ==
             {:error, ~s(Unknown command "create". Commands: view.)}

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
end
