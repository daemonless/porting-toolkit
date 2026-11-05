---
name: port-package
description: 'Port a new upstream application to a FreeBSD daemonless OCI image and prepare the PR. Use when asked to "add <app> to daemonless", "build a daemonless image for <repo>", "port <app> to FreeBSD/daemonless", or to fix/refresh an existing daemonless image build. Drives the full loop — research, scaffold, build, CIT test, debug, harden, audit, build notes — then stops for the human to write and open the PR.'
---

# Port a package to daemonless

**Read [`.porting/process.md`](../../../.porting/process.md) now and follow it end to
end.** It is the canonical procedure and it is agent-neutral; this file only maps
it onto Claude Code.

Also read [`AGENTS.md`](../../../AGENTS.md) at the repo root — it carries the
project's AI policy, which binds what you may submit.

## Claude Code specifics

| `process.md` says | Here that means |
|---|---|
| "run the build in the background" | the Bash tool's `run_in_background: true`. A hook blocks foreground `scripts/build.sh` / `dbuild build` |
| "fresh context: `prompts/upstream-researcher.md`" | the `upstream-researcher` subagent |
| "fresh context: `prompts/port-solver.md`" | the `freebsd-port-solver` subagent |
| "fresh context: `prompts/port-auditor.md`" | the `port-auditor` subagent — run it on the strongest model available |
| "a fresh-context correctness review of the branch diff" | the built-in `/code-review` skill. It ships with Claude Code — it is NOT in this toolkit; do not search for it, install anything, or write a substitute |
| "do not create harness tasks or to-do plans" | no TaskCreate, no TodoWrite. The phases ARE the plan |

The hooks in `.claude/hooks/` enforce a subset of the operating rules in-session
(generated-`Containerfile*` edits, foreground builds, pushing an untested tree,
`gh pr create`, plus the
`JOURNAL.log` auto-journal). They are a convenience: `scripts/*.sh` and the git
pre-push rail are the real gates and hold regardless.
