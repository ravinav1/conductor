#!/usr/bin/env bash
# Stop a round's agents (or only the named ones). Portable: macOS bash 3.2 and Linux.
# Usage: stop.sh <round_dir> [agent ...]
# Sends TERM to each agent's process group (launch.sh starts each agent in its own),
# falling back to the PID. Outputs are kept. Then check with: ps -p <pid>
set -u
[ $# -ge 1 ] || { echo "usage: stop.sh <round_dir> [agent ...]" >&2; exit 3; }
dir=$1; shift
[ -d "$dir/out" ] || { echo "stop.sh: no such directory: $dir/out" >&2; exit 3; }
if [ $# -eq 0 ]; then
  for p in "$dir"/out/*.pid; do [ -f "$p" ] && set -- "$@" "$(basename "$p" .pid)"; done
fi
for a in "$@"; do
  p="$dir/out/$a.pid"; [ -f "$p" ] || { echo "$a: no pid file (manual agent?)"; continue; }
  [ -f "$dir/out/$a.exit" ] && { echo "$a: already exited"; continue; }
  pid=$(tr -dc '0-9' < "$p"); [ -n "$pid" ] || { echo "$a: bad pid file"; continue; }
  if kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null; then
    echo "$a: sent TERM (pid $pid)"
  else
    echo "$a: not running"
  fi
done
