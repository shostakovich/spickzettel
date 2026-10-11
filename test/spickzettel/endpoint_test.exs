defmodule Spickzettel.EndpointTest do
  use ExUnit.Case, async: false

  setup :set_req_test_to_shared

  setup do
    Req.Test.stub(Spickzettel.Outline, &Spickzettel.FakeOutline.call/1)
    server = start_supervised!({Bandit, plug: Spickzettel.Router, port: 0, ip: :loopback})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{base: "http://127.0.0.1:#{port}"}
  end

  defp set_req_test_to_shared(context), do: Req.Test.set_req_test_to_shared(context)

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

  defp view(base, arguments) do
    response =
      rpc(base, 3, "tools/call", %{
        name: "memory",
        arguments: Map.put(arguments, :command, "view")
      })

    assert %{
             "result" => %{"isError" => false, "content" => [%{"type" => "text", "text" => text}]}
           } =
             response.body

    text
  end

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
end
