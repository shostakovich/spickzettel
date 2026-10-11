defmodule Spickzettel.RuntimeConfigTest do
  use ExUnit.Case, async: false

  @runtime Path.expand("../../config/runtime.exs", __DIR__)

  @environment %{
    "SPICKZETTEL_TOKEN" => String.duplicate("a", 64),
    "SPICKZETTEL_GLOBAL_HUB" => "General",
    "SPICKZETTEL_DREAM_LOG" => "/memories/General/dream-log",
    "SPICKZETTEL_DREAM_LOG_ARCHIVE" => "/memories/General/dream-log-archive",
    "OUTLINE_URL" => "http://outline.test",
    "OUTLINE_API_TOKEN" => "api-token",
    "OUTLINE_COLLECTION_ID" => "collection-1"
  }

  defp read(overrides) do
    environment = Map.merge(@environment, overrides)
    previous = Map.new(environment, fn {name, _value} -> {name, System.get_env(name)} end)

    try do
      System.put_env(environment)
      Config.Reader.read!(@runtime, env: :prod)
    after
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end
  end

  test "parses the dream log paths once" do
    config = read(%{})[:spickzettel]

    assert config[:dream_log] == {:note, "General", "dream-log"}
    assert config[:dream_log_archive] == {:note, "General", "dream-log-archive"}
  end

  test "refuses to boot with a dream log path that is not a note path" do
    assert_raise RuntimeError, ~r/SPICKZETTEL_DREAM_LOG must be a note path/, fn ->
      read(%{"SPICKZETTEL_DREAM_LOG" => "General/dream-log"})
    end

    assert_raise RuntimeError, ~r/SPICKZETTEL_DREAM_LOG_ARCHIVE must be a note path/, fn ->
      read(%{"SPICKZETTEL_DREAM_LOG_ARCHIVE" => "/memories/General"})
    end
  end

  test "refuses to boot with a token shorter than 32 characters" do
    assert_raise RuntimeError, ~r/SPICKZETTEL_TOKEN must have at least 32 characters/, fn ->
      read(%{"SPICKZETTEL_TOKEN" => String.duplicate("a", 31)})
    end

    assert read(%{"SPICKZETTEL_TOKEN" => String.duplicate("a", 32)})[:spickzettel][:token] ==
             String.duplicate("a", 32)
  end
end
