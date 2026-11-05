# PORT-BRIEF — <app>

Completed Phase 0/1 port plan (researched <date> by a stronger-context session;
facts below are verified from upstream unless marked VERIFY). Per the process's
execution-discipline rules: trust these facts, re-verify only that the pinned
tag is still the latest release, skip the research phase, start at Phase 2.

## Mission
Build the FreeBSD daemonless image for **<upstream URL>**, push the branch, and
leave the evidence for the human, who opens the PR.
Nothing else: <explicitly fence out-of-scope work — deployment, proxy wiring,
upstream feature requests>.

## Verified facts

<!-- Verify EVERY fact below against the PINNED TAG, not the default branch.
     Dependency versions drift between a release and `main`, and a brief that
     quotes `main` sends the porting session looking for a version that isn't
     there. `gh api repos/<o>/<r>/contents/<path>?ref=<TAG>` or a
     `git clone --depth 1 --branch <TAG>`, never raw.githubusercontent on a
     branch name. -->
- **Pin:** `<tag>` (latest release as of <date> — re-verify on the releases
  page before scaffolding).
- **In FreeBSD ports?** <`origin` + version from `pkg rquery '%o|%n|%v' <app>`,
  or "no". Packaged → pkg image, and most of the facts below shrink to the
  package name.>
- **License:** <license>.
- **Layout:** <where package.json / go.mod / pyproject lives; monorepo notes>.
- **Runtime:** <runtime + version, and how upstream's own Dockerfile runs it>.
- **Build:** `<build commands>`. **Start:** `<start command>`.
- **Dependencies:** <every native/compiled dep with its FreeBSD status, or
  "all pure JS/Go/py — no natives". If natives exist, map each to its cookbook
  entry here.>
- **Config (env):** <required and optional env vars with defaults>.

## Crib (mandatory — do not tour the registry)
- **Copy from `<nearest twin image>`:** `Containerfile.j2` structure,
  `root/daemonless/init.d/*` + `root/daemonless/libexec/<app>` (base-exec) or
  `root/etc/services.d/<app>/run` (legacy s6 base), `.daemonless/config.yaml`
  shape (variants and their `BASE_VERSION`).
- <one line on what differs from the twin and must NOT be copied>.

## Functional probe (mandatory — proves it WORKS, not just boots)
- CIT health: <path + expected status, and why (e.g. real /health pings an
  external dep and 503s in isolation → use / for CIT)>.
- Smoke test (`scripts/smoke-test.sh`): <one concrete request that exercises
  the app's actual purpose, and the expected response — e.g. "GET /share/x
  returns the app's own 404 page (proves routing + render), not a connection
  error">.

## Decisions already made
- **Base image:** <base-exec (one process) / base-rcd (several) / base-core
  (CLI); NOT `base` unless matching an existing image. `BASE_VERSION` per
  variant, as the twin sets it; tag verified with `skopeo list-tags`>.
- **Stays root?** <yes + why, e.g. binds a port <1024 → `ENV DAEMONLESS_USER=root`; else no>.
- **CIT mode:** <health/port/command + `cit.ready:` line if the app's startup
  log matches no default pattern>.
- <any other pre-made call: volumes, user, ports>.

## Expected traps (pre-mapped to cookbook entries)
1. <trap → cookbook entry title>.
2. <...>

## Definition of done
Per `.porting/process.md`: clean `scripts/build.sh` + CIT pass + smoke test + guards +
port-auditor CLEAN + BUILD-NOTES.md + PROCESS-LOG.md + lint-compose pass +
`dbuild lint` pass + the branch (off upstream/main) pushed to the fork + any new
cookbook entries appended. Then STOP: the human writes the description and
opens the PR.
