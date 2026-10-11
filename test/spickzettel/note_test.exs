defmodule Spickzettel.NoteTest do
  use ExUnit.Case, async: true

  alias Spickzettel.{Document, Note}

  @text """
  `name: tests-london-style` · `typ: feedback` · `stand: 2026-10-09`

  **Kurz:** Many fast unit tests.

  ## Mocks

  Mock collaborators.

  ```
  ## not a heading
  ```

  ### Seams

  Few seams.

  ## Integration

  Few.
  """

  test "reads name and stand from the header line" do
    assert Note.name(@text) == "tests-london-style"
    assert Note.stand(@text) == "2026-10-09"
  end

  test "reads typ and tells whether there is a header line" do
    assert Note.typ(@text) == "feedback"
    assert Note.header?(@text)
    refute Note.header?("Text.\n")
    refute Note.header?(nil)
  end

  test "sets stand in the header line" do
    assert Note.put_stand("\n" <> @text, ~D[2026-10-11]) ==
             {1, "`name: tests-london-style` · `typ: feedback` · `stand: 2026-10-11`"}

    assert Note.put_stand(@text, ~D[2026-10-09]) == nil
    assert Note.put_stand("`name: x`\n\nstand: 2026-01-01\n", ~D[2026-10-11]) == nil
    assert Note.put_stand("Text, stand: 2026-01-01\n", ~D[2026-10-11]) == nil
  end

  test "sets name in the header line" do
    assert Note.put_name(@text, "london") ==
             {0, "`name: london` · `typ: feedback` · `stand: 2026-10-09`"}

    assert Note.put_name("  name: a · typ: user\n", "b") == {0, "  name: b · typ: user"}
    assert Note.put_name(@text, "tests-london-style") == nil
    assert Note.put_name("Text.\n", "x") == nil
  end

  test "lists headings with line index and level, skipping code fences" do
    assert Note.heading_lines(@text) ==
             [{4, 2, "Mocks"}, {12, 3, "Seams"}, {16, 2, "Integration"}]
  end

  test "strips a closing sequence of #s only after whitespace" do
    text = "## C#\n\n## Mocks ##  \n\n### ###\n\n## Issue \\#\n"

    assert Note.heading_lines(text) ==
             [{0, 2, "C#"}, {2, 2, "Mocks"}, {4, 3, ""}, {6, 2, "Issue \\#"}]
  end

  test "parses a long heading without backtracking" do
    line = "## x" <> String.duplicate(" ", 20_000) <> "y"
    {microseconds, [{0, 2, _title}]} = :timer.tc(fn -> Note.heading_lines(line) end)
    assert microseconds < 50_000
  end

  test "has no name or stand without a header line" do
    assert Note.name("Just text, name: nope later\n") == nil
    assert Note.stand("Plain text, stand: 2026-01-01\n") == nil
    assert Note.name(nil) == nil
  end

  test "takes the summary from the line after the header, without its label" do
    assert Note.summary(@text) == "Many fast unit tests."
  end

  test "takes the first line as summary when there is no header" do
    assert Note.summary("\nSteps before a release.\n\nMore.\n") == "Steps before a release."
    assert Note.summary("`name: only-header` · `stand: 2026-10-01`\n") == nil
    assert Note.summary("") == nil
  end

  test "uses the name as slug and falls back to the title" do
    assert Note.slug(%Document{id: "1", title: "x", text: @text}) == "tests-london-style"

    assert Note.slug(%Document{id: "1", title: "Persönliche Übersicht: Geräte", text: "Text"}) ==
             "personliche-ubersicht-gerate"
  end

  test "lists headings outside code blocks" do
    assert Note.headings(@text) == ["Mocks", "Seams", "Integration"]
  end

  test "extracts a section with its subsections" do
    assert Note.section(@text, "mocks") ==
             {:ok,
              "## Mocks\n\nMock collaborators.\n\n```\n## not a heading\n```\n\n### Seams\n\nFew seams."}
  end

  test "extracts the last section up to the end and accepts leading hashes" do
    assert Note.section(@text, "## Integration") == {:ok, "## Integration\n\nFew."}
  end

  test "fails for an unknown section" do
    assert Note.section(@text, "Unknown") == :error
  end

  test "extracts a line range" do
    assert Note.line_range(@text, 3, 3) == {:ok, "**Kurz:** Many fast unit tests."}
    assert Note.line_range(@text, 17, -1) == {:ok, "## Integration\n\nFew."}
    assert Note.line_range(@text, 18, 99) == {:ok, "\nFew."}
  end

  test "fails for a range outside the note" do
    assert Note.line_range(@text, 20, 30) == :error
    assert Note.line_count(@text) == 19
  end
end
