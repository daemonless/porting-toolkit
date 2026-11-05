# Weak-model testing — can the toolkit carry a port without a strong pilot?

*Last updated 2026-09-28. Status: first cold PASS recorded (Run 2, rung 3).*

## The claim being tested

A port succeeds or fails on **procedure, not cleverness**. If that's true, the
toolkit's docs should let a mid-tier model complete a real port unaided. If it
can't, the docs — not the model — get patched. The docs are done when the
weakest model anyone would realistically use stops needing rescue.

This is also how the docs stay agent-neutral in fact and not just in wording: a
run on a different agent that trips over a Claude-shaped assumption is the same
kind of evidence as a run that trips over a missing cookbook entry.

## Design principles (what "weak-model-proof" means)

A weaker model doesn't lack knowledge — the cookbook holds the knowledge. It
fails in four predictable ways, each answered by a doc layer:

| Failure mode | Countermeasure | Where |
|---|---|---|
| Theorises instead of looking up | Binding rule: first action on ANY error is a literal `grep -F` of the cookbook (exact command given inline) | `porting/process.md` "Execution discipline" |
| Batches speculative fixes | One change per build cycle, verify each phase gate | same |
| Invents names/versions/fixes | `pkg rquery` every name; no fix not in the cookbook after 1 failed attempt → `porting/prompts/port-solver.md` in a fresh context → `WIP.md` and STOP. "A clean WIP.md is a success state; a repo of speculative hacks is not." | same |
| Burns judgement it doesn't have | **`PORT-BRIEF.md` pattern**: a strong-model session does Phase 0/1 once — verified deps, pinned tag, base/CIT decisions, traps pre-mapped to cookbook entries, scope fenced. The process detects the brief and skips research. Strong model plans; weak model executes. | brief at image-repo root |

Plus rails that must actually exist. The agent-agnostic ones (`scripts/*.sh`, the
`pre-push` hook) are the floor; an adapter's in-session hooks are a bonus layer.

**Found 2026-07-04:** `install.sh` silently dropped every adapter hook on GNU-cp
systems (BSD trailing-slash `cp -R dir/` semantics don't port; now `dir/.`).
Weak-model safety depends on rails installing — the only symptom was an
ignorable chmod warning. Lesson: **verify the rails installed before starting a
run**, and have `install.sh` assert it (it now does).

## Test protocol

1. Stage an image repo: `install.sh` from this toolkit + a `PORT-BRIEF.md`
   authored by a strong-model session. Verify the gates landed and are
   executable (`ls -l scripts/*.sh .git/hooks/pre-push`, plus the adapter's own
   files if one was installed).
2. Run **cold**: fresh session, weaker model, zero conversational context —
   that's what "the docs are sufficient" means, and it's how third-party users
   experience the toolkit. **Do not coach mid-run.** Give it only the entry
   point and the upstream URL:
   ```
   read AGENTS.md, then .porting/process.md, and port <upstream-url>
   ```
   (or the adapter's equivalent — with Claude Code, `/port-package <url>`).
3. **`JOURNAL.log` is the measuring instrument; `PROCESS-LOG.md` is the
   narrative.** Where the agent supports a command-logging hook the journal is
   automatic, so the instrument no longer depends on the discipline of the model
   being measured (run 1 wrote zero PROCESS-LOG entries in 121 turns). Where it
   doesn't, the session transcript is the fallback instrument. Afterwards, a
   strong-model session grades the run — journal + transcript + PROCESS-LOG:
   every hesitation, wrong turn, invented fix, ignored rule, or rescue is a
   DOC GAP, not a model failure. Patch the docs from that evidence.
   Test → rewrite, never rewrite → hope.
4. Outcomes: PASS (CIT green, evidence complete, no rescue) · PASS-WITH-GAPS (done, but
   the log shows doc friction — patch docs) · CLEAN FAIL (WIP.md written per
   the rules — patch docs, rerun) · DIRTY FAIL (flailed, broke discipline —
   the discipline section itself needs strengthening) · HARNESS FAIL (killed
   by the harness — tool-timeout SIGKILL, crash — before discipline could
   apply; fix the trap in TOOLING, not prose, and rerun).

## Test ladder

| Rung | Port | Why | Status |
|---|---|---|---|
| 1 | `immich-public-proxy` | Pure-JS, zero native modules, no DB — isolates *process* from *gnarl*. Brief pins v3.0.1. | RUN 1: HARNESS FAIL (see log); port finished by a strong model. **Cold re-run pending** to validate the patches. |
| 2 | `ffmpeg` | CLI class + pkg-based port — tests the `cli` layout (no compose.yaml, command-mode CIT) and the brief's don't-copy discipline (the nearest twin has an invalid category label). First run on the post-run-1 rails. | STAGED 2026-07-04 |
| 3 | something with one native module (sharp- or sqlite-class) | Tests cookbook lookup under real pressure | **PASS 2026-09-28** — run on `actual` (3 natives, harder than the rung intended). See Run 2 |
| 4 | a Python/FastAPI app | Tests the second runtime section cold | — |
| 5 | any rung, on a **different agent** | Tests that the neutral docs are actually neutral, and that `--agent none` is sufficient | — |

## Log of runs

*(append per run: date, agent + model, port, outcome, gaps found → doc patches made)*

### Run 2 — 2026-09-28 · Claude Code / Sonnet (+ Opus for the audit) · actual (rung 3) · PASS

First cold run to finish unaided. 80 min wall / 38 min active, US$15.17, 7 builds,
3 CIT runs, 727 lines added. Full figures in that port's `RUN-RECORD.md`.

- **Procedure held throughout.** Read the cookbook first; trusted the brief and
  skipped research per the rules; re-verified the pinned tag; `pkg rquery`'d
  every package name before the first build; `.j2`-only edits; one fix per build
  cycle across a four-build debug loop; wrote `PROCESS-LOG.md` as it went; no
  harness tasks created; stopped at the audit gate without pushing, as the brief
  instructed.
- **Hit three genuinely novel failures and solved all three** without a
  `port-solver` escalation: `lage`'s `glob-hasher` and Microsoft's `tsgo` both
  crash on FreeBSD (NAPI-RS prebuilts for win32/darwin/linux only, no source
  build), and `yarn workspaces focus` silently omits root devDependencies. Wrote
  pure-JS shims wired via yarn `resolutions`, each with a stated safety argument
  and a drift guard that checks the load-bearing assumption rather than mere
  file presence. All four became cookbook entries.
- **Caught a real doc bug in this toolkit and refused to paper over it.** The
  process doc and the port brief both said to use `base:15-pkg`; that tag 404s
  on `ghcr.io/daemonless/base`. It verified by pulling, built against `base:15`,
  corrected `BUILD-NOTES.md` to state what was actually built, and flagged the
  discrepancy for a human instead of quietly picking one. (Follow-up found the
  full story: `-pkg` exists on `base-core` but not `base` — now a cookbook entry
  and a corrected Phase 1 rule.)
- **Ran the audit gate and a fresh-context correctness review in parallel**, then
  fixed and rebuilt: a tautological patch-rot guard, a hardcoded vendored-yarn
  filename that would break on the next bump, two unused packages, a redundant
  recursive chown over a large `node_modules`, an unwired healthcheck file, and
  two smoke-test gaps.
- **Doc/tooling gaps found → patches made:** `cit-with-logs.sh` printed dbuild's
  stdout then deleted it, so the Phase 4 CIT transcript could only be
  paraphrased (now appended to `cit-output.log`); `lint-compose.sh` extracted
  `io.daemonless.healthcheck-url` and never checked it (now checked, and warns
  on a shipped `root/healthz` with no label); `lint-compose.sh`'s patch-rot check
  is satisfied by a tautological `test -f` immediately after the `COPY` that
  would already have failed — the run added one to pass the linter and a real
  guard separately, and said so.
- **Brief-authoring defects (the strong-model side, not the run's fault):** the
  brief quoted `better-sqlite3 ^13.0.3` from the default branch when the pinned
  tag has `^12.11.1`, and left sharp as an "open question" the run had to
  resolve from `yarn.lock`. `templates/PORT-BRIEF.md` now says to verify every
  fact against the pinned tag, never a branch.
- **Verdict: PASS.** No rescue, no coaching, `.cit-passed` earned by a real
  health check plus a two-probe smoke test. The rung-3 claim is now evidenced —
  with the caveat that this app was harder than rung 3 specified (three native
  compiles, Yarn Berry, a monorepo orchestrator), so an *easier* one-native port
  remains unproven.

### Run 1 — 2026-07-04 · Claude Code / Sonnet · immich-public-proxy (rung 1) · HARNESS FAIL
- **Good (procedure held):** cookbook read first; trusted the brief and skipped
  research per the rules; re-verified only the pinned tag; `pkg rquery`'d every
  package name; `.j2`-only edits; generate → lint gates in order; correct
  `/`-vs-`/healthcheck` CIT call. The scaffold it wrote later built and passed
  CIT unchanged.
- **Killed:** a foreground `dbuild build` was SIGKILLed at the harness's 600s
  command ceiling (turn 121, mid-`npm ci`); session died; no WIP.md possible.
- **Model-attributable gaps → patches made:** zero PROCESS-LOG writes in 121
  turns (→ the adapter's `journal.sh` auto-journal hook); created 7 harness
  tasks it never used (→ operating rule 9 forbids); ~40 turns touring 4 sibling
  repos because the brief said "check the registry" (→ mandatory **Crib**
  section in `porting/templates/PORT-BRIEF.md`); "one change per build cycle"
  ambiguous for the initial scaffold (→ scoped to build 2+).
- **Tooling patches:** foreground builds now hook-blocked +
  `scripts/build.sh` wrapper; `cit-with-logs.sh` privilege-prefix fix;
  `cit.ready` cookbook entry; git pre-push rail; smoke-test gate;
  `port-auditor` PR gate.
- **Caveat:** all patches since the kill are strong-model-authored and
  weak-model-UNVALIDATED. Rung 1 must be re-run cold (fresh easy port, or this
  one from scratch in a throwaway dir) before the toolkit's claim is credible.
