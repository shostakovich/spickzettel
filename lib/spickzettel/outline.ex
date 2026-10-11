defmodule Spickzettel.Outline do
  @moduledoc "Client for the Outline API, limited to the memory collection."

  alias Spickzettel.{Document, Edit}

  @page_size 100

  @type error ::
          :not_found
          | :conflict
          | {:rejected, String.t()}
          | {:status, pos_integer()}
          | Exception.t()

  @callback list_documents(parent_id :: String.t() | nil) ::
              {:ok, [Document.t()]} | {:error, error}
  @callback get_document(id :: String.t()) :: {:ok, Document.t()} | {:error, error}
  @callback patch_document(id :: String.t(), Edit.patch(), revision :: non_neg_integer()) ::
              {:ok, Document.t()} | {:error, error}

  @spec list_documents(String.t() | nil) :: {:ok, [Document.t()]} | {:error, error}
  def list_documents(parent_id \\ nil) do
    # Pages by offset, so the order must not change when a document is edited meanwhile.
    params = %{
      collectionId: config(:collection_id),
      limit: @page_size,
      sort: "createdAt",
      direction: "ASC"
    }

    params = if parent_id, do: Map.put(params, :parentDocumentId, parent_id), else: params

    list_pages(params, 0, [])
  end

  @spec get_document(String.t()) :: {:ok, Document.t()} | {:error, error}
  def get_document(id) do
    with {:ok, data} <- post("documents.info", %{id: id}) do
      {:ok, to_document(data)}
    end
  end

  @doc "Applies the patch with Outline's patch mode; fails with `:conflict` once `revision` is outdated."
  @spec patch_document(String.t(), Edit.patch(), non_neg_integer()) ::
          {:ok, Document.t()} | {:error, error}
  def patch_document(id, {find, replace}, revision) do
    body = %{id: id, editMode: "patch", findText: find, text: replace, lastRevision: revision}

    with {:ok, data} <- post("documents.update", body) do
      {:ok, to_document(data)}
    end
  end

  defp list_pages(params, offset, pages) do
    with {:ok, data} <- post("documents.list", Map.put(params, :offset, offset)) do
      pages = [Enum.map(data, &to_document/1) | pages]

      if length(data) < @page_size,
        do: {:ok, pages |> Enum.reverse() |> Enum.concat()},
        else: list_pages(params, offset + @page_size, pages)
    end
  end

  defp post(endpoint, body) do
    case Req.post(request(), url: endpoint, json: body) do
      {:ok, %{status: 200, body: %{"data" => data}}} -> {:ok, data}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: 409}} -> {:error, :conflict}
      {:ok, %{status: 400, body: %{"message" => message}}} -> {:error, {:rejected, message}}
      {:ok, %{status: status}} -> {:error, {:status, status}}
      {:error, exception} -> {:error, exception}
    end
  end

  defp request do
    Req.new(
      [
        base_url: String.trim_trailing(config(:url), "/") <> "/api",
        auth: {:bearer, config(:api_token)}
      ] ++
        config(:req_options, [])
    )
  end

  defp to_document(data) do
    %Document{
      id: data["id"],
      title: data["title"],
      icon: data["icon"],
      parent_id: data["parentDocumentId"],
      revision: data["revision"],
      text: data["text"] || ""
    }
  end

  defp config(key, default \\ nil) do
    :spickzettel |> Application.fetch_env!(__MODULE__) |> Keyword.get(key, default)
  end
end
