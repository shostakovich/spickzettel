defmodule Spickzettel.TestHelpers do
  @moduledoc "Helpers shared by the tests."

  @doc "The document as the index keeps it, without its text."
  def compact(document), do: %{document | text: nil}
end
