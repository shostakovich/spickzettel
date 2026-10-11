defmodule Spickzettel.IndexTest do
  use ExUnit.Case, async: true

  import Mox
  import Spickzettel.TestHelpers, only: [compact: 1]

  alias Spickzettel.{Document, Index, OutlineMock}

  setup :verify_on_exit!

  @general %Document{id: "hub-1", title: "General", text: "Hub."}
  @project %Document{id: "hub-2", title: "project", text: "Hub."}
  @note %Document{
    id: "note-1",
    title: "Tests",
    parent_id: "hub-2",
    text: "`name: tests` · `stand: 2026-10-09`\n"
  }
  @archive %Document{id: "note-2", title: "Old archive", parent_id: "note-1", text: "Archived."}

  setup do
    index = start_supervised!({Index, name: nil, outline: OutlineMock})
    allow(OutlineMock, self(), index)
    %{index: index}
  end

  test "builds once and finds hubs and notes, nested ones under their hub", %{index: index} do
    expect(OutlineMock, :list_documents, 1, fn nil ->
      {:ok, [@general, @project, @note, @archive]}
    end)

    assert Index.lookup("project", nil, index) == {:ok, compact(@project)}
    assert Index.lookup("project", "tests", index) == {:ok, compact(@note)}
    assert Index.lookup("project", "old-archive", index) == {:ok, compact(@archive)}
  end

  test "rebuilds when a path is not found", %{index: index} do
    renamed = %{@note | text: "`name: renamed`\n"}
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [@project, @note]} end)
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [@project, renamed]} end)
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [@project, renamed]} end)

    assert {:ok, _note} = Index.lookup("project", "tests", index)
    assert Index.lookup("project", "renamed", index) == {:ok, compact(renamed)}
    assert Index.lookup("General", nil, index) == {:error, :not_found}
  end

  test "matches hub names regardless of Unicode normalization", %{index: index} do
    composed = %Document{id: "hub-3", title: String.normalize("Küche", :nfc), text: "Hub."}
    note = %Document{@note | parent_id: "hub-3"}
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [composed, note]} end)

    decomposed = String.normalize("Küche", :nfd)
    assert Index.lookup(decomposed, nil, index) == {:ok, compact(composed)}
    assert Index.lookup(decomposed, "tests", index) == {:ok, compact(note)}
  end

  test "lists the hubs from a fresh listing, sorted by title", %{index: index} do
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [@project, @general]} end)
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [@project]} end)

    assert Index.hubs(index) == {:ok, [compact(@general), compact(@project)]}
    assert Index.hubs(index) == {:ok, [compact(@project)]}
  end

  test "refreshes on demand", %{index: index} do
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [@project]} end)
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [@general]} end)

    assert {:ok, _hub} = Index.lookup("project", nil, index)
    assert Index.refresh(index) == :ok
    assert Index.lookup("General", nil, index) == {:ok, compact(@general)}
  end

  test "passes Outline errors on and keeps the last index", %{index: index} do
    expect(OutlineMock, :list_documents, fn nil -> {:ok, [@project]} end)
    expect(OutlineMock, :list_documents, 3, fn nil -> {:error, {:status, 503}} end)

    assert {:ok, _hub} = Index.lookup("project", nil, index)
    assert Index.lookup("General", nil, index) == {:error, {:status, 503}}
    assert Index.hubs(index) == {:error, {:status, 503}}
    assert Index.refresh(index) == {:error, {:status, 503}}
    assert {:ok, _hub} = Index.lookup("project", nil, index)
  end
end
