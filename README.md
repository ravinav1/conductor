# swarm-conductor

An agent skill that runs several AI models in parallel on the same document, plan, or idea, then merges what they write into a numbered, versioned master. It also logs its own mistakes and fixes itself over time.

The agent running the skill is the **conductor**. It doesn't do the thinking. It briefs the agents, starts them, watches them, merges their output faithfully, and reports back. The human's decisions always beat anything an agent proposes.

## Why

Asking one model to review your work gets you one opinion, usually a polite one. Running several by hand means juggling terminals, losing track of who finished, and hand-merging long outputs. This skill handles the bookkeeping:

- **Every finished agent gets noticed.** A watcher script waits for each agent to print `ALL DONE`, notices crashes, and enforces a timeout.
- **You can always see progress.** `STATUS.md` is rewritten every 15 seconds and shows each agent's state and last line.
- **Built-in pushback.** Every round has a red-team agent on a different model family. Briefs never reveal whose idea the material is, and every agent must name at least three concrete weaknesses.
- **Versioned output.** Each round produces `draft/<name>-vN.md`, a changelog saying who proposed what, and a short list of questions only the human can answer.
- **Decisions stay decided.** Items marked Decided or Parked are never reopened unless the human asks.
- **It improves itself.** Every run is logged. A friction that repeats, or any correction from the human, leads to a small, snapshotted edit to the skill.

## Requirements

- An agent that can load skills (`SKILL.md` with YAML frontmatter), such as Claude Code, Cursor, Codex, or any agent that reads markdown instructions and runs shell commands.
- At least two model CLIs it can launch headless, for example `claude -p` and `codex exec`. A web chat also works if you paste its answers in by hand.
- `bash` (3.2 or later, so the default macOS shell works) for `scripts/watch.sh`.

## Install

Copy or clone this folder into your agent's skills directory, for example:

```bash
git clone <this repo> ~/.claude/skills/swarm-conductor
```

Then say "swarm this doc" (or similar) to your agent.

## Project layout it creates

```
<project>/
  swarm/
    CONDUCTOR.md            # optional per-project settings (templates/CONDUCTOR.md)
    <round>/
      out/<agent>.md        # raw output from each agent, ending in ALL DONE
      out/<agent>.pid       # process id, used to detect crashes
      STATUS.md             # live status, written by watch.sh
      progress.log
  draft/
    <name>-vN.md            # numbered masters
    archive/                # older masters
    master-latest.md
    changelog-latest.md
    questions-latest.md
```

## CONDUCTOR.md, in one paragraph

This is an optional cheat sheet for one project: which models to use and how to launch them, where files go, the current master version, and which items are Decided, Open, or Parked. Without it the conductor works those out from the folder and asks at most one question. With it, every swarm starts from the same place. See `templates/CONDUCTOR.md`.

## Files

| Path | What it is |
|---|---|
| `SKILL.md` | The skill the agent follows |
| `scripts/watch.sh` | Completion watcher and status writer |
| `templates/CONDUCTOR.md` | Per-project settings template |
| `templates/brief.md` | Agent brief template, including the pushback rules |
| `examples/launch.sh` | Example round: two Claude agents and a Codex red-team agent |
| `CHANGELOG.md` | Version history |

## Self-improvement

The conductor appends one entry per run to an append-only log (default `~/.swarm-conductor/log.md`). It edits `SKILL.md` only when the same friction shows up twice, the human corrects it, or a completion was missed. It makes at most one edit per run and snapshots the previous version first so the change can be rolled back. The rules are in the last section of `SKILL.md`.

## License

MIT, see `LICENSE`.
