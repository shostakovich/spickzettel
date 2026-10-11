defmodule Spickzettel.SimilarTest do
  use ExUnit.Case, async: true

  import Mox

  alias Spickzettel.{Document, IndexMock, OutlineMock, Similar}

  setup :verify_on_exit!

  @deps %{index: IndexMock, outline: OutlineMock}

  test "takes the distinct words of three letters or more, without stop words" do
    assert Similar.terms("Tests: London style mit Mox und die Mocks, the tests") ==
             ["tests", "london", "style", "mox", "mocks"]
  end

  test "lists the paths of the three best matching notes, without hubs" do
    expect(OutlineMock, :search_documents, fn ["london", "tests"], 10 ->
      hub = %Document{id: "hub", title: "Hub"}
      notes = for id <- ~w(a b c d), do: %Document{id: id, title: id, parent_id: "hub"}
      {:ok, [hub | notes]}
    end)

    expect(IndexMock, :path, fn "a" -> {:error, :not_found} end)
    expect(IndexMock, :path, 3, fn id -> {:ok, {:note, "hub", id}} end)

    assert Similar.paths("London tests", @deps) ==
             ["/memories/hub/b", "/memories/hub/c", "/memories/hub/d"]
  end

  test "finds nothing without words or when the search fails" do
    assert Similar.paths("a b", @deps) == []

    expect(OutlineMock, :search_documents, fn _terms, 10 -> {:error, {:status, 500}} end)
    assert Similar.paths("London tests", @deps) == []
  end
end
