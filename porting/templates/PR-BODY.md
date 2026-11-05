# PR description — outline for the SUBMITTER to write

**This is a checklist of what to cover, not prose to paste.** The [Daemonless
LLM / AI Contribution Policy](https://github.com/daemonless/daemonless/blob/main/LLM_POLICY.md) does not
allow AI-generated text in pull request descriptions. An agent must **not** fill
this in and hand it over; it produces the evidence below, and the person opening
the PR writes the description themselves from that evidence.

Evidence the porting session leaves behind for you to write from:

| File | What it gives you |
|---|---|
| `BUILD-NOTES.md` | every FreeBSD-specific change with its reason, the native-dep table, the guards |
| `PROCESS-LOG.md` | what actually broke at each phase and what fixed it |
| `build.log`, `cit-output.log`, `.cit-passed` | the verified build and test results |
| `port-auditor` output | provenance verdict and bump-survival answer |

---

## Cover these, in your own words

**What and why** — what the app is, and the FreeBSD-specific decisions that
mattered: runtime, DB strategy, why any dependency swap was needed.

**FreeBSD notes** — the handful of changes a reviewer needs to know about, one
line each. Pull them from `BUILD-NOTES.md`; don't restate the whole file.

**Tested** — what you ran and what you saw. Name the base image and tag. Include
the functional probe's result, not just "CIT passed": a reviewer wants to know
the app did its job, not that a port opened.

**Provenance** — confirm every non-boilerplate line traces to the port brief, a
cookbook entry, or a logged error, and list any exception with its
justification. Give the `port-auditor` verdict.

**Tradeoffs and limitations** — what this image can't do (e.g. local file DB
only, a pinned interpreter awaiting an upstream fix).

## Viva — answer these yourself

These are the three questions a reviewer will ask. Answering them is how you
demonstrate the understanding the policy requires. If you can't, the port isn't
ready.

- Why this base and runtime, and not the obvious alternative?
- What is the riskiest dependency or assumption in this image?
- What breaks first on the next upstream bump, and would it fail loud or silent?

## Disclosure

If an agent did the build loop, say so plainly in a line. That is permitted and
useful; what is not permitted is the description itself being model-written.
