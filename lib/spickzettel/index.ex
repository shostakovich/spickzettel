defmodule Spickzettel.Index do
  @moduledoc """
  Maps memory paths to Outline documents.

  Built from the collection listing and rebuilt when a path is not found, so renames in
  Outline do not break paths.
  """

  use GenServer

  alias Spickzettel.{Document, Note, Outline}

  @callback hubs() :: {:ok, [Document.t()]} | {:error, Outline.error()}
  @callback lookup(hub :: String.t(), slug :: String.t() | nil) ::
              {:ok, Document.t()} | {:error, :not_found | Outline.error()}
  @callback refresh() :: :ok | {:error, Outline.error()}

  # A rebuild lists the whole collection, page by page, inside the call.
  @timeout 60_000

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, Keyword.get(opts, :outline, Outline), name: name)
  end

  @doc "Lists the hubs from a fresh collection listing."
  def hubs(server \\ __MODULE__), do: GenServer.call(server, :hubs, @timeout)

  @doc "Finds a hub, or a note when `slug` is given."
  def lookup(hub, slug, server \\ __MODULE__),
    do: GenServer.call(server, {:lookup, hub, slug}, @timeout)

  def refresh(server \\ __MODULE__), do: GenServer.call(server, :refresh, @timeout)

  @impl true
  def init(outline), do: {:ok, %{outline: outline, entries: nil}}

  @impl true
  def handle_call(:hubs, _from, state) do
    case rebuild(state) do
      {:ok, state} ->
        hubs = state.entries.hubs |> Map.values() |> Enum.sort_by(&String.downcase(&1.title))
        {:reply, {:ok, hubs}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:lookup, hub, slug}, _from, state) do
    with :error <- find(state.entries, hub, slug),
         {:ok, state} <- rebuild(state) do
      {:reply, find(state.entries, hub, slug) |> not_found(), state}
    else
      {:ok, document} -> {:reply, {:ok, document}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call(:refresh, _from, state) do
    case rebuild(state) do
      {:ok, state} -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  defp find(nil, _hub, _slug), do: :error
  defp find(entries, hub, nil), do: Map.fetch(entries.hubs, key(hub))
  defp find(entries, hub, slug), do: Map.fetch(entries.notes, {key(hub), slug})

  defp not_found(:error), do: {:error, :not_found}
  defp not_found(found), do: found

  defp rebuild(state) do
    with {:ok, documents} <- state.outline.list_documents(nil) do
      {:ok, %{state | entries: entries(documents)}}
    end
  end

  defp entries(documents) do
    by_id = Map.new(documents, &{&1.id, &1})

    hubs = for %{parent_id: nil} = hub <- documents, into: %{}, do: {key(hub.title), compact(hub)}

    notes =
      for %{parent_id: parent_id} = note <- documents,
          parent_id != nil,
          hub = root(note, by_id),
          into: %{},
          do: {{key(hub.title), Note.slug(note)}, compact(note)}

    %{hubs: hubs, notes: notes}
  end

  defp root(%Document{parent_id: nil} = document, _by_id), do: document

  defp root(%Document{parent_id: parent_id}, by_id) do
    case Map.fetch(by_id, parent_id) do
      {:ok, parent} -> root(parent, by_id)
      :error -> nil
    end
  end

  defp compact(document), do: %{document | text: nil}

  # Directory names can arrive decomposed (macOS), Outline titles composed.
  defp key(title), do: String.normalize(title, :nfc)
end
