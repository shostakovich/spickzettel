# spickzettel

MCP server that gives coding agents a long-term memory stored in an Outline collection.

- One `memory` tool (`view`, `create`, `str_replace`, `insert`, `delete`, `rename`, `confirm`), see [DECISIONS.md](DECISIONS.md).
- Top-level documents of the collection are hubs; their child documents are notes, addressed as `/memories/<hub>/<slug>`.
- A SessionStart hook loads the cross-project hub and the current project's hub into local sessions.

## Endpoints

- `POST /mcp/<token>`: MCP over Streamable HTTP, plain JSON responses.
- `GET /mcp/<token>/hubs?project=<name>`: hub text for the SessionStart hook, below 10,000 characters.
- A wrong token answers 404.

## Container image

- Build: `docker build -t spickzettel .`
- Run: `docker run --env-file spickzettel.env -p 4000:4000 spickzettel`
- Runs as `nobody`, listens on `PORT`, Erlang distribution is off.
- Serve it behind a TLS-terminating reverse proxy; for a claude.ai connector, admit only Anthropic's published egress IP ranges from the internet (ADR 0003).

## Server environment

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| `SPICKZETTEL_TOKEN` | yes | | Path token of the endpoint `/mcp/<token>`; random, at least 32 characters, e.g. `openssl rand -hex 32` |
| `OUTLINE_URL` | yes | | Base URL of the Outline instance |
| `OUTLINE_API_TOKEN` | yes | | Outline API token with read and write access to the collection |
| `OUTLINE_COLLECTION_ID` | yes | | Id of the memory collection |
| `SPICKZETTEL_GLOBAL_HUB` | yes | | Title of the cross-project hub |
| `SPICKZETTEL_DREAM_LOG` | yes | | Path of the dream log, e.g. `/memories/<global hub>/<slug>` |
| `SPICKZETTEL_DREAM_LOG_ARCHIVE` | yes | | Path of the dream log archive |
| `SPICKZETTEL_SECTION_FEEDBACK` | no | `Working style` | Project hub section for `typ: feedback` |
| `SPICKZETTEL_SECTION_PROJECT` | no | `Project knowledge` | Project hub section for `typ: project` |
| `SPICKZETTEL_SECTION_REFERENCE` | no | `References` | Project hub section for `typ: reference` |
| `PORT` | no | `4000` | HTTP port |
| `TZ` | no | `UTC` | Time zone of the dates the server writes into `stand`, e.g. `Europe/Berlin` |

## MCP server

- URL: `https://<host>/mcp/<token>`; no OAuth, the token in the path is the credential.
- claude.ai: add a custom connector with this URL; it reaches claude.ai, cloud sessions and Claude Code sessions signed in to the same account.
- Claude Code without the connector: `claude mcp add --transport http --scope user spickzettel <url>`; do not register both, or the tool appears twice.
- Codex, in `~/.codex/config.toml`:

  ```toml
  [mcp_servers.spickzettel]
  url = "https://<host>/mcp/<token>"
  ```

## SessionStart hook

- Script: `hooks/session-start.sh`; needs `sh`, `curl` and, for the project name, `git`.
- Reads `SPICKZETTEL_URL`, the endpoint `https://<host>/mcp/<token>`; export it in the environment the agent starts in.
- The project hub is the one titled after the main repository's directory name, also from worktrees.
- When the server is unreachable it prints one line and exits 0.
- Matcher `startup|clear|compact`: a resumed session already holds the hubs.
- Claude Code, in `~/.claude/settings.json` (it keeps hook context up to 10,000 characters):

  ```json
  {
    "hooks": {
      "SessionStart": [
        {
          "matcher": "startup|clear|compact",
          "hooks": [{ "type": "command", "command": "/path/to/spickzettel/hooks/session-start.sh" }]
        }
      ]
    }
  }
  ```

- Codex, in `~/.codex/config.toml`; trust the hook once via `/hooks`:

  ```toml
  [[hooks.SessionStart]]
  matcher = "startup|clear|compact"

  [[hooks.SessionStart.hooks]]
  type = "command"
  command = "/path/to/spickzettel/hooks/session-start.sh"
  additionalContextLimit = 4000
  ```

- `additionalContextLimit` is in tokens and defaults to 2,500, which is less than up to 10,000 characters of hubs; above it Codex shows only a preview.

## Development

- Versions: `.tool-versions`
- `mix deps.get`, `mix test`, `mix format --check-formatted`

## License

[The Unlicense](LICENSE)
