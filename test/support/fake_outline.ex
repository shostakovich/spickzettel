defmodule Spickzettel.FakeOutline do
  @moduledoc "A stateful stub of Outline's API serving a small collection."

  use Agent

  import Plug.Conn

  @collection "collection-1"

  @documents [
    %{
      "id" => "hub-general",
      "title" => "General",
      "icon" => "📒",
      "parentDocumentId" => nil,
      "revision" => 3,
      "text" => "Rules for every project.\n"
    },
    %{
      "id" => "hub-project",
      "title" => "spickzettel",
      "icon" => "📝",
      "parentDocumentId" => nil,
      "revision" => 5,
      "text" => "The memory server.\n"
    },
    %{
      "id" => "note-tests",
      "title" => "Tests: London style",
      "icon" => "🧪",
      "parentDocumentId" => "hub-project",
      "revision" => 12,
      "text" => """
      `name: tests-london-style` · `typ: feedback` · `stand: 2026-10-09`

      **Kurz:** Many fast unit tests, few integration tests.

      **Why:** Fast feedback.

      **How to apply:** Mock collaborators.

      ## Mocks

      Mock collaborators with Mox.

      ### Seams

      Avoid questionable seams.

      ## Integration

      Keep them few.

      **Belege:** 2 Sessions, zuletzt 2026-10-01
      """
    },
    %{
      "id" => "note-release",
      "title" => "Release checklist",
      "icon" => nil,
      "parentDocumentId" => "hub-project",
      "revision" => 4,
      "text" => "Steps before a release.\n"
    },
    %{
      "id" => "note-english",
      "title" => "English in repositories",
      "icon" => "🇬🇧",
      "parentDocumentId" => "hub-general",
      "revision" => 7,
      "text" =>
        "`name: english-in-repos` · `typ: feedback` · `stand: 2026-10-01`\n\n**Kurz:** Code and docs in English.\n"
    }
  ]

  def start_link(_opts) do
    Agent.start_link(fn -> %{documents: @documents, before_update: nil} end, name: __MODULE__)
  end

  @doc "Returns a document's current text."
  def text(id), do: document(id)["text"]

  @doc "Saves a document as the browser would, as a new revision."
  def save_in_browser(id, fun) do
    Agent.update(__MODULE__, fn state ->
      update_in(state.documents, &Enum.map(&1, fn doc -> save(doc, id, fun) end))
    end)
  end

  @doc "Runs `fun` once, right before the next update is applied."
  def before_next_update(fun), do: Agent.update(__MODULE__, &%{&1 | before_update: fun})

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
        case document(params["id"]) do
          nil -> not_found(conn)
          document -> Req.Test.json(conn, %{"data" => document})
        end

      conn.request_path == "/api/documents.update" ->
        run_before_update()
        update(conn, params)
    end
  end

  defp update(conn, %{"editMode" => "patch", "findText" => find, "text" => replacement} = params) do
    document = document(params["id"])

    cond do
      document == nil ->
        not_found(conn)

      params["lastRevision"] != document["revision"] ->
        error(conn, 409, "document_conflict")

      not String.contains?(document["text"], find) ->
        error(conn, 400, "validation_error", "The specified text was not found in the document")

      true ->
        save_in_browser(document["id"], &String.replace(&1, find, replacement, global: false))
        Req.Test.json(conn, %{"data" => document(document["id"])})
    end
  end

  defp run_before_update do
    case Agent.get_and_update(__MODULE__, &{&1.before_update, %{&1 | before_update: nil}}) do
      nil -> :ok
      fun -> fun.()
    end
  end

  defp save(%{"id" => id} = doc, id, fun),
    do: %{doc | "text" => fun.(doc["text"]), "revision" => doc["revision"] + 1}

  defp save(doc, _id, _fun), do: doc

  defp document(id),
    do: Agent.get(__MODULE__, &Enum.find(&1.documents, fn d -> d["id"] == id end))

  defp not_found(conn), do: error(conn, 404, "not_found")

  defp error(conn, status, error, message \\ "") do
    Req.Test.json(put_status(conn, status), %{
      "ok" => false,
      "error" => error,
      "message" => message
    })
  end

  defp list(%{"collectionId" => @collection} = params) do
    __MODULE__
    |> Agent.get(& &1.documents)
    |> Enum.filter(fn document ->
      not Map.has_key?(params, "parentDocumentId") or
        document["parentDocumentId"] == params["parentDocumentId"]
    end)
    |> Enum.drop(params["offset"])
    |> Enum.take(params["limit"])
  end
end
