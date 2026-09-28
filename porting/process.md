# Porting a package to daemonless

You are porting an upstream app to a FreeBSD `daemonless` container image built with `dbuild`. Work autonomously through the phases below, but **stop at the gates** and **never self-merge**. The reviewer reads `BUILD-NOTES.md`, not the diff — keep it accurate.

Before anything else, read [`../AGENTS.md`](../AGENTS.md) if you have not already: it
states the project's AI policy, which binds every PR this process produces.

**First, always read [`cookbook.md`](cookbook.md).** It is keyed by error signature and turns multi-hour discoveries into instant fixes. Consult it BEFORE guessing at any build/runtime error, and APPEND to it whenever you solve something new (this is the point of the system).

**Check for `WIP.md`:** if one exists, a previous session failed mid-port. Read it to understand which phase you're resuming from, what was tried, and what the last error was. Skip completed phases and pick up where it left off.

## What this process assumes of you

Any coding agent can run this process. It needs five capabilities; where yours
differs, the substitution is noted:

| Capability | Used for | If your agent lacks it |
|---|---|---|
| Read/write files | everything | — (mandatory) |
| Run shell commands | `dbuild`, `pkg`, `podman`, the `scripts/` gates | — (mandatory) |
| **Background / detached commands** | builds (operating rule 7) | run the build in a second terminal, `nohup`, or `tmux`; never a foreground call that your harness can time out |
| Fetch web pages | upstream releases, changelogs, registries | ask the human for the pages named in Phase 1 |
| **Delegate to a fresh context** ("subagents") | the three roles in [`prompts/`](prompts/) | run each prompt as a **separate session** and paste back its output block — the point is fresh context, not a specific feature |

Anything else your harness offers — planners, todo lists, memory — is optional
and mostly counterproductive here (see operating rule 9).

## Operating rules (these are where ports go wrong)
1. **Edit `Containerfile.j2` only**, never the generated `Containerfile`. After any `.j2` change run `dbuild generate`.
2. **`dbuild build` exit 0 ≠ success.** Its wrapper can exit 0 while the inner build failed. Grep the log for `error:`/`Failed`/`gyp ERR`.
3. **A green build ≠ a working image.** Always `dbuild test` (CIT). Apps crash at config-parse / migrations after building fine.
4. **`dbuild test` truncates logs on failure** — use `scripts/cit-with-logs.sh` for full log capture, or see [`cit-and-logs.md`](cit-and-logs.md) for manual capture.
5. **Pin the upstream release tag.** Never build `main`.
6. **Branch off `upstream/main`** for the PR so the diff is just your files (no fork-URL/sbom noise). If `dbuild generate` rewrote `README.md` with fork URLs, restore it before committing.
7. **Build only via `scripts/build.sh`, always in the background.** A cold build routinely outlives an agent harness's command timeout, which SIGKILLs the command (exit 137) and can end your session mid-build — no error to read, no chance to write `WIP.md`. The script also refuses a stale `Containerfile` (`.j2` newer → run `dbuild generate`) and greps `build.log` for the rule-2 failure signatures for you; read its PASS/FAIL verdict when you come back to it. `dbuild test` finishes in minutes and is fine in the foreground.
8. **The image name comes from the directory name** (`dbuild` has no config override). Work in a directory named exactly like the target image (`immich-public-proxy`, not `ipp-daemonless`), or every generated artifact — README, registry refs, built image tag — carries the wrong name, silently. Fork clones land as `<app>-daemonless` by default, so this catches people on their first port: **rename the checkout before Phase 0**. `scripts/lint-compose.sh` fails on the mismatch; cookbook: "Generated files carry the wrong image name".
9. **Do not create harness tasks or to-do plans — the phases below ARE the plan.** The only fresh contexts you open are `upstream-researcher` (Phase 1, skipped when a brief exists), `port-solver` (stubborn errors), and `port-auditor` (Phase 6 gate). Anything else is coordination overhead that produces nothing.

## Execution discipline (binding — follow mechanically)
These rules exist so the port succeeds on procedure, not cleverness. Do not
deviate from them even when you believe you see a shortcut.
- **On ANY build or runtime error, your FIRST action is** (before hypothesising):
  `grep -n -F "<the most distinctive line of the error>" .porting/cookbook.md`
  — then broaden to a keyword if no hit. A cookbook hit = apply that fix verbatim.
- **One change per build cycle — from build 2 onwards.** The initial scaffold
  necessarily lands several files before the first build; the rule binds in the
  debug loop. Never batch two FIXES into one rebuild — when it passes you won't
  know which worked; when it fails you won't know which broke it.
- **No invented fixes.** If the cookbook has no entry and your first attempt at a
  fix fails, do not keep improvising: hand the error to a fresh context using
  [`prompts/port-solver.md`](prompts/port-solver.md). If that also fails, write
  `WIP.md` and stop. An unfinished port with a clean WIP.md is a success state; a
  repo full of speculative hacks is not.
- **Never guess names or versions.** Package names: `pkg rquery '%v' <name>`
  first, every time. Upstream versions: read the releases page, never memory.
- **Verify each phase's exit gate before moving on** (generate ran clean; lint
  passed; the build log greps clean; CIT actually PASSED — not "should pass").
- **Log as you go:** append every error + what fixed it to `PROCESS-LOG.md` at the
  moment it happens, not retrospectively. New non-cookbook fixes also get a
  cookbook entry (signature → cause → fix → why) immediately. (If your agent
  supports a command-logging hook, install the adapter's `journal.sh` so
  `JOURNAL.log` is the raw recovery record when a session dies; `PROCESS-LOG.md`
  is the curated narrative you still owe on top.)
- **Provenance:** every non-boilerplate line you put in `Containerfile.j2`, the
  run scripts, or a patch must trace to the PORT-BRIEF, a cookbook entry, or an
  error you logged. If you can't say which, the line doesn't go in. The
  `port-auditor` walks this before the PR, and the project's AI policy makes it
  your responsibility to defend every line in review **in your own words**.
- **If `PORT-BRIEF.md` exists at the repo root, it is the completed Phase 1 port
  plan** — authored with stronger research context than you have. Trust its facts
  (deps, runtime, traps), re-verify only the pinned tag is still the latest
  release, skip the research phase, and go straight to Phase 2.

## Phase 0 — Intake
- **Check the directory name FIRST — before `dbuild init`, before anything.** It
  becomes the image name (operating rule 8), it is wrong from the first
  `dbuild generate`, and renaming later means regenerating every artefact. If
  the checkout is `<app>-daemonless`, `<app>-fork` or `<app>-port` — as a fork
  clone usually is — rename it to `<app>` now.
- Check for `WIP.md` — resume from there if it exists.
- Identify the upstream repo, app name, and target category/port.
- Check the registry + sibling images for a near-twin to copy.
- Resolve and pin the latest upstream **release tag**.

## Phase 1 — Research (fresh context: [`prompts/upstream-researcher.md`](prompts/upstream-researcher.md))
Get a written **port plan** before touching a Containerfile. Must answer:
- Runtime + exact version (`.nvmrc`, `go.mod`, …) and how upstream's own Dockerfile runs it (flags, `CMD`).
- Build system (pnpm/npm/yarn, vite/esbuild, monorepo workspaces).
- **Native modules** — the decisive question. List every dep with prebuilt platform binaries (`@libsql/*`, `better-sqlite3`, `sharp`, `@napi-rs/*`, `@img/*`, …). For each: does a FreeBSD prebuilt exist? Does it build from source on FreeBSD? (See cookbook — this is 80% of the work.)
- Database driver + whether it works on FreeBSD (libsql does NOT).
- **Base image shape** — long-running **service** or **one-shot CLI / non-daemon tool**? Service → `ghcr.io/daemonless/base:<tag>` (s6-supervised). CLI/tool → `ghcr.io/daemonless/base-core:<tag>` (minimal, **no** service supervision; lighter, still ships `pkg`). Tells it's a CLI: no listening port, no health endpoint, runs-and-exits, upstream ships a `bin`/command not a server. On a minimal base, add `ca_root_nss` if the build fetches over HTTPS (npm/pip/curl).
- **Base tag — `base` and `base-core` do NOT share a tag scheme.** Verify before you write a tag into a Containerfile: `skopeo list-tags docker://ghcr.io/daemonless/base` (same for `base-core`). As of 2026-09:
  - `base`: `15`, `15.1`, `15-quarterly`, `15-latest`, `15.1-latest` (plus `-amd64`/`-aarch64`). **There is no `base:15-pkg`** — it 404s with `manifest unknown`.
  - `base-core`: `15-pkg`, `15-pkg-latest`, `15.1-pkg`, … — on *this* repo the `-pkg` suffix is the correct form.
  - The `-quarterly` / `-latest` suffix selects the **pkg branch** baked in, not the FreeBSD minor. If your runtime only exists in the latest branch, a `…-latest` tag can save you the in-Containerfile `sed` (see the node cookbook entry).
- **Base version = LOWEST supported minor, not the build host's.** FreeBSD ABI compat is backward-only: a 15.0-userland image runs on 15.0 **and** 15.1 kernels, but a 15.1 image is **not** guaranteed on 15.0. So prefer the rolling major tag (`15`) over a pinned minor (`15.1`); only pin the minor if a 15.1-only feature is required (rare). Containers run on the host kernel, so this is a real runtime gate, not cosmetic.
- License + CIT: a **service** → smallest health endpoint (`health`/`port` mode); a **CLI** → `command`-mode CIT running the command to completion (e.g. `<tool> --version`) and asserting exit 0 + an `expect_output` regex (a run-and-exit tool has no live process for `shell`/`port`/`health`/`screenshot`).

## Phase 2 — Scaffold
- `dbuild init` or copy the nearest image. Set the **image class** (`x-daemonless: class:` — `service`/`cli`/`base`) explicitly. A **service** ships `compose.yaml` (with the `x-daemonless` block) + `.daemonless/config.yaml` (CIT mode, port, health). A **CLI** ships **no `compose.yaml`** — put `x-daemonless: class: cli` + `build:` + `cit: mode: command` in `.daemonless/config.yaml`. See the cookbook entry "Catalog metadata: set `x-daemonless: class:`".
- Write `Containerfile.j2`, then `dbuild generate`.
- **Verify `compose.yaml` metadata:** run `scripts/lint-compose.sh` to cross-check metadata against Containerfile LABELs. Fix mismatches before proceeding.
- **Pre-build verification:** `pkg rquery` every candidate package name before the first build. A wrong pkg name wastes a ~15-min build cycle.

## Phase 3 — Build loop
`dbuild generate → scripts/build.sh (backgrounded, per operating rule 7) → on FAIL/SUSPECT: read the real error from build.log → look up its class in the cookbook → apply the documented fix → repeat.`
If one error resists 2 attempts, hand it to a fresh context with [`prompts/port-solver.md`](prompts/port-solver.md).

## Phase 4 — Runtime test (CIT) + functional probe
- Write `scripts/smoke-test.sh` from [`templates/smoke-test.sh`](templates/smoke-test.sh), implementing the
  PORT-BRIEF's **Functional probe** (one request that exercises the app's actual
  purpose — CIT's health check only proves a process listens).
- Run `scripts/cit-with-logs.sh` — it runs CIT, captures full container logs, runs
  the smoke test, and writes `.cit-passed` (which unlocks push/PR) only when BOTH
  pass. Diagnose runtime failures (missing Temporal global, native-module load,
  DB driver shape) against the cookbook. Iterate.

## Phase 5 — Harden + complete the catalog
- **Patch-rot guard:** before every `COPY patches/x dest/x`, assert `test -f dest/x` (a COPY silently CREATES the file if upstream moved it → ships unpatched code).
- **Pin** injected native-dep versions; add a **drift guard** (e.g. sharp ↔ `@img/sharp-wasm32` must match exactly).
- **Lazy-load** optional natives with no FreeBSD build so they only fail if used.
- Keep build-only toolchains in the builder stage; discard from runtime.
- **Use standard patches where possible:** prefer `.patch` files with `patch -p1 --fuzz=0` over custom scripts. Reserve scripts for programmatic transformations. `--fuzz=0` is the drift guard (fails on context mismatch).
- **Two easy-to-miss shipped files** (see [`shipped-files.md`](shipped-files.md)): `.github/workflows/build.yaml` (from `dbuild init` — gone if you scaffolded by copying a sibling; it is a thin caller of `daemonless/dbuild`'s reusable workflow, only `image_name` differs) and `LICENSE` (the image repo's own BSD-2-Clause, not upstream's). **`sbom.json` is NOT yours to add** — CI generates and commits it after the first build on `main`.
- **Catalog screenshots (easy to forget — do it every image):** `dbuild screenshot <upstream image URL>...` downloads the app's screenshots from its README/repo into `.daemonless/screenshots/` for the daemonless catalog. Find them in the upstream README (often a `.github/`, `assets/`, or `docs/` path). (Distinct from `dbuild baseline`, which captures the CIT *comparison* shot for screenshot-mode tests.)

## Phase 6 — Audit gate, then PR (then STOP)
- `dbuild generate`; restore `README.md` if needed.
- **Check the repo is pristine.** A finished image repo ships `.daemonless/`, `.github/`, `Containerfile(+.j2)`, `README.md`, `sbom.json`, and for a service `compose.yaml` + `root/`. It does **not** ship `scripts/`, `.porting/`, adapter config, or the porting paperwork — see [`shipped-files.md`](shipped-files.md). `git status --short` should show nothing but the image's own files; `scripts/lint-compose.sh` fails if an artifact is tracked.
- Write `BUILD-NOTES.md` from [`templates/BUILD-NOTES.md`](templates/BUILD-NOTES.md) — accurate, scannable.
- Fill in `PROCESS-LOG.md` from [`templates/PROCESS-LOG.md`](templates/PROCESS-LOG.md) — record what happened at each phase.
- Fill in `RUN-RECORD.md` from [`templates/RUN-RECORD.md`](templates/RUN-RECORD.md) — cost, wall/active time, build count, what the brief got wrong, and any toolkit defects found. Get the cost and token figures from your agent's own usage report; the timings and counts come from `JOURNAL.log`.
- **Run [`prompts/port-auditor.md`](prompts/port-auditor.md) in a fresh context and address its findings.** It walks every
  line for provenance (brief / cookbook / logged error), checks BUILD-NOTES
  honesty and the quality floors, and answers bump-survival. Fix or document
  each finding (re-running build/CIT if files changed); do not open the PR
  until it returns CLEAN.
- **Get a fresh-context correctness review of the branch diff before pushing.** Most
  agents ship one (Claude Code: the built-in `/code-review`); if yours does not,
  open a new session on the diff and ask for one. This is a different gate from
  `port-auditor`, which checks provenance, not bugs. Fix each finding (re-running
  build/CIT if files changed) or record why it is dismissed in `PROCESS-LOG.md`.
- Branch off `upstream/main`, push to fork, open PR against `daemonless/<image>` using [`templates/PR-BODY.md`](templates/PR-BODY.md) — **including its Provenance and Viva sections, answered honestly in your own words** (templated non-answers are an audit failure).
- **The human opens the PR, not you.** Per the project's AI policy, the PR body
  must be the submitter's own words and the submitter must be able to defend the
  change in review, and the policy forbids AI-generated text in PR descriptions.
  Leave them the evidence (`BUILD-NOTES.md`, `PROCESS-LOG.md`, the logs, the
  audit verdict) and point them at `templates/PR-BODY.md`, which is an outline
  for them to write from. Do not write the description or post it yourself.
- Record the verified result (build, CIT: migrations / health 200 / screenshot). **Stop for human review.**
- **Delete `WIP.md`** if one exists (the port is done).

## On failure — write WIP.md
If you hit a blocker you can't resolve, or the session is ending before the port is complete:
1. Write `WIP.md` at repo root with: current phase, last error (full signature), what you've tried, what to try next.
2. Append any new cookbook entries you discovered.
3. Tell the user where things stand.

The next session's Phase 0 will pick up from `WIP.md`.

## Definition of done
`scripts/build.sh` PASSED + `scripts/cit-with-logs.sh` PASSED (real CIT **and** smoke test — boot alone is not function) AND patch-rot + drift guards in place AND `dbuild screenshot` run (catalog screenshots in `.daemonless/screenshots/`) AND `BUILD-NOTES.md` written AND `PROCESS-LOG.md` filled in AND `RUN-RECORD.md` filled in AND `scripts/lint-compose.sh` passes (including its pristine-repo check — see [`shipped-files.md`](shipped-files.md)) AND `port-auditor` returned CLEAN AND correctness-review findings fixed or dismissed-with-reason AND the evidence a human needs to write the PR description themselves (BUILD-NOTES, PROCESS-LOG, logs, audit verdict). Append any new gotcha to the cookbook.
