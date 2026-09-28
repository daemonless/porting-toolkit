# What an image repo actually ships

A finished port is a **small, boring repo**. The toolkit installs a lot of
scaffolding into your working tree so the port can be driven and audited — none
of that belongs in the commit. This file says exactly which is which, so nobody
has to decide it per-port.

Derived from the tracked contents of 16 daemonless image repos (2026-09-28):
`immich-cli`, `immich-server`, `immich-public-proxy`, `papra`, `sparkyfitness`,
`ffmpeg`, `caddy`, `jellyfin`, `vaultwarden`, `uptime-kuma`, `stump`, `n8n`,
`mealie`, `navidrome`, `transmission`, `grafana`.

## Shipped

| Path | In how many | Where it comes from |
|---|---|---|
| `.daemonless/` | 16/16 | `dbuild init`, then `dbuild logo` / `dbuild screenshot` / `dbuild baseline`. Holds `config.yaml`, `logo.svg`, `screenshots/`, `baseline-*.png` |
| `.github/` | 16/16 | **`dbuild init`** (`init.py`, `github-workflow.yaml` template). Easy to lose if you scaffold by copying a sibling instead — check it exists |
| `README.md` | 16/16 | **`dbuild generate`** — never hand-edit |
| `sbom.json` | 16/16 | **generated and committed by CI** (`github-actions[bot]`, "Update sbom.json and generated files [skip ci]"), after the first build on `main`. **Do not hand-add it to a PR** — it will not exist in a new image repo until CI has run once. `dbuild sbom` exists for local inspection, writes to `sbom-results/`, and produces a different (single-variant) shape than the committed aggregate |
| `Containerfile` + `Containerfile.j2` | 16/16 | you write the `.j2`; `dbuild generate` writes the rest. Some repos ship `Containerfile.pkg` + `.pkg.j2` instead of, or as well as, the plain pair |
| `compose.yaml` | 15/16 | you write it. **Service class only** — a `cli`-class image ships none (`immich-cli`); see the cookbook's `x-daemonless: class:` entry |
| `root/` | 15/16 | you write it: `etc/services.d/<app>/run`, `etc/cont-init.d/*`, `healthz`. CLI images have none |
| `LICENSE` | 12/16 | you add it — the **image repo's** licence (BSD-2-Clause, matching the org), not upstream's |
| `patches/` | 3/16 | only when the port patches or shims upstream source |
| app-specific config | rare | e.g. `example.env`, `postgres-template.conf` — only when the app genuinely needs a shipped sample |
| `.gitignore` | ~6/16 | `install.sh` writes one; fine to ship |

## Never committed — porting-time only

**No image repo in the survey ships any of these.** They are how the port was
produced, not part of the image.

| Path | Why it exists | Why it doesn't ship |
|---|---|---|
| `scripts/` | `build.sh`, `cit-with-logs.sh`, `lint-compose.sh`, `smoke-test.sh` | **0/16 repos ship a `scripts/` directory.** These drive and gate the port; they are not part of the image, and they come from the toolkit, so committing them forks a copy that goes stale |
| `.porting/` | the process, cookbook, prompts, templates | toolkit content — installed, refreshed, never vendored into a PR |
| `.claude/`, `CLAUDE.md`, and any other adapter files | agent integration | one agent's config has no place in a shared image repo |
| `AGENTS.md` | per-image agent entry point | same reason; regenerate it with `install.sh` when you next work on the repo |
| `PORT-BRIEF.md` | the Phase 0/1 plan | an input to the port |
| `PROCESS-LOG.md`, `RUN-RECORD.md` | what happened, what it cost | evidence you write the PR description **from** — attach or quote them, don't commit them |
| `BUILD-NOTES.md` | the rationale a reviewer reads | 1/16 ships it (`immich-public-proxy`, and that is an outlier worth cleaning up, not a precedent). Put its content in the PR description |
| `JOURNAL.log`, `build.log`, `cit-output.log`, `.cit-passed`, `WIP.md` | session artefacts | already gitignored by `install.sh` |

`install.sh` writes all of the above into `.gitignore`, so the default is safe.
`scripts/lint-compose.sh` fails if any of them is actually **tracked**, which
catches the case where someone `git add -f`'d one or installed the toolkit into
a repo that already tracked a colliding path.

## "But my port needs a script"

Then it isn't a porting script, and it doesn't go in `scripts/`:

- **Runs in the container at runtime** → `root/`. That is what `root/` is for:
  `root/etc/services.d/<app>/run` for the service itself, `root/etc/cont-init.d/`
  for one-shot setup, `root/healthz` for an external health probe (and set
  `io.daemonless.healthcheck-url` so something can find it).
- **Runs during the build** → inline it in `Containerfile.j2` as a `RUN`, or put
  it in `patches/` if it is a source transformation. A build step that only
  exists in a file the image doesn't copy is a build step that will silently
  stop running.
- **Fixes or maintains the repo itself** (regeneration helpers, one-off
  migrations) → it belongs in the toolkit or in `dbuild`, not in one image repo
  where sixteen others can't benefit from it. Send a PR.

If you think you have a genuine exception, say so in the PR description and let
a maintainer decide — don't just commit it.
