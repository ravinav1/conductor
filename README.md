# conductor

An agent skill that runs several AI models in parallel on the same document, plan, or idea, then merges what they write into a numbered, versioned master. It logs its own friction and improves itself over time.

The agent running the skill is the **conductor**. It doesn't do the thinking. It briefs the agents, starts them, watches them, merges their output faithfully, and reports back. The human's decisions always beat anything an agent proposes.

## Why

Parallel review is useful when agents look at the material from genuinely different angles or on different model families. It also costs more and leaves more to reconcile, and more output is not the same as a better result. Running several models by hand means juggling terminals, losing track of who finished, and hand-merging long outputs. This skill handles the bookkeeping:

- **Recorded completion.** The launcher records each agent's exit code. The watcher counts an agent as done only when its process has exited cleanly and its answer ends with `ALL DONE`, notices crashes and early failures, and enforces a timeout.
- **Visible progress.** While the watcher runs it rewrites `STATUS.md` about every 15 seconds with each agent's state and last output line. Some CLIs print nothing until they finish, so an empty output file alone doesn't mean an agent is stuck.
- **Built-in pushback.** Every round has a red-team agent on a different model family. Briefs never reveal whose idea the material is, and agents are asked for concrete, rated critique tied to a passage and a proposed fix. There is no quota, so agents aren't pushed to invent objections.
- **Sized to the task, then converged.** There is no fixed agent count: simple material gets a few agents, hard or contested questions get more angles, fresh-context agents and every model family you allowed. When agents disagree or leave gaps, the conductor runs convergence rounds with fresh agents, who see the disputed points without names attached, until they agree or the same split survives two fresh rounds. Only those leftover splits come to you.
- **Merge or review.** By default each round produces a new master. Say "just review" and it only collects the reviews into `swarm/<round>/review.md` and `questions.md`, with no new master and no version bump.
- **Versioned output.** Each merge round produces `draft/<name>-vN.md`, a changelog saying who proposed what, and at most five questions only the human can answer. Contested proposals become questions, not edits.
- **Decisions stay decided.** Items marked Decided or Parked are never reopened unless the human asks.
- **It improves itself.** Every run is logged. A friction that repeats, or any correction from the human, leads to a small, snapshotted edit to the skill.

## Requirements

- An agent that can load skills (`SKILL.md` with YAML frontmatter) and run shell commands, such as Claude Code or Codex CLI. Any agent that follows markdown instructions works in principle.
- Signed-in, headless access to models from at least two model families, for example `claude -p` and `codex exec`. Two CLI names alone don't guarantee two families; check which model each one is set to. A web chat also works if you paste its answers in by hand.
- `bash` 3.2+ and standard `ps`, `grep`, `sed`, `tr` (the macOS and Linux defaults work).
- Each agent call sends its brief and the material to that model's provider and uses your account's quota or API credit. Because swarms are sized to the task and convergence rounds run without asking, a hard question can mean many frontier-model calls; set a spend cap in `CONDUCTOR.md` if that matters.

## Install

Clone this repo into your agent's skills folder. For Claude Code:

```bash
mkdir -p ~/.claude/skills
git clone <this repo's URL> ~/.claude/skills/conductor
```

For Codex CLI, use its skills folder instead (for example `~/.agents/skills/conductor`; check your version's docs). For other agents, put the folder wherever that agent loads skills from. If the destination already exists, inspect it rather than overwriting it.

Check the scripts on your machine before spending any tokens (about 30 seconds, no model calls):

```bash
bash ~/.claude/skills/conductor/scripts/selftest.sh
```

Then start your agent in the project that contains the document and invoke the skill (in Claude Code, `/conductor`, or just say "swarm this"). If it doesn't appear, restart the agent and check that `SKILL.md` sits directly inside the `conductor` folder.

## First swarm

For a document called `plan.md`, a good first request looks like this:

```text
Swarm ./plan.md.
Goal: find concrete weaknesses and propose a clearer, more workable next version.
Agents: a Claude critic and a Claude builder on <claude model id>, and a Codex red team on <codex model id>.
Decided: none. Parked: none.
Timeout 60 minutes, at most one retry per agent.
```

Name exact model ids. The conductor pins every agent to a model and never quietly uses a CLI's default.

What happens next:

1. The conductor copies `plan.md` to `draft/plan-v1.md` (your original is never edited), writes one brief per agent from `templates/brief.md`, records the settings in the round's `RUN.md`, and checks that each CLI is installed and signed in.
2. It tells you in one line what is launching, then starts the agents in the background and arms the watcher.
3. When the watcher exits, the conductor merges: undisputed changes go into `draft/plan-v2.md` and you get the paths to every agent's raw output.
4. If agents disagreed, it runs convergence rounds with fresh agents on the disputed points (a one-line status after each). Whatever is still split after that becomes a question for you, and you get one report for the whole run.

You don't need to write the briefs yourself, and `CONDUCTOR.md` is optional (see below).

## During and after a run

- `STATUS.md` is generated by the watcher; don't edit it by hand. Its header shows when it was last written: if that is more than a minute old, the watcher has stopped.
- **Being woken up.** The watcher is an ordinary script; on its own it can't wake an AI agent. The conductor runs it as a background job and relies on its environment to report when that job ends. Make sure your agent supports this, and that its background-job time limit is longer than the round's timeout (some harnesses stop background jobs after about 10 minutes). If your agent can't be notified, it will say so and check `STATUS.md` every time you write to it.
- **Timeouts.** A timeout ends the wait, not the agents: they keep running, and spending, until stopped. Stop them with `scripts/stop.sh <round>` or arm the watcher with `WATCH_KILL_ON_TIMEOUT=1`.
- **Retries.** A failed agent is relaunched once. The failed attempt is moved to `out/attempts/` and is never overwritten.
- **Watcher exit codes:** 0 all done · 1 finished, at least one agent failed · 2 timeout · 3 bad arguments or STATUS.md not writable · 4 one agent failed while others are still running.

## Project layout it creates

```
<project>/
  swarm/
    CONDUCTOR.md            # optional per-project settings (templates/CONDUCTOR.md)
    r01/                    # one folder per round, never reused
      RUN.md                # settings actually used: mode, models, material version, limits
      review.md, questions.md  # review mode only: summarized reviews + owner questions
      brief-<agent>.md      # the exact prompt each agent got (on stdin)
      out/<agent>.md        # the agent's final answer, ending in ALL DONE
      out/<agent>.err       # its progress and error output
      out/<agent>.pid       # launch wrapper process id
      out/<agent>.exit      # exit code, written when the agent ends
      out/attempts/         # earlier attempts of relaunched agents
      STATUS.md             # live status, generated by watch.sh
      STATUS.notes.md       # optional hand notes (e.g. web agents), shown in STATUS.md
      progress.log          # launch log
  draft/
    <name>-vN.md            # numbered masters
    archive/                # older masters
    master-latest.md        # copy of the newest master
    changelog-latest.md
    questions-latest.md
```

If the project is a git repo, you may want to ignore the per-round runtime files:

```
swarm/*/out/*.pid
swarm/*/out/*.exit
swarm/*/out/*.err
swarm/*/STATUS.md
```

## CONDUCTOR.md, in one paragraph

An optional cheat sheet for one project: which models to use (exact ids and launch commands), run limits, how the conductor gets woken, where files go, the current master version, and which items are Decided, Proposed, Open, or Parked. Without it the conductor works those out from the folder, asks at most one question, and records what it used in the round's `RUN.md`. With it, every swarm starts from the same place. See `templates/CONDUCTOR.md`.

## Running the example launcher by hand

`examples/launch.sh` starts agents and runs the watcher. It doesn't write briefs, judge answers, merge, or version anything; for the full workflow, use the skill.

```bash
mkdir -p swarm/r01
# write swarm/r01/brief-claude-critic.md, brief-claude-builder.md, brief-codex-redteam.md
CLAUDE_MODEL=<claude model id> CODEX_MODEL=<codex model id> \
  bash ~/.claude/skills/conductor/examples/launch.sh swarm/r01 60 &
```

- Briefs go in on stdin. Passing a long brief as an argument fails (Linux caps one argument at 128 KB), and `claude --allowedTools` takes several values, so it swallows a prompt placed after it.
- Each agent's model is pinned (`claude --model`, `codex exec -m`); the script refuses to start without them.
- Claude agents get read-only tools (`--allowedTools Read,Grep,Glob`). `claude -p` reads only under the folder it starts in, so launch from the project root or add `--add-dir <path>`.
- Codex runs with `--sandbox read-only` and `--skip-git-repo-check` (without it, `codex exec` refuses to run outside a git repo).
- It refuses a round folder that already has outputs. `launch.sh swarm/r01 60 codex-redteam` relaunches only that agent and archives its previous attempt.
- `scripts/stop.sh swarm/r01 [agent]` stops a round's agents, including their child processes.
- Edit `agent_cmd` in the script for other CLIs or rosters.

## Files

| Path | What it is |
|---|---|
| `SKILL.md` | The skill the agent follows |
| `scripts/watch.sh` | Completion watcher and status writer |
| `scripts/stop.sh` | Stops a round's agents |
| `scripts/selftest.sh` | Tests the scripts with stub CLIs, no model calls |
| `templates/CONDUCTOR.md` | Per-project settings template |
| `templates/brief.md` | Agent brief template, including the pushback rules |
| `examples/launch.sh` | Example round: two Claude agents and a Codex red-team agent |
| `CHANGELOG.md` | Version history |

## Self-improvement

The conductor appends one entry per run to an append-only log (default `~/.conductor/log.md`); entries are never removed or rewritten. It edits the skill only when the same friction shows up twice, the human corrects it, or a completion was missed. Small, local fixes are applied automatically; larger or important changes (hard rules, the pushback design, merge or mode behavior, script logic, or more than ~15 lines) are written to `~/.conductor/proposals.md` and applied only after the human says yes. It makes at most one edit per run, snapshots every file it touches first so the change can be rolled back, and re-runs the self-test after changing a script. If the skill folder is read-only, it records the proposed diff instead. Local edits stay in your copy; they aren't sent anywhere. The rules are in the last section of `SKILL.md`.

## License

MIT, see `LICENSE`.
