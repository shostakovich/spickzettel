defmodule Spickzettel.MemoryPathTest do
  use ExUnit.Case, async: true

  alias Spickzettel.MemoryPath

  test "parses the root, a hub and a note" do
    assert MemoryPath.parse("/memories") == {:ok, :root}
    assert MemoryPath.parse("/memories/") == {:ok, :root}
    assert MemoryPath.parse("/memories/General") == {:ok, {:hub, "General"}}
    assert MemoryPath.parse("/memories/General/english/") == {:ok, {:note, "General", "english"}}
  end

  test "rejects other paths" do
    for path <- ["", "/", "memories", "/notes/x", "/memories//x", "/memories/a/b/c"] do
      assert MemoryPath.parse(path) == :error
    end
  end
end
