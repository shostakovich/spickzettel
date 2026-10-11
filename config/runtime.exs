import Config

if config_env() != :test do
  token = System.fetch_env!("SPICKZETTEL_TOKEN")

  if String.length(token) < 32,
    do: raise("SPICKZETTEL_TOKEN must have at least 32 characters, e.g. openssl rand -hex 32")

  config :spickzettel,
    port: String.to_integer(System.get_env("PORT", "4000")),
    token: token,
    global_hub: System.fetch_env!("SPICKZETTEL_GLOBAL_HUB")

  config :spickzettel, Spickzettel.Outline,
    url: System.fetch_env!("OUTLINE_URL"),
    api_token: System.fetch_env!("OUTLINE_API_TOKEN"),
    collection_id: System.fetch_env!("OUTLINE_COLLECTION_ID")
end
