defmodule Spickzettel.TestHelpers do
  @moduledoc "Helpers shared by the tests."

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Spickzettel.{Edit, FakeOutline}

  @spec applied(String.t(), Edit.result()) :: String.t()
  def applied(text, {:ok, patch}), do: Edit.apply(text, patch)

  @doc "The document as the index keeps it, without its text."
  def compact(document), do: %{document | text: nil}

  @doc "Serves the router on a free port in front of a fresh FakeOutline; use with `setup`."
  def serve_fake_outline(context) do
    Req.Test.set_req_test_to_shared(context)
    start_supervised!(FakeOutline)
    Req.Test.stub(Spickzettel.Outline, &FakeOutline.call/1)
    :ok = Spickzettel.Index.refresh()
    server = start_supervised!({Bandit, plug: Spickzettel.Router, port: 0, ip: :loopback})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    %{base: "http://127.0.0.1:#{port}"}
  end
end
