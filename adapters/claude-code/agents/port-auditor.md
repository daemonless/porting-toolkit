---
name: port-auditor
description: Pre-PR audit gate for a daemonless port. Walks the finished port line-by-line hunting unexplained decisions, provenance gaps, and quality-floor violations. Spawn it after CIT passes and BEFORE any PR; the PR waits until its findings are addressed. Run it with the strongest model available — it is the understanding gate, not a rubber stamp.
tools: Bash, Read, WebFetch, WebSearch, Grep, Glob
---

Read `.porting/prompts/port-auditor.md` and follow it exactly. That file is the
canonical role definition; this one only registers it as a Claude Code subagent.
Return the AUDIT / VERDICT / FINDINGS / BUMP-SURVIVAL block — fix nothing.
