# daemonless porting toolkit

Shared AGENTS configuration for porting upstream apps to FreeBSD daemonless OCI
images. The procedure, cookbook and checks are plain files and shell scripts, so
they are not tied to one assistant; per-agent integration is an optional adapter.

Claude Code is the only agent this has been run with so far — an adapter ships
for it. Other agents are untested; see
[`AGENTS.md`](AGENTS.md#which-agent).

Start by reading the [Daemonless LLM / AI Contribution
Policy](https://daemonless.io/guides/llm-policy/) and jump in the Discord if you
have any questions. [`AGENTS.md`](AGENTS.md) explains what that policy means for
a port; the short version is that the agent produces the evidence and the
human writes the PR description.

## What's in here

| Path | Purpose |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Entry point for any agent: AI policy, capability requirements, layout |
| [`porting/process.md`](porting/process.md) | The porting procedure: research, scaffold, build, CIT + smoke, harden, audit, PR |
| [`porting/bump-upstream.md`](porting/bump-upstream.md) | Bump a pinned upstream version and re-validate |
| [`porting/cookbook.md`](porting/cookbook.md) | Error-signature-keyed fixes. The reason the Nth port is fast |
| [`porting/cit-and-logs.md`](porting/cit-and-logs.md) | What CIT checks, and how to capture the logs it truncates |
| [`porting/shipped-files.md`](porting/shipped-files.md) | What a finished image repo ships vs what is porting-time only (surveyed across 16 repos) |
| [`porting/prompts/`](porting/prompts/) | Three fresh-context roles: upstream research, stubborn-error deep-dive, pre-PR provenance audit |
| [`porting/templates/`](porting/templates/) | PORT-BRIEF, BUILD-NOTES, PROCESS-LOG, RUN-RECORD, PR body, smoke test, per-image `AGENTS.md` |
| [`scripts/`](scripts/) | `build.sh` (the only sanctioned build entry), `cit-with-logs.sh` (CIT + smoke + log capture), `lint-compose.sh` (metadata + quality floors), `pre-push.git-hook` (agent-agnostic CIT rail) |
| [`adapters/`](adapters/) | Optional per-agent in-session enforcement (currently: Claude Code) |
| [`docs/testing-the-toolkit.md`](docs/testing-the-toolkit.md) | The weak-model test protocol: can a mid-tier model complete a port on these docs alone? |
| [`install.sh`](install.sh) | Copy the toolkit into an image repo |

## Usage

### Install into an image repo

```sh
# from the image repo root:
/path/to/porting-toolkit/install.sh                 # with the Claude Code adapter
/path/to/porting-toolkit/install.sh --agent none    # neutral files + git rails only
/path/to/porting-toolkit/install.sh --list-agents
```

This installs `.porting/` (process, cookbook, prompts, templates), `scripts/`
(the gates), the `pre-push` git rail, and an `AGENTS.md` for the image. The
cookbook is copied, not symlinked, so it works offline.

### Refresh an existing image repo

```sh
/path/to/porting-toolkit/install.sh --refresh
```

Overwrites `.porting/`, `scripts/` and the adapter with the latest toolkit
versions. Leaves `AGENTS.md` and any local-only files alone.

### Port a new app

Point your agent at `AGENTS.md`, then `.porting/process.md`, and give it the
upstream repo URL. With the Claude Code adapter that is `/port-package <url>`;
with any other agent, "read `.porting/process.md` and port `<url>`" does the same
thing.

### Bump an upstream version

Same, with [`.porting/bump-upstream.md`](porting/bump-upstream.md) (Claude Code:
`/bump-upstream`).

## Cookbook workflow

The cookbook becomes more valuable with every port:

1. During a port, the agent appends new error-signature entries to the local copy.
2. After the port ships, PR those entries back to this repo.
3. The next `install.sh --refresh` distributes them to every image repo.

That loop is what makes the Nth port fast. See [`CONTRIBUTING.md`](CONTRIBUTING.md).
