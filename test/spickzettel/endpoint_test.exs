defmodule Spickzettel.EndpointTest do
  use ExUnit.Case, async: false

  import Spickzettel.TestHelpers, only: [serve_fake_outline: 1]

  alias Spickzettel.FakeOutline

  setup :serve_fake_outline

  defp post(base, path, message) do
    Req.post!(base <> path,
      json: message,
      headers: [accept: "application/json, text/event-stream"],
      retry: false
    )
  end

  defp rpc(base, id, method, params) do
    post(base, "/mcp/test-token", %{jsonrpc: "2.0", id: id, method: method, params: params})
  end

  defp memory(base, command, arguments) do
    response =
      rpc(base, 3, "tools/call", %{
        name: "memory",
        arguments: Map.put(arguments, :command, command)
      })

    assert %{
             "result" => %{
               "isError" => error?,
               "content" => [%{"type" => "text", "text" => text}]
             }
           } =
             response.body

    if error?, do: {:error, text}, else: {:ok, text}
  end

  defp view(base, arguments) do
    assert {:ok, text} = memory(base, "view", arguments)
    text
  end

  defp today, do: NaiveDateTime.local_now() |> NaiveDateTime.to_date() |> Date.to_iso8601()

  test "completes the MCP handshake", %{base: base} do
    initialize =
      rpc(base, 1, "initialize", %{
        protocolVersion: "2025-06-18",
        capabilities: %{},
        clientInfo: %{name: "test", version: "1"}
      })

    assert initialize.status == 200
    assert %{"jsonrpc" => "2.0", "id" => 1, "result" => result} = initialize.body
    assert result["protocolVersion"] == "2025-06-18"
    assert result["capabilities"] == %{"tools" => %{}}
    assert result["serverInfo"]["name"] == "spickzettel"
    assert result["instructions"] =~ "/memories/General"

    initialized =
      post(base, "/mcp/test-token", %{jsonrpc: "2.0", method: "notifications/initialized"})

    assert initialized.status == 202
    assert initialized.body == ""

    tools = rpc(base, 2, "tools/list", %{})

    assert [%{"name" => "memory", "inputSchema" => %{"type" => "object"}}] =
             tools.body["result"]["tools"]
  end

  test "views a hub as a compact list", %{base: base} do
    assert view(base, %{path: "/memories/spickzettel"}) == """
           # 📝 spickzettel · /memories/spickzettel
           - 🧪 Tests: London style · tests-london-style · 2026-10-09 — Many fast unit tests, few integration tests.
           - Release checklist · release-checklist — Steps before a release.\
           """
  end

  test "views a section of a note", %{base: base} do
    assert view(base, %{path: "/memories/spickzettel/tests-london-style", section: "Mocks"}) ==
             """
             ## Mocks

             Mock collaborators with Mox.

             ### Seams

             Avoid questionable seams.\
             """
  end

  test "rejects a wrong token", %{base: base} do
    response = post(base, "/mcp/wrong-token", %{jsonrpc: "2.0", id: 1, method: "tools/list"})

    assert response.status == 404
  end

  describe "concurrent edit in the browser" do
    test "re-reads the newer revision and applies the replacement once more", %{base: base} do
      FakeOutline.before_next_update(fn ->
        FakeOutline.save_in_browser(
          "note-tests",
          &String.replace(&1, "Keep them few.", "Keep them very few.")
        )
      end)

      assert memory(base, "str_replace", %{
               path: "/memories/spickzettel/tests-london-style",
               old_str: "Mock collaborators with Mox.",
               new_str: "Mock collaborators with Mox, never the code under test."
             }) == {:ok, "ok · /memories/spickzettel/tests-london-style · #{today()}"}

      text = FakeOutline.text("note-tests")
      assert text =~ "Mock collaborators with Mox, never the code under test."
      assert text =~ "Keep them very few."
      assert text =~ "`stand: #{today()}`"
    end

    test "changes nothing when the old text is gone in the newer revision", %{base: base} do
      FakeOutline.before_next_update(fn ->
        FakeOutline.save_in_browser(
          "note-tests",
          &String.replace(&1, "Mock collaborators with Mox.", "Use Mox.")
        )
      end)

      assert {:error, "old_str was not found in the note" <> _} =
               memory(base, "str_replace", %{
                 path: "/memories/spickzettel/tests-london-style",
                 old_str: "Mock collaborators with Mox.",
                 new_str: "Mock everything."
               })

      text = FakeOutline.text("note-tests")
      assert text =~ "Use Mox."
      assert text =~ "`stand: 2026-10-09`"
    end
  end

  describe "format check" do
    test "rejects a write that would remove the Why line of a valid feedback note", %{base: base} do
      before = FakeOutline.text("note-tests")

      assert memory(base, "str_replace", %{
               path: "/memories/spickzettel/tests-london-style",
               old_str: "**Why:** Fast feedback.\n\n",
               new_str: ""
             }) ==
               {:error,
                "Rejected: the note would become invalid: no **Why:** line. Nothing changed."}

      assert FakeOutline.text("note-tests") == before
    end

    test "applies an edit to a note without header line and warns", %{base: base} do
      assert memory(base, "insert", %{
               path: "/memories/spickzettel/release-checklist",
               insert_line: 1,
               insert_text: "\nRun the tests."
             }) ==
               {:ok,
                "ok · /memories/spickzettel/release-checklist\nWarning: the note is invalid: no header line."}

      assert FakeOutline.text("note-release") == "Steps before a release.\n\nRun the tests.\n"
    end
  end

  test "confirm increments the evidence count and sets its date, nothing else", %{base: base} do
    before = FakeOutline.text("note-tests")

    assert memory(base, "confirm", %{path: "/memories/spickzettel/tests-london-style"}) ==
             {:ok, "ok · /memories/spickzettel/tests-london-style · 2026-10-09"}

    assert FakeOutline.text("note-tests") ==
             String.replace(
               before,
               "**Belege:** 2 Sessions, zuletzt 2026-10-01",
               "**Belege:** 3 sessions, last #{today()}"
             )
  end
end
