defmodule Spickzettel.HubTest do
  use ExUnit.Case, async: true

  import Spickzettel.TestHelpers, only: [applied: 2]

  alias Spickzettel.{Document, Hub}

  @hub """
  The memory server.

  ## Working style

  * 🧪 [Tests](https://outline.test/doc/AAA111) — Fast tests.

  ## Project knowledge

  Notes about the project.

  ### Details

  * [Release](https://outline.test/doc/release-BBB222) — Steps. See [Tests](https://outline.test/doc/AAA111).
  """

  test "lists the level-2 sections" do
    assert Hub.sections(@hub) == ["Working style", "Project knowledge"]
  end

  describe "sections for a link" do
    test "the cross-project hub needs an existing section named by the caller" do
      assert Hub.cross_project_section(@hub, nil) == {:error, :unnamed}
      assert Hub.cross_project_section(@hub, "working STYLE") == {:ok, "Working style"}
      assert Hub.cross_project_section(@hub, "Pitfalls") == {:error, :unknown}
    end

    test "a project hub takes the named section, else the default, existing or new" do
      assert Hub.project_section(@hub, "pitfalls", "Working style") == {:ok, "pitfalls"}
      assert Hub.project_section(@hub, nil, "project knowledge") == {:ok, "Project knowledge"}
      assert Hub.project_section(@hub, nil, nil) == {:error, :unnamed}
    end
  end

  test "renders a link line with icon and summary" do
    note = %Document{id: "n", title: "Mocks", icon: "🎭", url: "https://outline.test/doc/CCC333"}

    assert Hub.link(note, "Use Mox.") ==
             "* 🎭 [Mocks](https://outline.test/doc/CCC333) — Use Mox."

    assert Hub.link(%{note | icon: nil}, nil) == "* [Mocks](https://outline.test/doc/CCC333)"
  end

  describe "add_link" do
    test "appends the link to the section's list" do
      assert applied(@hub, Hub.add_link(@hub, "Working style", "* New")) ==
               String.replace(@hub, "Fast tests.\n", "Fast tests.\n* New\n")
    end

    test "appends below the section's nested headings" do
      assert applied(@hub, Hub.add_link(@hub, "Project knowledge", "* New")) ==
               String.replace(@hub, "AAA111).\n", "AAA111).\n* New\n")
    end

    test "starts a list after a paragraph" do
      text = "Intro.\n\n## Notes\n\nSome text.\n"

      assert applied(text, Hub.add_link(text, "Notes", "* New")) ==
               "Intro.\n\n## Notes\n\nSome text.\n\n* New\n"
    end

    test "appends a missing section" do
      assert applied(@hub, Hub.add_link(@hub, "Pitfalls", "* New")) ==
               @hub <> "\n## Pitfalls\n\n* New\n"
    end
  end

  describe "remove_link" do
    test "removes the list item that links the document first" do
      assert applied(@hub, Hub.remove_link(@hub, "AAA111")) ==
               String.replace(
                 @hub,
                 "* 🧪 [Tests](https://outline.test/doc/AAA111) — Fast tests.\n",
                 ""
               )

      assert applied(@hub, Hub.remove_link(@hub, "BBB222")) ==
               String.replace(@hub, ~r/\* \[Release\].*\n/, "")
    end

    test "fails without a link line" do
      assert Hub.remove_link(@hub, "ZZZ999") == {:error, "it has no link line for the note."}
      assert Hub.remove_link(@hub, nil) == {:error, "the note has no link address."}
    end
  end
end
