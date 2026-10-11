defmodule Spickzettel.MCP do
  @moduledoc "MCP's JSON-RPC methods: initialize, ping, tools/list and tools/call."

  alias Spickzettel.Instructions

  @protocol_versions ["2025-11-25", "2025-06-18", "2025-03-26"]

  @parse_error -32700
  @invalid_request -32600
  @method_not_found -32601
  @invalid_params -32602

  @type reply :: {:reply, map()} | :noreply

  @spec parse_error() :: map()
  def parse_error, do: error(nil, @parse_error, "Parse error")

  @spec handle(term(), module()) :: reply()
  def handle(message, tool \\ Spickzettel.Memory)

  def handle(%{"jsonrpc" => "2.0", "id" => id, "method" => method} = message, tool)
      when is_binary(method) and (is_binary(id) or is_integer(id)) do
    case Map.get(message, "params", %{}) do
      params when is_map(params) -> {:reply, respond(id, method, params, tool)}
      _params -> {:reply, error(id, @invalid_params, "params must be an object")}
    end
  end

  def handle(%{"jsonrpc" => "2.0", "method" => method} = message, _tool)
      when is_binary(method) and not is_map_key(message, "id"),
      do: :noreply

  def handle(%{"jsonrpc" => "2.0", "id" => _id} = message, _tool)
      when is_map_key(message, "result") or is_map_key(message, "error"),
      do: :noreply

  def handle(message, _tool),
    do: {:reply, error(request_id(message), @invalid_request, "Invalid Request")}

  defp respond(id, "initialize", params, _tool) do
    result(id, %{
      protocolVersion: protocol_version(params["protocolVersion"]),
      capabilities: %{tools: %{}},
      serverInfo: %{name: "spickzettel", version: version()},
      instructions: Instructions.text(Application.fetch_env!(:spickzettel, :global_hub))
    })
  end

  defp respond(id, "ping", _params, _tool), do: result(id, %{})

  defp respond(id, "tools/list", _params, tool), do: result(id, %{tools: [tool.definition()]})

  defp respond(id, "tools/call", %{"name" => name} = params, tool) when is_binary(name) do
    if name == tool.definition().name do
      result(id, tool_result(tool.call(Map.get(params, "arguments", %{}))))
    else
      error(id, @invalid_params, "Unknown tool: #{name}")
    end
  end

  defp respond(id, "tools/call", %{"name" => _name}, _tool),
    do: error(id, @invalid_params, "Tool name must be a string")

  defp respond(id, "tools/call", _params, _tool),
    do: error(id, @invalid_params, "Missing tool name")

  defp respond(id, method, _params, _tool),
    do: error(id, @method_not_found, "Method not found: #{method}")

  defp tool_result({:ok, text}), do: %{content: [%{type: "text", text: text}], isError: false}
  defp tool_result({:error, text}), do: %{content: [%{type: "text", text: text}], isError: true}

  defp protocol_version(requested) when requested in @protocol_versions, do: requested
  defp protocol_version(_requested), do: hd(@protocol_versions)

  defp version, do: :spickzettel |> Application.spec(:vsn) |> to_string()

  defp request_id(%{"id" => id}) when is_binary(id) or is_integer(id), do: id
  defp request_id(_message), do: nil

  defp result(id, result), do: %{jsonrpc: "2.0", id: id, result: result}

  defp error(id, code, message),
    do: %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}}
end
