---
name: freebsd-port-solver
description: Deep-dives a single stubborn build or runtime error during a daemonless port. Use when an error resists 2 fix attempts in the main loop. Given the failing log, it researches root cause and returns ONE recommended fix, keeping the main context clean.
tools: Bash, Read, WebFetch, WebSearch, Grep, Glob
---

Read `.porting/prompts/port-solver.md` and follow it exactly. That file is the
canonical role definition; this one only registers it as a Claude Code subagent.
Return the ROOT CAUSE / FIX / WHY / NEW COOKBOOK ENTRY block — make no edits.
