# AGENTS.md — daemonless porting toolkit

This repository is a **toolkit**, not an image. You do not port anything here.
You install it into an image repository and run the process there.

If you are an agent reading this because someone pointed you at this repo:

1. Read [§ AI policy](#ai-policy) below. It is binding and it constrains what you
   may submit.
2. Read [`porting/process.md`](porting/process.md) — the porting procedure.
3. Install into the image repo: `<path-to-toolkit>/install.sh` from that repo's root.

---

## AI policy

**Read the [Daemonless LLM / AI Contribution
Policy](https://daemonless.io/guides/llm-policy/) before you generate anything
destined for a pull request.** It is short, it applies to every repository in
the Daemonless organization, and it is the authority here — this file only
explains what it means for a port. This toolkit exists to make ports that
satisfy it, not to route around it.

How each of its four requirements maps onto this toolkit:

| Policy requirement | How this process meets it |
|---|---|
| **Understand what you are committing** — no blind copy-paste | [`port-auditor`](porting/prompts/port-auditor.md) walks every non-boilerplate line for provenance: it must trace to the port brief, a cookbook entry, or a logged error. An unexplainable line is a finding even when the build is green |
| **Test it first** — untested AI output gets the PR closed | `scripts/build.sh` and `scripts/cit-with-logs.sh` are mandatory gates, and `.cit-passed` (which the pre-push rail checks) is only written when CIT **and** the functional smoke test both pass |
| **Keep it clean** — no leftover artifacts or verbose comments | `JOURNAL.log`, `build.log`, `cit-output.log` and `.cit-passed` are gitignored by `install.sh`; the provenance walk removes speculative lines rather than documenting them |
| **Keep communication human** — no AI-generated text in issues, PR descriptions or review comments | [`porting/templates/PR-BODY.md`](porting/templates/PR-BODY.md) is an *outline of what to cover*, explicitly not prose to paste. The agent leaves evidence; the submitter writes the description, including the three **Viva** questions |

Practical consequence for an agent running this process: **you do not open the
pull request.** You produce the branch, the build evidence, the `BUILD-NOTES.md`,
the `PROCESS-LOG.md` and the audit verdict, and you stop. **Do not write the PR
description** — the policy does not allow AI-generated text there. The person
opening the PR writes it themselves from the evidence you left behind;
[`porting/templates/PR-BODY.md`](porting/templates/PR-BODY.md) tells them what to cover.

---

## Which agent

Nothing here is written against one assistant. The process needs five
capabilities and names the substitution where an agent lacks one — see
[§ What this process assumes of you](porting/process.md#what-this-process-assumes-of-you).

**What has actually been exercised, as of 2026-09:**

| Agent | Status |
|---|---|
| Claude Code | The only agent the process has been run with. An adapter ships. Even here the cold weak-model run is incomplete — see [`docs/testing-the-toolkit.md`](docs/testing-the-toolkit.md) |
| Anything else | **Untested.** The docs are written to be neutral and the gates are plain shell, but no one has yet completed a port with another agent |

Treat "works with any agent" as the design intent, not a tested claim. If you
run a port on something else, the gaps you hit are doc bugs — log them against
[rung 5 of the test ladder](docs/testing-the-toolkit.md#test-ladder) and send a
patch.

**The checks do not depend on your agent.** They are ordinary programs:

| Gate | What it refuses |
|---|---|
| `scripts/build.sh` | a stale `Containerfile`; a build whose log contains failure signatures despite exit 0 |
| `scripts/cit-with-logs.sh` | writing `.cit-passed` unless CIT **and** the functional smoke test both pass |
| `scripts/lint-compose.sh` | a directory name that doesn't match the image name, metadata mismatches, unpinned upstream refs, unguarded patches, a toolchain in the runtime stage |
| `.git/hooks/pre-push` | any push without a `.cit-passed` marker |

[`adapters/`](adapters/) adds *in-session* enforcement for agents that support
it (for Claude Code: hooks that block foreground builds and edits to the
generated `Containerfile`). Adapters are a convenience layer. If your agent has
no adapter, the gates above still hold, and the process is unchanged.

To contribute an adapter, see [`CONTRIBUTING.md`](CONTRIBUTING.md#adding-an-agent-adapter).

---

## Repository layout

| Path | Purpose |
|---|---|
| [`porting/process.md`](porting/process.md) | The porting procedure: research, scaffold, build, CIT + smoke, harden, audit, PR |
| [`porting/bump-upstream.md`](porting/bump-upstream.md) | Bump a pinned upstream version and re-validate |
| [`porting/cookbook.md`](porting/cookbook.md) | Error-signature-keyed fixes. The crown jewel — grep it before guessing |
| [`porting/cit-and-logs.md`](porting/cit-and-logs.md) | What CIT checks, and how to capture the logs it truncates |
| [`porting/shipped-files.md`](porting/shipped-files.md) | What a finished image repo ships vs what is porting-time only (surveyed across 16 repos) |
| [`porting/prompts/`](porting/prompts/) | Three fresh-context roles: upstream research, stubborn-error deep-dive, pre-PR provenance audit |
| [`porting/templates/`](porting/templates/) | PORT-BRIEF, BUILD-NOTES, PROCESS-LOG, RUN-RECORD, PR body, smoke test, per-image `AGENTS.md` |
| [`scripts/`](scripts/) | The agent-agnostic gates, plus the git pre-push rail |
| [`adapters/`](adapters/) | Optional per-agent in-session enforcement |
| [`docs/testing-the-toolkit.md`](docs/testing-the-toolkit.md) | The weak-model test protocol: can a mid-tier model complete a port on these docs alone? |
| [`install.sh`](install.sh) | Copy the toolkit into an image repo |

`porting/` installs into an image repo as `.porting/`; paths inside it are
relative, so they resolve in both places.
