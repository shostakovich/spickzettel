defmodule Spickzettel.MemoryPath do
  @moduledoc "Paths of the form `/memories`, `/memories/<hub>` and `/memories/<hub>/<slug>`."

  @type t :: :root | {:hub, String.t()} | {:note, String.t(), String.t()}

  defguard is_note(path) when is_tuple(path) and elem(path, 0) == :note

  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(path) do
    case path |> String.trim() |> String.trim_trailing("/") |> String.split("/") do
      ["", "memories"] -> {:ok, :root}
      ["", "memories", hub] when hub != "" -> {:ok, {:hub, hub}}
      ["", "memories", hub, slug] when hub != "" and slug != "" -> {:ok, {:note, hub, slug}}
      _ -> :error
    end
  end

  @spec hub(String.t()) :: String.t()
  def hub(name), do: "/memories/" <> name

  @spec to_string(t()) :: String.t()
  def to_string(:root), do: "/memories"
  def to_string({:hub, name}), do: hub(name)
  def to_string({:note, hub, slug}), do: hub(hub) <> "/" <> slug
end
