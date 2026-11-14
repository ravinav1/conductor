#!/usr/bin/env bash
# conductor completion watcher. Portable: macOS bash 3.2 and Linux; POSIX tools only.
# Usage: watch.sh <round_dir> <timeout_minutes> <agent> [agent ...]
# Per agent, in <round_dir>/out/:
#   <agent>.md    final answer. Done only when its process has ended AND its last
#                 non-blank line is "ALL DONE" (surrounding whitespace, CR, * ` _ ignored).
#   <agent>.pid   PID of the launch wrapper. No pid file = manual/web agent ("waiting").
#   <agent>.exit  exit code, written by the launcher when the process ends. Preferred
#                 over the PID (immune to PID reuse). Non-zero = FAILED.
# Rewrites <round_dir>/STATUS.md every WATCH_INTERVAL s (default 15) and appends
# <round_dir>/STATUS.notes.md (hand-kept notes) if it exists. Never edit STATUS.md by hand.
# Exit: 0 all done | 1 all settled, >=1 failed | 2 timeout
#       3 bad usage or cannot write STATUS.md (never a success)
#       4 an agent failed while others still run (relaunch it, then re-arm the watcher)
# WATCH_KILL_ON_TIMEOUT=1 sends TERM to still-running agents (their process group) at timeout.
set -u

usage() { echo "usage: watch.sh <round_dir> <timeout_minutes> <agent> [agent ...]" >&2; exit 3; }
[ $# -ge 3 ] || usage
dir=$1; tmo=$2; shift 2
case $tmo in ''|*[!0-9]*) echo "watch.sh: timeout must be whole minutes, got '$tmo'" >&2; usage;; esac
[ "$tmo" -gt 0 ] || usage
[ -d "$dir/out" ] || { echo "watch.sh: no such directory: $dir/out" >&2; exit 3; }
[ -w "$dir" ] || { echo "watch.sh: not writable: $dir" >&2; exit 3; }
seen=" "
for a in "$@"; do
  case $a in ''|*/*|.*) echo "watch.sh: bad agent name: '$a'" >&2; exit 3;; esac
  case $seen in *" $a "*) echo "watch.sh: duplicate agent name: $a" >&2; exit 3;; esac
  seen="$seen$a "
  [ -f "$dir/out/$a.pid" ] || echo "watch.sh: no $a.pid, treating '$a' as manual (typo?)" >&2
done
interval=${WATCH_INTERVAL:-15}
case $interval in ''|*[!0-9]*|0) interval=15;; esac

tmp="$dir/.STATUS.md.$$"
trap 'rm -f "$tmp"' EXIT
trap 'exit 130' INT TERM

alive() { # true if PID exists and is not a zombie. ps, not kill -0: no EPERM false "dead".
  case $1 in ''|*[!0-9]*) return 1;; esac
  s=$(ps -o stat= -p "$1" 2>/dev/null) || return 1
  case $s in Z*|'') return 1;; esac
  return 0
}

tsec=${WATCH_TIMEOUT_SEC:-$((tmo*60))}   # WATCH_TIMEOUT_SEC: test hook (selftest.sh)
case $tsec in ''|*[!0-9]*) tsec=$((tmo*60));; esac
start=$(date +%s); deadline=$((start + tsec))
while :; do
  now=$(date +%s); el=$((now - start)); pending=0; failed=0; live_pids=""
  {
    printf '# Swarm status (%s, %dm%02ds elapsed, timeout %s min)\n\n' \
      "$(date '+%Y-%m-%d %H:%M:%S %Z')" $((el/60)) $((el%60)) "$tmo"
    echo "| agent | state | lines | last line |"; echo "|---|---|---|---|"
    for a in "$@"; do
      f="$dir/out/$a.md"; p="$dir/out/$a.pid"; x="$dir/out/$a.exit"
      last=""; lines=0; pid=""; code=""; marker=0
      if [ -f "$f" ]; then
        last=$(grep -v '^[[:space:]]*$' "$f" | tail -n 1 | tr -d '\r')
        lines=$(grep -c -v '^[[:space:]]*$' "$f")
        clean=$(printf '%s' "$last" | tr -d '*`_' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ "$clean" = "ALL DONE" ] && marker=1
      fi
      [ -f "$p" ] && pid=$(tr -dc '0-9' < "$p")
      [ -f "$x" ] && code=$(tr -dc '0-9' < "$x")
      if [ -z "$code" ] && alive "$pid"; then
        st=running; [ $marker -eq 1 ] && st="running (marker seen, waiting for exit)"
        pending=$((pending+1)); live_pids="$live_pids $pid"
      elif [ -n "$code" ] && [ "$code" != 0 ]; then
        st="FAILED (exit $code)"; failed=$((failed+1))
      elif [ $marker -eq 1 ] && [ "$lines" -le 1 ]; then
        st="EMPTY (only the marker)"; failed=$((failed+1))
      elif [ $marker -eq 1 ]; then
        st=done
      elif [ -n "$code" ]; then
        st="NO MARKER (exited 0 without ALL DONE)"; failed=$((failed+1))
      elif [ -n "$pid" ]; then
        st="CRASHED (process gone, no marker)"; failed=$((failed+1))
      elif [ -f "$p" ]; then
        st="BAD PID FILE"; failed=$((failed+1))
      else
        st="waiting (no process: manual agent?)"; pending=$((pending+1))
      fi
      short=$(printf '%s' "$last" | cut -c1-80 | tr '|' '/')
      echo "| $a | $st | $lines | $short |"
    done
    if [ -f "$dir/STATUS.notes.md" ]; then echo; cat "$dir/STATUS.notes.md"; fi
  } > "$tmp" 2>/dev/null || { echo "watch.sh: cannot write $tmp" >&2; exit 3; }
  mv "$tmp" "$dir/STATUS.md" || { echo "watch.sh: cannot write $dir/STATUS.md" >&2; exit 3; }
  if [ "$pending" -eq 0 ]; then
    echo "ROUND FINISHED: failed=$failed"; cat "$dir/STATUS.md"
    [ "$failed" -eq 0 ] && exit 0 || exit 1
  fi
  if [ "$failed" -gt 0 ]; then
    echo "AGENT FAILED (others still running): relaunch it, then re-arm the watcher"
    cat "$dir/STATUS.md"; exit 4
  fi
  if [ "$now" -ge "$deadline" ]; then
    echo "ROUND TIMEOUT: still running:${live_pids:- none (manual agents pending)}"
    if [ "${WATCH_KILL_ON_TIMEOUT:-0}" = 1 ] && [ -n "$live_pids" ]; then
      for k in $live_pids; do kill -TERM -- "-$k" 2>/dev/null || kill -TERM "$k" 2>/dev/null; done
      echo "sent TERM to:$live_pids"
    fi
    cat "$dir/STATUS.md"; exit 2
  fi
  sleep "$interval"
done
