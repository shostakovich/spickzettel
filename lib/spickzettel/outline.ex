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

  @type new_document :: %{
          title: String.t(),
          text: String.t(),
          icon: String.t() | nil,
          parent_id: String.t() | nil
        }

  @callback list_documents(parent_id :: String.t() | nil) ::
              {:ok, [Document.t()]} | {:error, error}
  @callback get_document(id :: String.t()) :: {:ok, Document.t()} | {:error, error}
  @callback patch_document(id :: String.t(), Edit.patch(), revision :: non_neg_integer()) ::
              {:ok, Document.t()} | {:error, error}
  @callback create_document(new_document()) :: {:ok, Document.t()} | {:error, error}
  @callback move_document(id :: String.t(), parent_id :: String.t()) :: :ok | {:error, error}
  @callback delete_document(id :: String.t()) :: :ok | {:error, error}
  @callback search_documents(terms :: [String.t()], limit :: pos_integer()) ::
              {:ok, [Document.t()]} | {:error, error}

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

  @doc "Applies the patch with the matching edit mode; fails with `:conflict` once `revision` is outdated."
  @spec patch_document(String.t(), Edit.patch(), non_neg_integer()) ::
          {:ok, Document.t()} | {:error, error}
  def patch_document(id, patch, revision) do
    body = Map.merge(%{id: id, lastRevision: revision}, edit(patch))

    with {:ok, data} <- post("documents.update", body) do
      {:ok, to_document(data)}
    end
  end

  # The leading newline keeps Outline from merging the block into a closing paragraph.
  defp edit({:append, block}), do: %{editMode: "append", text: "\n\n" <> block}
  defp edit({:replace, text}), do: %{text: text}
  defp edit({find, replace}), do: %{editMode: "patch", findText: find, text: replace}

  @spec create_document(new_document()) :: {:ok, Document.t()} | {:error, error}
  def create_document(%{title: title, text: text, icon: icon, parent_id: parent_id}) do
    body = %{
      collectionId: config(:collection_id),
      parentDocumentId: parent_id,
      title: title,
      text: text,
      publish: true
    }

    with {:ok, data} <-
           post("documents.create", if(icon, do: Map.put(body, :icon, icon), else: body)) do
      {:ok, to_document(data)}
    end
  end

  @spec move_document(String.t(), String.t()) :: :ok | {:error, error}
  def move_document(id, parent_id) do
    body = %{id: id, collectionId: config(:collection_id), parentDocumentId: parent_id}

    with {:ok, _data} <- post("documents.move", body), do: :ok
  end

  @doc "Moves the document to Outline's trash."
  @spec delete_document(String.t()) :: :ok | {:error, error}
  def delete_document(id) do
    with {:ok, _data} <- post("documents.delete", %{id: id}), do: :ok
  end

  @doc "Full-text search for documents matching any of the terms, best match first."
  @spec search_documents([String.t()], pos_integer()) :: {:ok, [Document.t()]} | {:error, error}
  def search_documents(terms, limit) do
    body = %{query: Enum.join(terms, " | "), collectionId: config(:collection_id), limit: limit}

    with {:ok, results} <- post("documents.search", body) do
      {:ok, Enum.map(results, &to_document(&1["document"]))}
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
      {:ok, %{status: 200, body: %{"success" => true}}} -> {:ok, nil}
      response -> response(response)
    end
  end

  defp response({:ok, %{status: 404}}), do: {:error, :not_found}
  defp response({:ok, %{status: 409}}), do: {:error, :conflict}

  defp response({:ok, %{status: 400, body: %{"message" => message}}}),
    do: {:error, {:rejected, message}}

  defp response({:ok, %{status: status}}), do: {:error, {:status, status}}
  defp response({:error, exception}), do: {:error, exception}

  defp request do
    Req.new(
      [
        base_url: base_url() <> "/api",
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
      url_id: data["urlId"],
      url: data["urlId"] && base_url() <> "/doc/" <> data["urlId"],
      text: data["text"] || ""
    }
  end

  defp base_url, do: String.trim_trailing(config(:url), "/")

  defp config(key, default \\ nil) do
    :spickzettel |> Application.fetch_env!(__MODULE__) |> Keyword.get(key, default)
  end
end
