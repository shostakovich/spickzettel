defmodule Spickzettel.OutlineTest do
  use ExUnit.Case, async: true

  alias Spickzettel.{Document, Outline}

  defp document(n),
    do: %{
      "id" => "doc-#{n}",
      "title" => "Doc #{n}",
      "icon" => nil,
      "parentDocumentId" => "hub",
      "text" => "Text #{n}"
    }

  defp params(conn), do: conn |> Req.Test.raw_body() |> JSON.decode!()

  test "lists the collection page by page" do
    Req.Test.expect(Spickzettel.Outline, 2, fn conn ->
      assert conn.request_path == "/api/documents.list"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-api-token"]

      %{
        "collectionId" => "collection-1",
        "limit" => 100,
        "offset" => offset,
        "sort" => "createdAt",
        "direction" => "ASC"
      } = params = params(conn)

      refute Map.has_key?(params, "parentDocumentId")

      count = if offset == 0, do: 100, else: 1
      Req.Test.json(conn, %{"data" => Enum.map(offset..(offset + count - 1)//1, &document/1)})
    end)

    assert {:ok, documents} = Outline.list_documents(nil)
    assert length(documents) == 101

    assert List.last(documents) == %Document{
             id: "doc-100",
             title: "Doc 100",
             icon: nil,
             parent_id: "hub",
             text: "Text 100"
           }
  end

  test "lists the children of a document" do
    Req.Test.expect(Spickzettel.Outline, fn conn ->
      assert %{"parentDocumentId" => "hub"} = params(conn)
      Req.Test.json(conn, %{"data" => [document(1)]})
    end)

    assert {:ok, [%Document{id: "doc-1"}]} = Outline.list_documents("hub")
  end

  test "fetches a document" do
    Req.Test.expect(Spickzettel.Outline, fn conn ->
      assert conn.request_path == "/api/documents.info"
      assert params(conn) == %{"id" => "doc-1"}
      Req.Test.json(conn, %{"data" => document(1)})
    end)

    assert {:ok, %Document{id: "doc-1", text: "Text 1"}} = Outline.get_document("doc-1")
  end

  test "reports missing documents and failed requests" do
    Req.Test.expect(Spickzettel.Outline, fn conn ->
      Req.Test.json(Plug.Conn.put_status(conn, 404), %{})
    end)

    Req.Test.expect(Spickzettel.Outline, fn conn ->
      Req.Test.json(Plug.Conn.put_status(conn, 401), %{})
    end)

    Req.Test.expect(Spickzettel.Outline, &Req.Test.transport_error(&1, :timeout))

    assert Outline.get_document("gone") == {:error, :not_found}
    assert Outline.list_documents(nil) == {:error, {:status, 401}}
    assert {:error, %Req.TransportError{reason: :timeout}} = Outline.get_document("doc-1")
  end
end
