defmodule Spickzettel.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [Spickzettel.Index | server()]
    Supervisor.start_link(children, strategy: :one_for_one, name: Spickzettel.Supervisor)
  end

  defp server do
    if Application.fetch_env!(:spickzettel, :server) do
      [{Bandit, plug: Spickzettel.Router, port: Application.fetch_env!(:spickzettel, :port)}]
    else
      []
    end
  end
end
