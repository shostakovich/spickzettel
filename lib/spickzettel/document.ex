defmodule Spickzettel.Document do
  @moduledoc "An Outline document as the server uses it."

  @enforce_keys [:id, :title]
  defstruct [:id, :title, :icon, :parent_id, :revision, :url_id, :url, text: ""]

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          icon: String.t() | nil,
          parent_id: String.t() | nil,
          revision: non_neg_integer() | nil,
          url_id: String.t() | nil,
          url: String.t() | nil,
          text: String.t() | nil
        }
end
