# Decisions

## 0001. Elixir with a hand-written MCP layer

Accepted, 2026-10-11

- **Context:** The server needs only a small part of MCP (initialize, tools/list, tools/call over Streamable HTTP), and the other projects are moving to Elixir; Ruby has the official SDK.
- **Decision:** Elixir with Plug, Bandit and Req, no Phoenix, no database, and the JSON-RPC layer written by hand instead of an SDK.
- **Consequences:** Protocol changes in MCP must be followed by hand; in return there is no SDK dependency, and later steps (Ecto, webhooks) fit the same stack.

## 0002. One `memory` tool modelled on Anthropic's memory tool

Accepted, 2026-10-11

- **Context:** Agents in Claude Code and Codex call the server; Claude Code defers MCP tool schemas, so the cost of tool descriptions barely matters, while models already know the commands of Anthropic's memory tool.
- **Decision:** A single `memory` tool with a `command` parameter (`view`, `create`, `str_replace`, `insert`, `delete`, `rename`, plus `confirm`) instead of one tool per command.
- **Consequences:** One schema covers all commands, so parameter validation happens in the server, not in the schema; skills and prompts depend on this interface.

## 0003. Connector with a path token, IP-restricted at the proxy

Accepted, 2026-10-11

- **Context:** Cloud sessions reach MCP servers only as claude.ai connectors, whose traffic comes from Anthropic's published egress range; OAuth is the most complex and riskiest part of a public, write-capable endpoint.
- **Decision:** The endpoint lives at `/mcp/<token>`; the reverse proxy admits only Anthropic's egress range from the internet, and the local network reaches the server directly.
- **Consequences:** Anyone who knows the token and sends from Anthropic's range can write; rotating the token means updating every client configuration.
