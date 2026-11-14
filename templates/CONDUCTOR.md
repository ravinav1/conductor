# <Project> conductor
Root: <path; default: git root if any, else the folder you started in> | Machine: <name> | Fallback: <other machine or none>
Models/agents allowed: <one line each: name, exact model id, family, launch command>
Web reasoner (optional): <tool, project/folder to use, where answers are saved>
Run limits: <round timeout (default 60 min), max attempts per agent (default 2), spend cap or "none">
Wake-up: <how this environment tells the conductor a background job ended, or "none: poll STATUS.md each turn">
Deliverables: <e.g. numbered master + changelog + questions; summaries wanted? one-liner / 30-second / 2-minute>
Layout: draft/ (masters), draft/archive/, swarm/<round>/out/, pro/
Current master: v<N> (<file>)
Run log: ~/.conductor/log.md
Decided:
Proposed:
Open (user's call):
Parked (don't touch):
Project lessons:
