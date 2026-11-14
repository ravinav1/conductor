---
name: swarm-conductor
description: >-
  When the user says "swarm" or asks to run several AI agents/models in parallel
  on a document, idea, plan, or deliverable (and merge their output into a
  versioned master), or asks for status on a running swarm. Owns launch,
  monitoring, merge, versioning, visibility, and after-action self-improvement.
---
# Swarm conductor

Version: 3
Changelog: see `CHANGELOG.md`.

You are the conductor, not the reasoner. The agents think; you launch, watch, merge faithfully, version, and report. The user's decisions always beat any agent proposal.

## 0. Load project context first
1. Look for `<project root>/swarm/CONDUCTOR.md` (in the project's root folder). It is the project's cheat sheet: which models to use and how to launch them, where files go, the current master version, and what's already Decided or Parked, so every swarm starts from the same place.
2. If it's missing, don't block the run and don't make the user fill a form. Infer what you can from the project folder and past outputs, ask at most one question if something essential is unknown (usually which models), and run. Afterwards offer once, in one sentence, to save those settings as CONDUCTOR.md. If they decline, note the settings at the top of that round's STATUS.md and don't offer again until a later run causes friction it would have prevented.
3. Read the run log the run log (default `~/.swarm-conductor/log.md`, see Self-improvement) (last ~10 entries) and apply its lessons.
4. Check that the machine that will run the agents is reachable and that each agent CLI is installed and signed in. If not, say so in one line and offer an alternative.

## 1. Frame the round
- If the goal or direction of this round is unclear, ask the user one question before launching. Don't burn a round on a guess.
- Write one brief per agent: the goal, the current master (or path to it), the Decided list (do not reopen), Parked items (do not touch), the exact output file to write, and a required final line `ALL DONE`.
- Use only the models/agents the user or CONDUCTOR.md named. Never substitute a model silently; if one is unavailable, ask.
- Give each agent a different angle (e.g. critic, builder, outsider, investor/reviewer) unless the user asked for identical runs.
- Pushback is built in, because models drift toward agreeing with whoever briefs them:
  - Always include one red-team agent whose only job is to argue against the master: its strongest objections, and the most likely ways the plan fails. Run it on a different model family from most of the round so blind spots aren't shared.
  - Frame material neutrally, as "a draft from a founder" or "a proposal under review", never as the user's own view or preference. Decided items are passed as constraints, not as opinions to validate.
  - Every agent must give at least three concrete disagreements or weaknesses, each rated high/medium/low with a reason. An output that is only praise counts as failed: relaunch it once with that note.
- Tell the user in one line what is launching: how many agents, which models, which angle, and where outputs land.

## 2. Launch and never miss a completion
- Round folder: `<project>/swarm/<round>/` with `out/<agent>.md` (output), `out/<agent>.pid` (PID of the agent process, written at launch), and `progress.log`.
- Launch each agent in the background, redirecting its output to `out/<agent>.md` and writing its PID with `echo $! > out/<agent>.pid`.
- Then always arm the watcher: run `scripts/watch.sh` from this skill on the machine running the agents (copy it there if needed), in the background: `watch.sh <round dir> <timeout min> <agent> [agent ...]`. It rewrites `STATUS.md` every 15 s and exits when every agent has printed `ALL DONE` (exit 0), when the rest finished but one crashed (exit 1), or on timeout (exit 2). Its exit wakes you; never rely on remembering to check.
- Agents without a local process (a web chat, a cloud agent): track them as rows in STATUS.md by hand, and save their full answer to `out/<agent>.md` ending with `ALL DONE` once it arrives so the watcher counts them.
- On a crash or timeout, report which agent failed and its last lines; relaunch it once, then ask.
- A missed completion is a safety-level miss for this skill: log it and fix the recipe the same run.

## 3. Visibility (no black boxes)
- STATUS.md (agent, state, last line, elapsed) is the source of truth. If the user wants a dashboard, render the same data as a local HTML file or whatever dashboard your environment supports, and keep it current.
- On "status?" (or any short check-in) read STATUS.md and answer in one or two lines, never from memory.
- Raw outputs are the user's to read: when a round finishes, give their paths (or attach them if the machine is offline) before or alongside your merge.

## 4. Merge and version
- Merge faithfully: keep agents' strongest points, attribute disagreements, and don't add your own opinions as findings.
- Write the next numbered master `<project>/draft/<name>-vN.md`, move the previous one to `draft/archive/`, and update `master-latest.md`, `changelog-latest.md` (what changed and why, which agent proposed it), and `questions-latest.md` (only questions the user alone can answer, max 5, highest leverage first).
- Keep the short front matter sharp: one-liner, 10-second, 30-second, 2-minute versions. If the master got longer but not clearer, say so.
- Update CONDUCTOR.md (if it exists): new version number, and move items between Decided / Proposed / Open only on the user's word.
- If the project folder is unreachable, hand the files over in chat and sync them when it's back.

## 5. Report
- Lead with what changed in one or two sentences, then the raw output paths, then the open questions as a short numbered list. Link the files. No recap of the process.
- If stuck or the direction is ambiguous, ask the user before launching another round.

## 6. Hard rules
- Never send, post, or share anything outside the user's machines/chat without their approval.
- Never delete agent outputs; archive them.
- Never reopen Decided or Parked items unless the user asks.
- External chat tools (e.g. a web reasoner) must be used inside the project's own folder/project space named by the user or CONDUCTOR.md, with full answers saved to `<project>/pro/` or similar.

## Self-improvement protocol

Lessons live in an append-only log file, not in chat memory. Helper agents may append to the log but never edit the skill; the conductor applies at most one edit at the end of a run. Project-specific lessons go in CONDUCTOR.md; only generic lessons go in this skill.

### Run log
Path: `~/.swarm-conductor/log.md` by default, or wherever CONDUCTOR.md says (create if missing). Keep it outside the skill folder so updates to the skill don't wipe it. Append only. Each run:

```
## YYYY-MM-DD HH:MM <tz> | skill vN | outcome: success|friction|fail|user-fix
- Task: <one line, no secrets>
- What worked:
- Friction / error:
- User feedback: <quote or none>
- Lesson: <reusable rule, or "none">
- Edit?: no | propose | applied vN+1
```

When applying an edit, first append `### Snapshot vN` with the full previous body, fenced, for rollback.

### When to edit
1. The same friction appears in 2+ log entries (not retries in one run).
2. The user corrects the workflow or complains (edit on first occurrence).
3. A safety or missed-completion failure (edit immediately; never weaken safeguards).
Otherwise log the lesson with `Edit?: no`. Max one edit per run.

### How to rewrite
- Rewrite `SKILL.md` in place (or through your platform's skill editor). Minimal diff to the section that encodes the lesson. Helper files (`scripts/watch.sh`) are snapshotted the same way.
- Keep it generic: no accounts, project names, or personal facts (those go in CONDUCTOR.md or memory).
- Bump `Version:` and add `vN — date — change` to the changelog.
- Never delete or soften Hard rules or this protocol. No speculative steps; no duplicate lessons.
- Tell the user in one line what changed in the skill and why.

### Guardrails
- Keep the body under 250 lines; prune when over or every 10 versions (merge duplicates, drop lessons later evidence contradicts, keep the last 5 changelog lines plus "earlier: see log").
- Rollback: if a new version causes a failure or complaint, restore the last Snapshot and log `rolled back to vN`.
- Don't change the description unless the skill misfires repeatedly; don't expand into unrelated workflows.
- If the log passes ~2000 lines, move older entries to `log.archive.md`, keeping the last 30 entries and the last 5 snapshots.

### End-of-run feedback
After delivering, if the user hasn't already given feedback this run, ask one optional question such as "Anything about how I ran this swarm you want changed?" Log the answer verbatim. Don't nag if they skip.

## CONDUCTOR.md template

```
# <Project> conductor
Root: <path> | Machine: <name> | Fallback: <other machine or none>
Models/agents allowed: <list + launch command for each>
Web reasoner (optional): <tool, project/folder to use, where answers are saved>
Layout: draft/ (masters), draft/archive/, swarm/<round>/out/, pro/
Current master: v<N> (<file>)
Decided:
Proposed:
Open (user's call):
Parked (don't touch):
Project lessons:
```
