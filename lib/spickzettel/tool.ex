defmodule Spickzettel.Tool do
  @moduledoc "An MCP tool: its definition for `tools/list` and its handler for `tools/call`."

  @callback definition() :: map()
  @callback call(arguments :: map()) :: {:ok, String.t()} | {:error, String.t()}
end
