#!/bin/sh

unavailable() {
  echo "spickzettel: memory hubs not loaded ($1); view them with the memory tool."
  exit 0
}

[ -n "$SPICKZETTEL_URL" ] || unavailable "SPICKZETTEL_URL is not set"

project_dir() {
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || {
    pwd
    return
  }

  # A worktree shares the main repository's .git, whose parent names the project.
  if [ "$(basename "$common")" = ".git" ]; then
    dirname "$common"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

project=$(basename "$(project_dir)")

hubs=$(curl --silent --fail --connect-timeout 2 --max-time 10 --get \
  --data-urlencode "project=$project" "${SPICKZETTEL_URL%/}/hubs") ||
  unavailable "the request to the server failed"

printf '%s\n' "$hubs"
