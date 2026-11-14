#!/usr/bin/env bash
# conductor completion watcher. Portable (macOS bash 3.2 + Linux).
# Usage: watch.sh <round_dir> <timeout_minutes> <agent> [agent ...]
# Expects: <round_dir>/out/<agent>.md (agent output, last line "ALL DONE")
# Optional: <round_dir>/out/<agent>.pid (agent PID, to detect crashes)
# Writes <round_dir>/STATUS.md every 15s; exits 0 when every agent is done,
# 1 if any crashed (all others finished), 2 on timeout.
dir="$1"; tmo="$2"; shift 2
start=$(date +%s); deadline=$((start + tmo*60))
while :; do
  now=$(date +%s); el=$(( (now-start)/60 )); pending=0; failed=0
  {
    echo "# Swarm status ($(date '+%Y-%m-%d %H:%M %Z'), ${el} min elapsed)"
    echo; echo "| agent | state | last line |"; echo "|---|---|---|"
    for a in "$@"; do
      f="$dir/out/$a.md"; p="$dir/out/$a.pid"; last=""
      [ -f "$f" ] && last=$(grep -v '^[[:space:]]*$' "$f" | tail -n 1 | cut -c1-80 | tr '|' '/')
      if [ -f "$f" ] && grep -q '^ALL DONE' "$f"; then st=done
      elif [ -f "$p" ] && ! kill -0 "$(cat "$p")" 2>/dev/null; then st=CRASHED; failed=$((failed+1))
      else st=running; pending=$((pending+1)); fi
      echo "| $a | $st | $last |"
    done
  } > "$dir/STATUS.md.tmp" && mv "$dir/STATUS.md.tmp" "$dir/STATUS.md"
  if [ "$pending" -eq 0 ]; then
    echo "ROUND FINISHED: failed=$failed"; cat "$dir/STATUS.md"; [ "$failed" -eq 0 ] && exit 0 || exit 1
  fi
  if [ "$now" -ge "$deadline" ]; then echo "ROUND TIMEOUT"; cat "$dir/STATUS.md"; exit 2; fi
  sleep 15
done
