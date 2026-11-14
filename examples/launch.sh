#!/usr/bin/env bash
# Example round: two Claude agents + one Codex red-team agent.
# Check your CLI versions' flags; these are common headless forms.
set -euo pipefail
ROUND="${1:-swarm/round1}"; SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROUND/out"

launch() { # name, brief-file, command...
  local name="$1" brief="$2"; shift 2
  ( "$@" "$(cat "$brief")" > "$ROUND/out/$name.md" 2>>"$ROUND/progress.log" ) &
  echo $! > "$ROUND/out/$name.pid"
}

launch claude-critic  "$ROUND/brief-critic.md"  claude -p
launch claude-builder "$ROUND/brief-builder.md" claude -p
launch codex-redteam  "$ROUND/brief-redteam.md" codex exec

# Wait for every ALL DONE (or a crash, or 60 min), writing STATUS.md as it goes.
"$SKILL_DIR/scripts/watch.sh" "$ROUND" 60 claude-critic claude-builder codex-redteam
