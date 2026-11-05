# PROCESS LOG — porting `<owner/repo>` to a FreeBSD daemonless image

<!-- Fill this in as you go. Record what actually happened, not what the process says should happen.
     The value is in the surprises — what broke, what the cookbook didn't cover, what you added to it. -->

## Phase 0 — Intake
- Target: `<upstream URL>`, pinned to release **`<tag>`** (<license>).
- Prior art: `<nearest sibling image copied, or "scaffold fresh">`.

## Phase 1 — Research
<!-- Paste the upstream-researcher's port plan summary here -->
- Runtime: `<runtime + version>`
- Build: `<build system>`
- Native hazards: `<list with FreeBSD status>`
- DB: `<driver + strategy>`
- Health: `<endpoint>`
- Verdict: `<EASY / MODERATE / HARD — blockers?>`

## Phase 2 — Scaffold
- `<what was scaffolded, any pre-build verification findings>`
- Package name surprises: `<any pkg names that weren't what you expected>`

## Phase 3 — Build loop
<!-- Record each real error and how it was fixed. This is the most useful section. -->
- Build 1: `<result — error or success>`
- Build 2: `<if needed — what broke, what fixed it>`
- ...

## Phase 4 — CIT
```
<paste the CIT output here>
```
- Runtime issues found: `<list, or "none">`

## Phase 5 — Harden
- Guards added: `<patch-rot, drift, lazy-load>`
- Screenshots: `<dbuild screenshot done? how many?>`

## Phase 6 — PR
- PR: `<URL>`
- Final status: build ✅/❌, CIT ✅/❌

## Cookbook entries added
<!-- List any new entries you appended to the cookbook during this port -->
- `<signature → one-line summary>`

## Lessons / notes for next time
- `<anything surprising that isn't captured in the cookbook>`
