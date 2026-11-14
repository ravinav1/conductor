#!/usr/bin/env bash
# Example round: two Claude agents + one Codex red-team agent, each on a pinned model.
# Usage: CLAUDE_MODEL=<id> CODEX_MODEL=<id> launch.sh <round_dir> [timeout_min] [agent ...]
#   Briefs live at <round_dir>/brief-<agent>.md (create them from templates/brief.md).
#   No agents named: a fresh round. Refuses a round whose out/ already has outputs.
#   Agents named: relaunch only those; earlier attempts move to out/attempts/ (never
#   overwritten). The watcher then waits for every agent in the round.
# Run the whole script as a background job your environment notifies you about: it
# blocks on the watcher until the round ends, and its exit code is the watcher's.
# If your environment kills background jobs after N minutes, keep timeout_min below N.
# Flags checked against `claude --help` and `codex exec --help` (Nov 2026); re-check yours.
set -euo pipefail
ROUND="${1:?usage: CLAUDE_MODEL=<id> CODEX_MODEL=<id> launch.sh <round_dir> [timeout_min] [agent ...]}"
TIMEOUT_MIN="${2:-60}"
shift; [ $# -gt 0 ] && shift
ALL_AGENTS="claude-critic claude-builder codex-redteam"
SELECTED="${*:-$ALL_AGENTS}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Never use a CLI's default model silently: every agent's model is pinned here.
: "${CLAUDE_MODEL:?set CLAUDE_MODEL to an allowed model id}"
: "${CODEX_MODEL:?set CODEX_MODEL to an allowed model id}"

# One line per agent. The brief always arrives on STDIN:
# - no argument-size limit (Linux caps one argument at 128 KB);
# - `claude --allowedTools` takes several values and would swallow a prompt argument.
# stdout = final answer -> out/<agent>.md ; stderr/progress -> out/<agent>.err
# Agents only read: Claude gets read-only tools, Codex a read-only sandbox.
agent_cmd() {
  case "$1" in
    claude-critic|claude-builder)
      echo "claude -p --model $CLAUDE_MODEL --allowedTools Read,Grep,Glob" ;;
    codex-redteam)
      echo "codex exec -m $CODEX_MODEL --skip-git-repo-check --sandbox read-only -" ;;
    *) return 1 ;;
  esac
}

mkdir -p "$ROUND/out"
ROUND="$(cd "$ROUND" && pwd)"    # absolute: agents and watcher agree whatever their cwd

if [ $# -eq 0 ] && ls "$ROUND"/out/*.md >/dev/null 2>&1; then
  echo "launch.sh: $ROUND/out already has outputs; use a fresh round dir, or name agents to relaunch" >&2
  exit 1
fi

# Preflight everything before launching anything: no half-launched rounds.
for a in $SELECTED; do
  cmd=$(agent_cmd "$a") || { echo "launch.sh: unknown agent: $a" >&2; exit 3; }
  [ -s "$ROUND/brief-$a.md" ] || { echo "launch.sh: missing or empty brief: $ROUND/brief-$a.md" >&2; exit 1; }
  set -- $cmd
  command -v "$1" >/dev/null 2>&1 || { echo "launch.sh: CLI not found on PATH: $1" >&2; exit 1; }
  o="$ROUND/out/$a"
  if [ -f "$o.pid" ] && [ ! -f "$o.exit" ] && kill -0 "$(cat "$o.pid")" 2>/dev/null; then
    echo "launch.sh: $a still running (pid $(cat "$o.pid")); stop it first (scripts/stop.sh)" >&2; exit 1
  fi
done

archive_previous() { # Hard rule: archive outputs, never overwrite them
  local a="$1" o="$ROUND/out/$1" n=1 ext
  [ -e "$o.md" ] || [ -e "$o.pid" ] || [ -e "$o.exit" ] || return 0
  mkdir -p "$ROUND/out/attempts"
  while [ -e "$ROUND/out/attempts/$a.$n.md" ] || [ -e "$ROUND/out/attempts/$a.$n.pid" ]; do n=$((n+1)); done
  for ext in md pid exit err; do
    if [ -e "$o.$ext" ]; then mv "$o.$ext" "$ROUND/out/attempts/$a.$n.$ext"; fi
  done
}

set -m   # each agent gets its own process group, so stop.sh / timeout can stop the whole tree
for a in $SELECTED; do
  o="$ROUND/out/$a"; brief="$ROUND/brief-$a.md"; cmd=$(agent_cmd "$a")
  archive_previous "$a"
  (
    set +e; trap '' HUP                       # portable nohup: survive the launcher's hangup
    $cmd < "$brief" > "$o.md" 2> "$o.err"
    echo $? > "$o.exit.tmp" && mv "$o.exit.tmp" "$o.exit"
  ) &
  echo $! > "$o.pid.tmp" && mv "$o.pid.tmp" "$o.pid"   # atomic: watcher never reads a half-written PID
  echo "$(date '+%Y-%m-%d %H:%M:%S %Z') launched $a (pid $!): $cmd" >> "$ROUND/progress.log"
done
set +m

# Exit 0 all done, 1 settled with failures, 2 timeout, 3 usage, 4 one failed early.
exec bash "$SKILL_DIR/scripts/watch.sh" "$ROUND" "$TIMEOUT_MIN" $ALL_AGENTS
