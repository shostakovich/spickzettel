defmodule Spickzettel.FakeOutline do
  @moduledoc "A stub of Outline's API serving a small collection."

  import Plug.Conn

  @collection "collection-1"

  @documents [
    %{
      "id" => "hub-general",
      "title" => "General",
      "icon" => "📒",
      "parentDocumentId" => nil,
      "text" => "Rules for every project.\n"
    },
    %{
      "id" => "hub-project",
      "title" => "spickzettel",
      "icon" => "📝",
      "parentDocumentId" => nil,
      "text" => "The memory server.\n"
    },
    %{
      "id" => "note-tests",
      "title" => "Tests: London style",
      "icon" => "🧪",
      "parentDocumentId" => "hub-project",
      "text" => """
      `name: tests-london-style` · `typ: feedback` · `stand: 2026-10-09`

      **Kurz:** Many fast unit tests, few integration tests.

      **Why:** Fast feedback.

      ## Mocks

      Mock collaborators with Mox.

      ### Seams

      Avoid questionable seams.

      ## Integration

      Keep them few.
      """
    },
    %{
      "id" => "note-release",
      "title" => "Release checklist",
      "icon" => nil,
      "parentDocumentId" => "hub-project",
      "text" => "Steps before a release.\n"
    },
    %{
      "id" => "note-english",
      "title" => "English in repositories",
      "icon" => "🇬🇧",
      "parentDocumentId" => "hub-general",
      "text" =>
        "`name: english-in-repos` · `typ: feedback` · `stand: 2026-10-01`\n\n**Kurz:** Code and docs in English.\n"
    }
  ]

  def call(conn) do
    params = conn |> Req.Test.raw_body() |> JSON.decode!()

    cond do
      get_req_header(conn, "authorization") != ["Bearer test-api-token"] ->
        Req.Test.json(put_status(conn, 401), %{"ok" => false})

      conn.request_path == "/api/documents.list" ->
        Req.Test.json(conn, %{
          "data" => list(params),
          "pagination" => %{"offset" => params["offset"], "limit" => params["limit"]}
        })

      conn.request_path == "/api/documents.info" ->
        case Enum.find(@documents, &(&1["id"] == params["id"])) do
          nil -> Req.Test.json(put_status(conn, 404), %{"ok" => false, "error" => "not_found"})
          document -> Req.Test.json(conn, %{"data" => document})
        end
    end
  end

  defp list(%{"collectionId" => @collection} = params) do
    @documents
    |> Enum.filter(fn document ->
      not Map.has_key?(params, "parentDocumentId") or
        document["parentDocumentId"] == params["parentDocumentId"]
    end)
    |> Enum.drop(params["offset"])
    |> Enum.take(params["limit"])
  end
end
