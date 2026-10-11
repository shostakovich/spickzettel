defmodule Spickzettel.MCPTest do
  use ExUnit.Case, async: true

  import Mox

  alias Spickzettel.{MCP, ToolMock}

  setup :verify_on_exit!

  @definition %{name: "memory", inputSchema: %{type: "object"}}

  defp request(method, params \\ %{}),
    do: %{"jsonrpc" => "2.0", "id" => 7, "method" => method, "params" => params}

  test "initializes with a supported protocol version and the instructions" do
    assert {:reply, %{id: 7, result: result}} =
             MCP.handle(request("initialize", %{"protocolVersion" => "2025-03-26"}), ToolMock)

    assert result.protocolVersion == "2025-03-26"
    assert result.capabilities == %{tools: %{}}
    assert result.serverInfo == %{name: "spickzettel", version: "0.1.0"}
    assert result.instructions =~ "/memories/General"
  end

  test "offers its latest protocol version for an unknown one" do
    assert {:reply, %{result: %{protocolVersion: "2025-11-25"}}} =
             MCP.handle(request("initialize", %{"protocolVersion" => "1999-01-01"}), ToolMock)
  end

  test "answers ping" do
    assert MCP.handle(request("ping"), ToolMock) ==
             {:reply, %{jsonrpc: "2.0", id: 7, result: %{}}}
  end

  test "lists the tool" do
    expect(ToolMock, :definition, fn -> @definition end)

    assert MCP.handle(request("tools/list"), ToolMock) ==
             {:reply, %{jsonrpc: "2.0", id: 7, result: %{tools: [@definition]}}}
  end

  test "calls the tool and wraps its text" do
    stub(ToolMock, :definition, fn -> @definition end)
    expect(ToolMock, :call, fn %{"command" => "view"} -> {:ok, "# /memories"} end)
    expect(ToolMock, :call, fn %{} -> {:error, "Missing command."} end)

    assert {:reply, %{result: %{content: [%{type: "text", text: "# /memories"}], isError: false}}} =
             MCP.handle(
               request("tools/call", %{"name" => "memory", "arguments" => %{"command" => "view"}}),
               ToolMock
             )

    assert {:reply,
            %{result: %{content: [%{type: "text", text: "Missing command."}], isError: true}}} =
             MCP.handle(request("tools/call", %{"name" => "memory"}), ToolMock)
  end

  test "rejects unknown tools and methods" do
    stub(ToolMock, :definition, fn -> @definition end)

    assert {:reply, %{error: %{code: -32602, message: "Unknown tool: other"}}} =
             MCP.handle(request("tools/call", %{"name" => "other"}), ToolMock)

    assert {:reply, %{error: %{code: -32602}}} = MCP.handle(request("tools/call"), ToolMock)

    assert {:reply, %{error: %{code: -32602, message: "Tool name must be a string"}}} =
             MCP.handle(request("tools/call", %{"name" => %{"x" => 1}}), ToolMock)

    assert {:reply, %{error: %{code: -32602}}} = MCP.handle(request("tools/list", [1]), ToolMock)

    assert {:reply, %{id: 7, error: %{code: -32601}}} =
             MCP.handle(request("resources/list"), ToolMock)
  end

  test "does not answer notifications and responses" do
    assert MCP.handle(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, ToolMock) ==
             :noreply

    assert MCP.handle(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}, ToolMock) == :noreply
  end

  test "rejects invalid requests" do
    assert {:reply, %{id: nil, error: %{code: -32600}}} = MCP.handle([request("ping")], ToolMock)

    assert {:reply, %{id: 3, error: %{code: -32600}}} =
             MCP.handle(%{"id" => 3, "method" => "ping"}, ToolMock)

    assert {:reply, %{id: nil, error: %{code: -32600}}} =
             MCP.handle(%{"jsonrpc" => "2.0", "id" => %{}, "method" => "ping"}, ToolMock)
  end
end
