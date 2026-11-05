---
name: bump-upstream
description: 'Bump the pinned upstream version of a daemonless image to the latest release. Use when asked to "update <app>", "bump <app> version", or "check for upstream updates". Fetches latest tag, checks patch compatibility, updates the ARG, rebuilds + CITs, then stops for the human to write and open the PR.'
---

# Bump upstream version

**Read [`.porting/bump-upstream.md`](../../../.porting/bump-upstream.md) and follow
it.** The Claude Code mappings in the `port-package` skill apply here too —
notably: builds go through `scripts/build.sh` with `run_in_background: true`, and
**you do not write the PR description — the human does** (see the AI policy in
[`AGENTS.md`](../../../AGENTS.md)).
