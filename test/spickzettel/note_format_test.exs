defmodule Spickzettel.NoteFormatTest do
  use ExUnit.Case, async: true

  alias Spickzettel.NoteFormat

  @feedback """
  `name: tests` · `typ: feedback` · `stand: 2026-10-09`

  **Kurz:** Fast.

  **Why:** Feedback.

  **How to apply:** Mock.
  """

  test "accepts a complete note" do
    assert NoteFormat.problems(@feedback) == []

    assert NoteFormat.problems("`name: x` · `typ: user` · `stand: 2026-10-09`\n\nSummary.\n") ==
             []
  end

  test "requires the header line with name, a known typ and stand" do
    assert NoteFormat.problems("Summary.\n") == ["no header line"]

    assert NoteFormat.problems("`name: x` · `typ: other`\n\nSummary.\n") ==
             ["header line lacks typ, stand"]
  end

  test "requires the summary line" do
    assert NoteFormat.problems("`name: x` · `typ: user` · `stand: 2026-10-09`\n") ==
             ["no summary line"]
  end

  test "limits the summary line, label included, to 160 characters" do
    header = "`name: x` · `typ: user` · `stand: 2026-10-09`\n\n**Kurz:** "

    assert NoteFormat.problems(header <> String.duplicate("x", 150) <> "\n") == []

    assert NoteFormat.problems(header <> String.duplicate("x", 151) <> "\n") ==
             ["summary line has 161 characters, above 160"]
  end

  test "requires Why and How to apply in feedback and project notes" do
    assert @feedback |> String.replace("**Why:** Feedback.\n", "") |> NoteFormat.problems() ==
             ["no **Why:** line"]

    assert @feedback
           |> String.replace("typ: feedback", "typ: project")
           |> String.replace("**How to apply:** Mock.\n", "")
           |> NoteFormat.problems() == ["no **How to apply:** line"]
  end
end
