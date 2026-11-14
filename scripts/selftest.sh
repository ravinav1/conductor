#!/usr/bin/env bash
# Self-test for watch.sh, launch.sh and stop.sh using stub CLIs: no model calls, no cost.
# Usage: bash scripts/selftest.sh     (about 30 s; prints PASS/FAIL per case)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; W="$HERE/watch.sh"; ROOT="$(cd "$HERE/.." && pwd)"
T="$(mktemp -d 2>/dev/null || mktemp -d -t conductor)"; trap 'rm -rf "$T"' EXIT
export WATCH_INTERVAL=1
pass=0; fail=0
check() { # name expected_exit actual_exit [grep-pattern-in-STATUS file]
  if [ "$2" = "$3" ] && { [ -z "${4:-}" ] || grep -q "$4" "$5"; }; then
    echo "PASS  $1"; pass=$((pass+1))
  else echo "FAIL  $1 (expected exit $2, got $3)"; fail=$((fail+1)); fi
}
newround() { rm -rf "$T/r"; mkdir -p "$T/r/out"; }
bg() { # name, seconds, output, exit code: fake agent as launch.sh runs it
  ( sleep "$2"; printf '%b' "$3" > "$T/r/out/$1.md"; echo "$4" > "$T/r/out/$1.exit"; exit "$4" ) &
  echo $! > "$T/r/out/$1.pid"
}

newround; bash "$W" >/dev/null 2>&1; check "no args -> usage error" 3 $?
bash "$W" "$T/missing" 1 a >/dev/null 2>&1; check "missing round dir -> error, not success" 3 $?
newround; bash "$W" "$T/r" 1h a >/dev/null 2>&1; check "bad timeout -> error" 3 $?
newround; bash "$W" "$T/r" 1 a a >/dev/null 2>&1; check "duplicate agent -> error" 3 $?

newround; bg a 1 'review\nALL DONE\n' 0; bg b 2 'review\n**ALL DONE**\r\n' 0
bash "$W" "$T/r" 1 a b >/dev/null 2>&1; check "all done (incl. **ALL DONE** + CRLF)" 0 $? '| b | done' "$T/r/STATUS.md"

newround; ( printf 'ALL DONE with part 1\nALL DONE\n' > "$T/r/out/a.md"; sleep 3; printf 'more\nALL DONE\n' >> "$T/r/out/a.md"; echo 0 > "$T/r/out/a.exit" ) &
echo $! > "$T/r/out/a.pid"; sleep 1
bash "$W" "$T/r" 1 a > "$T/log" 2>&1 & wp=$!; sleep 1
grep -q "marker seen" "$T/r/STATUS.md" 2>/dev/null; first=$?
wait $wp; rc=$?
check "marker mid-output while running -> not done yet" 0 $first
check "... then done once the process exits" 0 $rc
newround; bg a 1 'text\nALL DONEZO\n' 0; bash "$W" "$T/r" 1 a >/dev/null 2>&1; check "ALL DONEZO -> NO MARKER" 1 $? 'NO MARKER' "$T/r/STATUS.md"
newround; bg a 1 'review\nALL DONE\n' 2; bash "$W" "$T/r" 1 a >/dev/null 2>&1; check "marker but non-zero exit -> FAILED" 1 $? 'FAILED (exit 2)' "$T/r/STATUS.md"
newround; bg a 1 'ALL DONE\n' 0; bash "$W" "$T/r" 1 a >/dev/null 2>&1; check "only the marker -> EMPTY" 1 $? 'EMPTY' "$T/r/STATUS.md"
newround; ( sleep 1; printf 'half a review\n' > "$T/r/out/a.md" ) & echo $! > "$T/r/out/a.pid"
bash "$W" "$T/r" 1 a >/dev/null 2>&1; check "process gone, no marker, no exit file -> CRASHED" 1 $? 'CRASHED' "$T/r/STATUS.md"
newround; : > "$T/r/out/a.pid"; bash "$W" "$T/r" 1 a >/dev/null 2>&1; check "empty pid file -> BAD PID FILE" 1 $? 'BAD PID FILE' "$T/r/STATUS.md"
newround; bg a 1 'oops\n' 1; bg b 30 'x\nALL DONE\n' 0
bash "$W" "$T/r" 1 a b >/dev/null 2>&1; check "early failure while others run -> exit 4" 4 $?
kill -- -"$(cat "$T/r/out/b.pid")" 2>/dev/null; kill "$(cat "$T/r/out/b.pid")" 2>/dev/null
newround; echo "note: web agent pasted at 21:00" > "$T/r/STATUS.notes.md"
( sleep 2; printf 'web answer\nALL DONE\n' > "$T/r/out/web.md" ) &
bash "$W" "$T/r" 1 web >/dev/null 2>&1; check "manual agent + notes kept" 0 $? 'web agent pasted' "$T/r/STATUS.md"
newround; sleep 30 & echo $! > "$T/r/out/a.pid"; sp=$!
WATCH_TIMEOUT_SEC=2 WATCH_KILL_ON_TIMEOUT=1 bash "$W" "$T/r" 1 a >/dev/null 2>&1; rc=$?; sleep 1
if kill -0 $sp 2>/dev/null; then kill $sp; rc=killfailed; fi
check "timeout -> exit 2, agent stopped with WATCH_KILL_ON_TIMEOUT=1" 2 $rc

# launch.sh + stop.sh end to end with stub claude/codex on PATH
mkdir -p "$T/bin"
cat > "$T/bin/claude" <<'S'
#!/usr/bin/env bash
cat >/dev/null; sleep "${STUB_SLEEP:-1}"; echo "stub review by claude $*"; echo "ALL DONE"
S
cat > "$T/bin/codex" <<'S'
#!/usr/bin/env bash
cat >/dev/null; sleep "${STUB_SLEEP:-1}"; echo "stub review by codex $*"; echo "ALL DONE"
S
chmod +x "$T/bin/claude" "$T/bin/codex"
export PATH="$T/bin:$PATH" CLAUDE_MODEL=stub-claude CODEX_MODEL=stub-codex
L="$ROOT/examples/launch.sh"; R="$T/round"; mkdir -p "$R"
for a in claude-critic claude-builder; do echo "brief" > "$R/brief-$a.md"; done
bash "$L" "$R" 1 >/dev/null 2>&1; check "launch.sh: missing brief -> nothing launched" 1 $?
[ -e "$R/out/claude-critic.pid" ] && { echo "FAIL  launch.sh launched with a missing brief"; fail=$((fail+1)); }
head -c 300000 /dev/zero | tr '\0' 'x' > "$R/brief-codex-redteam.md"   # > 128 KB: stdin, not argv
bash "$L" "$R" 1 >/dev/null 2>&1; check "launch.sh: full round with a 300 KB brief, models pinned" 0 $? 'codex-redteam | done' "$R/STATUS.md"
grep -q -- "-m stub-codex" "$R/out/codex-redteam.md"; check "launch.sh: codex model pinned" 0 $?
bash "$L" "$R" 1 >/dev/null 2>&1; check "launch.sh: refuses to reuse a round" 1 $?
bash "$L" "$R" 1 codex-redteam >/dev/null 2>&1; check "launch.sh: relaunch one agent" 0 $?
[ -f "$R/out/attempts/codex-redteam.1.md" ]; check "launch.sh: earlier attempt archived" 0 $?
R2="$T/round2"; mkdir -p "$R2"; for a in claude-critic claude-builder codex-redteam; do echo b > "$R2/brief-$a.md"; done
STUB_SLEEP=30 bash "$L" "$R2" 1 > /dev/null 2>&1 & lp=$!; sleep 2
bash "$HERE/stop.sh" "$R2" >/dev/null 2>&1; wait $lp; rc=$?
sleep 1; left=0; for p in "$R2"/out/*.pid; do kill -0 "$(cat "$p")" 2>/dev/null && left=1; done
pgrep -f "$T/bin/" >/dev/null && left=1
[ $left -eq 0 ] && [ $rc -eq 1 ]; check "stop.sh: stops the round's process trees" 0 $?

echo; echo "$pass passed, $fail failed"; [ $fail -eq 0 ]
