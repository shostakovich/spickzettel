defmodule Spickzettel.EditTest do
  use ExUnit.Case, async: true

  import Spickzettel.TestHelpers, only: [applied: 2]

  alias Spickzettel.Edit

  @text """
  `name: tests` · `typ: feedback` · `stand: 2026-10-09`

  **Kurz:** Fast.

  - Mox.

  ## Mocks

  - Mox.
  """

  describe "str_replace" do
    test "patches the only occurrence" do
      assert Edit.str_replace(@text, "**Kurz:** Fast.", "**Kurz:** Quick.") ==
               {:ok, {"**Kurz:** Fast.", "**Kurz:** Quick."}}
    end

    test "fails when the old text is missing, repeated or empty" do
      assert Edit.str_replace(@text, "Slow.", "x") ==
               {:error, "old_str was not found in the note; nothing changed."}

      assert Edit.str_replace(@text, "- Mox.", "x") ==
               {:error,
                "old_str occurs 2 times in the note; add context to make it unique. Nothing changed."}

      assert Edit.str_replace(@text, "", "x") == {:error, "old_str must not be empty."}
    end
  end

  describe "insert" do
    test "inserts after a line, anchored on the fewest lines that first occur right there" do
      result = Edit.insert(@text, 9, "- Seams.")

      assert result == {:ok, {"## Mocks\n\n- Mox.", "## Mocks\n\n- Mox.\n- Seams."}}

      assert applied(@text, result) ==
               String.replace_suffix(@text, "- Mox.\n", "- Mox.\n- Seams.\n")
    end

    test "inserts before the first line" do
      result = Edit.insert(@text, 0, "Intro")

      assert applied(@text, result) == "Intro\n" <> @text
    end

    test "inserts after the last line and drops trailing newlines of the inserted text" do
      assert applied("One\n", Edit.insert("One\n", 1, "Two\n\n")) == "One\nTwo\n"
    end

    test "fails for a line outside the note or an empty text" do
      assert Edit.insert(@text, 10, "x") == {:error, "insert_line must be between 0 and 9."}
      assert Edit.insert(@text, -1, "x") == {:error, "insert_line must be between 0 and 9."}
      assert Edit.insert(@text, 1, "") == {:error, "insert_text must not be empty."}
    end
  end

  describe "replace_line" do
    test "replaces a repeated line at its own position" do
      assert Edit.replace_line(@text, 8, "- Stubs.") ==
               {:ok, {"## Mocks\n\n- Mox.", "## Mocks\n\n- Stubs."}}
    end
  end

  describe "insert_before" do
    test "inserts a block before a line, separated by a blank line" do
      assert applied(@text, Edit.insert_before(@text, 6, "## Intro\n\n- One.")) ==
               String.replace(@text, "## Mocks", "## Intro\n\n- One.\n\n## Mocks")
    end
  end

  describe "remove_line" do
    test "removes a repeated line at its own position, anchored with the line before" do
      result = Edit.remove_line(@text, 8)

      assert result == {:ok, {"## Mocks\n\n- Mox.", "## Mocks\n"}}
      assert applied(@text, result) == String.replace_suffix(@text, "\n- Mox.\n", "\n")
    end
  end

  describe "confirm" do
    test "increments the evidence count and sets its date, keeping the label" do
      text = "`name: x`\n\n**Kurz:** X.\n\n**Belege:** 2 Sessions, zuletzt 2026-10-01\n"

      assert applied(text, Edit.confirm(text, ~D[2026-10-11])) ==
               "`name: x`\n\n**Kurz:** X.\n\n**Belege:** 3 sessions, last 2026-10-11\n"
    end

    test "leaves other labelled lines with a count and a date alone" do
      text = "`name: x`\n\n**Kurz:** X.\n\n**Why:** 2 outages, since 2026-09-01\n"

      assert applied(text, Edit.confirm(text, ~D[2026-10-11])) ==
               text <> "\n**Evidence:** 1 session, last 2026-10-11\n"
    end

    test "adds an evidence line when there is none" do
      text = "`name: x`\n\n**Kurz:** X.\n"

      assert applied(text, Edit.confirm(text, ~D[2026-10-11])) ==
               "`name: x`\n\n**Kurz:** X.\n\n**Evidence:** 1 session, last 2026-10-11\n"
    end
  end

  test "applies a patch to the first occurrence only" do
    assert Edit.apply("a b a", {"a", "c"}) == "c b a"
  end
end
