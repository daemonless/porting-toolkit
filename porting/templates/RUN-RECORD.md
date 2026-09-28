# RUN RECORD — `<image>`

One per port. Cheap to fill, and the only way the project learns what a port
actually costs rather than what it feels like. Commit it alongside
`BUILD-NOTES.md` and `PROCESS-LOG.md`.

Numbers come from your agent's own usage report (Claude Code: `/cost`), from
your own telemetry if you run any, and from `JOURNAL.log` for the timings and
counts. Where a number isn't available, write `n/a` — don't estimate.

## Run

| | |
|---|---|
| **Image / upstream tag** | `<image>` @ `<tag>` |
| **Date (UTC)** | `<YYYY-MM-DD>` |
| **Outcome** | PASS / PASS-WITH-GAPS / CLEAN FAIL / DIRTY FAIL / HARNESS FAIL |
| **Agent + model(s)** | `<e.g. Claude Code, Sonnet main loop + Opus for the audit>` |
| **Cold or warm start** | cold (no conversational context) / warm |
| **Port brief present?** | yes / no |

## Cost and effort

| | |
|---|---|
| **Total cost** | `<USD>` |
| **Cost by model** | `<model: $x; model: $y>` |
| **Wall time** | `<h:mm>` (first to last entry in `JOURNAL.log`) |
| **Active time** | `<h:mm>` (`<N>%` of wall — the rest is waiting on builds) |
| **Tokens** | in `<n>` · out `<n>` · cache read `<n>` · cache write `<n>` |
| **Commands journalled** | `<N>` (`wc -l JOURNAL.log`) |
| **Lines added / removed** | `<n>` / `<n>` |

## Build

| | |
|---|---|
| **Builds run** | `<N>` (`grep -c 'scripts/build.sh' JOURNAL.log`) |
| **Cold build time** | `<mm:ss>` |
| **CIT runs** | `<N>` |
| **Peak `NODE_OPTIONS` / memory setting** | `<if applicable>` |

## What the brief got wrong

The highest-value field here. Anything the port brief asserted that turned out
to be false, stale, or checked against the wrong ref. Each of these is a bug in
how briefs get written, not in the port.

- `<claim>` → `<what was actually true, and how it was verified>`

## Cookbook entries added

- `<signature → one-line summary>`

## Toolkit defects found

Bugs in the shared `scripts/`, `porting/` docs or the process itself — things a
port shouldn't have to fix locally. Report them upstream rather than patching
around them.

- `<file>` — `<defect>`
