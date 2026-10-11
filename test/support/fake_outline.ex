defmodule Spickzettel.FakeOutline do
  @moduledoc "A stateful stub of Outline's API serving a small collection."

  use Agent

  import Plug.Conn

  @collection "collection-1"

  @dream_log_runs (for {date, size} <- [
                         {"2026-10-10", 6_000},
                         {"2026-10-09", 5_000},
                         {"2026-10-08", 3_000}
                       ] do
                     "## #{date} · Dream\n\n" <> String.duplicate("z", size) <> "\n"
                   end)

  @documents [
    %{
      "id" => "hub-general",
      "urlId" => "GEN1",
      "title" => "General",
      "icon" => "📒",
      "parentDocumentId" => nil,
      "revision" => 3,
      "text" => """
      Rules for every project.

      ## Code

      * 🇬🇧 [English in repositories](http://outline.test/doc/ENG1) — Code and docs in English.

      ## Projects

      * 📝 [spickzettel](http://outline.test/doc/SPZ1) — The memory server.
      """
    },
    %{
      "id" => "hub-project",
      "urlId" => "SPZ1",
      "title" => "spickzettel",
      "icon" => "📝",
      "parentDocumentId" => nil,
      "revision" => 5,
      "text" => """
      The memory server.

      ## Working style

      * 🧪 [Tests: London style](http://outline.test/doc/TST1) — Many fast unit tests, few integration tests.
      """
    },
    %{
      "id" => "hub-other",
      "urlId" => "OTH1",
      "title" => "other",
      "icon" => nil,
      "parentDocumentId" => nil,
      "revision" => 1,
      "text" => "Another project.\n"
    },
    %{
      "id" => "note-tests",
      "urlId" => "TST1",
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
      "urlId" => "REL1",
      "title" => "Release checklist",
      "icon" => nil,
      "parentDocumentId" => "hub-project",
      "revision" => 4,
      "text" => "Steps before a release.\n"
    },
    %{
      "id" => "note-english",
      "urlId" => "ENG1",
      "title" => "English in repositories",
      "icon" => "🇬🇧",
      "parentDocumentId" => "hub-general",
      "revision" => 7,
      "text" =>
        "`name: english-in-repos` · `typ: feedback` · `stand: 2026-10-01`\n\n**Kurz:** Code and docs in English.\n"
    },
    %{
      "id" => "note-dream-log",
      "urlId" => "DRM1",
      "title" => "Dream log",
      "icon" => "🌙",
      "parentDocumentId" => "hub-general",
      "revision" => 20,
      "text" => Enum.join(["Runs, newest first.\n" | @dream_log_runs], "\n")
    },
    %{
      "id" => "note-dream-log-archive",
      "urlId" => "ARC1",
      "title" => "Dream log archive",
      "icon" => "🗃️",
      "parentDocumentId" => "note-dream-log",
      "revision" => 2,
      "text" => "Older runs, newest first.\n\n## 2026-10-01 · Dream\n\nOld run.\n"
    }
  ]

  def start_link(_opts) do
    Agent.start_link(fn -> %{documents: @documents, before_update: nil} end, name: __MODULE__)
  end

  @doc "Returns a document's current text."
  def text(id), do: document(id)["text"]

  @doc "Saves a document as the browser would, as a new revision."
  def save_in_browser(id, fun),
    do: save(id, &%{&1 | "text" => fun.(&1["text"]), "revision" => &1["revision"] + 1})

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

      conn.request_path == "/api/documents.create" ->
        Req.Test.json(conn, %{"data" => create(params)})

      conn.request_path == "/api/documents.move" ->
        save(params["id"], &Map.put(&1, "parentDocumentId", params["parentDocumentId"]))
        Req.Test.json(conn, %{"data" => %{"documents" => [document(params["id"])]}})

      conn.request_path == "/api/documents.delete" ->
        Agent.update(__MODULE__, fn state ->
          update_in(state.documents, &Enum.reject(&1, fn doc -> doc["id"] == params["id"] end))
        end)

        Req.Test.json(conn, %{"success" => true})

      conn.request_path == "/api/documents.search" ->
        Req.Test.json(conn, %{"data" => search(params)})
    end
  end

  @doc "Returns the document with the given title."
  def titled(title),
    do: Agent.get(__MODULE__, &Enum.find(&1.documents, fn d -> d["title"] == title end))

  defp create(params) do
    Agent.get_and_update(__MODULE__, fn state ->
      n = length(state.documents) + 1

      document = %{
        "id" => "doc-#{n}",
        "urlId" => "NEW#{n}",
        "title" => params["title"],
        "icon" => params["icon"],
        "parentDocumentId" => params["parentDocumentId"],
        "revision" => 1,
        "text" => params["text"]
      }

      {document, update_in(state.documents, &(&1 ++ [document]))}
    end)
  end

  defp search(%{"query" => query, "collectionId" => @collection, "limit" => limit}) do
    terms = String.split(query, " | ")

    __MODULE__
    |> Agent.get(& &1.documents)
    |> Enum.map(fn doc ->
      content = String.downcase(doc["title"] <> " " <> doc["text"])
      {doc, Enum.count(terms, &String.contains?(content, &1))}
    end)
    |> Enum.filter(fn {_doc, hits} -> hits > 0 end)
    |> Enum.sort_by(fn {_doc, hits} -> hits end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {doc, hits} -> %{"ranking" => hits, "context" => "", "document" => doc} end)
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

  defp save(id, fun) do
    Agent.update(__MODULE__, fn state ->
      update_in(
        state.documents,
        &Enum.map(&1, fn doc -> if doc["id"] == id, do: fun.(doc), else: doc end)
      )
    end)
  end

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
