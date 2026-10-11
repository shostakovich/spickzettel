defmodule Spickzettel.InstructionsTest do
  use ExUnit.Case, async: true

  alias Spickzettel.Instructions

  test "carries the recall rule, path scheme and note format within 2,048 characters" do
    text = Instructions.text("General")

    assert String.length(text) <= 2048
    assert text =~ "check relevance first"
    assert text =~ "already in your context"
    assert text =~ "/memories/General"
    assert text =~ "/memories/<hub>/<slug>"
    assert text =~ "`stand: YYYY-MM-DD`"
    assert text =~ "at most 160 characters"
  end
end
