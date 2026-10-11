import Config

config :spickzettel, server: true

if config_env() == :test do
  config :logger, level: :warning

  config :spickzettel,
    server: false,
    token: "test-token",
    global_hub: "General",
    sections: [feedback: "Working style", project: "Project knowledge", reference: "References"],
    dream_log: {:note, "General", "dream-log"},
    dream_log_archive: {:note, "General", "dream-log-archive"}

  config :spickzettel, Spickzettel.Outline,
    url: "http://outline.test",
    api_token: "test-api-token",
    collection_id: "collection-1",
    req_options: [plug: {Req.Test, Spickzettel.Outline}, retry: false]
end
