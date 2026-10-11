defmodule Spickzettel.RouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Spickzettel.Router

  defp call(method, path, body \\ nil),
    do: method |> conn(path, body) |> Router.call(Router.init([]))

  test "answers malformed JSON with a parse error" do
    conn = call(:post, "/mcp/test-token", "{")

    assert conn.status == 400

    assert JSON.decode!(conn.resp_body) == %{
             "jsonrpc" => "2.0",
             "id" => nil,
             "error" => %{"code" => -32700, "message" => "Parse error"}
           }
  end

  test "answers a batch with the responses to its requests" do
    ping = %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"}
    notification = %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}

    conn = call(:post, "/mcp/test-token", JSON.encode!([ping, notification, 5]))

    assert conn.status == 200

    assert [
             %{"id" => 1, "result" => %{}},
             %{"id" => nil, "error" => %{"code" => -32600}}
           ] = JSON.decode!(conn.resp_body)

    assert call(:post, "/mcp/test-token", JSON.encode!([notification])).status == 202
  end

  test "refuses a body above the size limit" do
    assert call(:post, "/mcp/test-token", String.duplicate(" ", 1_000_001)).status == 413
  end

  test "allows only POST on the endpoint" do
    conn = call(:get, "/mcp/test-token")

    assert conn.status == 405
    assert Plug.Conn.get_resp_header(conn, "allow") == ["POST"]
  end

  test "hides the endpoint behind the token" do
    assert call(:get, "/mcp/wrong").status == 404
    assert call(:post, "/mcp/wrong", "{}").status == 404
    assert call(:get, "/").status == 404
  end
end
