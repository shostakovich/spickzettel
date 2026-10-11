defmodule Spickzettel.Router do
  @moduledoc """
  Streamable HTTP transport for MCP at `/mcp/<token>`, answering with plain JSON, and the hubs
  for the SessionStart hook at `/mcp/<token>/hubs?project=<name>`.
  """

  use Plug.Router

  alias Spickzettel.{MCP, SessionStart}

  @max_body_bytes 1_000_000

  plug(:match)
  plug(:dispatch)

  post "/mcp/:token" do
    with :ok <- authorize(token),
         {:ok, body, conn} <- read_body(conn, length: @max_body_bytes) do
      case JSON.decode(body) do
        {:ok, [_ | _] = batch} -> reply_batch(conn, Enum.map(batch, &MCP.handle/1))
        {:ok, message} -> reply(conn, MCP.handle(message))
        {:error, _reason} -> send_json(conn, 400, MCP.parse_error())
      end
    else
      :unauthorized -> send_resp(conn, 404, "")
      {:more, _partial, conn} -> send_resp(conn, 413, "")
      {:error, _reason} -> send_resp(conn, 400, "")
    end
  end

  get "/mcp/:token/hubs" do
    with :ok <- authorize(token),
         %{"project" => project} when is_binary(project) and project != "" <-
           fetch_query_params(conn).query_params do
      conn = put_resp_header(conn, "cache-control", "no-store")

      case SessionStart.text(project) do
        {:ok, text} -> send_text(conn, 200, text)
        {:error, message} -> send_text(conn, 502, message)
      end
    else
      :unauthorized -> send_resp(conn, 404, "")
      _params -> send_text(conn, 400, "Missing project.")
    end
  end

  match "/mcp/:token" do
    case authorize(token) do
      :ok -> conn |> put_resp_header("allow", "POST") |> send_resp(405, "")
      :unauthorized -> send_resp(conn, 404, "")
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  defp authorize(token) do
    if Plug.Crypto.secure_compare(token, Application.fetch_env!(:spickzettel, :token)),
      do: :ok,
      else: :unauthorized
  end

  defp reply(conn, {:reply, response}), do: send_json(conn, 200, response)
  defp reply(conn, :noreply), do: send_resp(conn, 202, "")

  defp reply_batch(conn, replies) do
    case for({:reply, response} <- replies, do: response) do
      [] -> send_resp(conn, 202, "")
      responses -> send_json(conn, 200, responses)
    end
  end

  defp send_text(conn, status, text) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(status, text)
  end

  defp send_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(body))
  end
end
