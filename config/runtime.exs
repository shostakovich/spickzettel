import Config

if config_env() != :test do
  note_path = fn variable ->
    value = System.fetch_env!(variable)

    case Spickzettel.MemoryPath.parse(value) do
      {:ok, {:note, _hub, _slug} = path} ->
        path

      _invalid ->
        raise "#{variable} must be a note path /memories/<hub>/<slug>, not #{inspect(value)}"
    end
  end

  token = System.fetch_env!("SPICKZETTEL_TOKEN")

  if String.length(token) < 32,
    do: raise("SPICKZETTEL_TOKEN must have at least 32 characters, e.g. openssl rand -hex 32")

  config :spickzettel,
    port: String.to_integer(System.get_env("PORT", "4000")),
    token: token,
    global_hub: System.fetch_env!("SPICKZETTEL_GLOBAL_HUB"),
    sections: [
      feedback: System.get_env("SPICKZETTEL_SECTION_FEEDBACK", "Working style"),
      project: System.get_env("SPICKZETTEL_SECTION_PROJECT", "Project knowledge"),
      reference: System.get_env("SPICKZETTEL_SECTION_REFERENCE", "References")
    ],
    dream_log: note_path.("SPICKZETTEL_DREAM_LOG"),
    dream_log_archive: note_path.("SPICKZETTEL_DREAM_LOG_ARCHIVE")

  config :spickzettel, Spickzettel.Outline,
    url: System.fetch_env!("OUTLINE_URL"),
    api_token: System.fetch_env!("OUTLINE_API_TOKEN"),
    collection_id: System.fetch_env!("OUTLINE_COLLECTION_ID")
end
