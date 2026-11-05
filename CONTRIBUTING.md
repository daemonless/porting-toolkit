# Contributing to the porting toolkit

This repo is the shared procedure and accumulated knowledge behind daemonless
ports. The most valuable contribution is not code — it is a cookbook entry.

The AI policy in [`AGENTS.md`](AGENTS.md#ai-policy) applies to contributions to
*this* repo too: write your PR body yourself, and be able to explain what you
changed.

## Cookbook entries — the main contribution

[`porting/cookbook.md`](porting/cookbook.md) is keyed by **error signature**. Its
whole value is that a porter can paste a literal error line into `grep -F` and
get a verified fix. Protect that property.

An entry is four parts and nothing else:

```markdown
### <the literal error signature, as it appears in the log>
**Cause:** <the actual mechanism, one or two sentences>
**Fix:** <the exact change — Containerfile lines, patch, config key>
**Why:** <why that works, so the next person can adapt it>
```

Rules:

- **Signature first, verbatim.** Use the most distinctive line the tool actually
  prints, not a paraphrase. That is what people grep for.
- **Build-verified only.** An entry means "this was applied and the build went
  green." If you have not seen it work, it is a guess and belongs in the PR
  discussion, not the cookbook.
- **One mechanism per entry.** Two symptoms with the same root cause are one
  entry; one symptom with two causes is two entries.
- **Put it in the right runtime section** (Node, Python, Go, General). Create a
  section if your runtime has none — a stub with one real entry beats a heading.
- **No local colour.** No hostnames, usernames, private paths, or "works on my
  box" detail. Dates on a finding are fine and useful.

Entries usually arrive from a real port: the porting session appends to its local
`.porting/cookbook.md`, and the entry gets PR'd back here once the port ships.

## Changing the process

[`porting/process.md`](porting/process.md) is deliberately rigid — the operating
rules and execution discipline exist because ports fail on procedure, not
cleverness. Change them from evidence, not taste.

The evidence standard is in
[`docs/testing-the-toolkit.md`](docs/testing-the-toolkit.md): a logged run where
a model hesitated, invented a fix, ignored a rule, or needed rescue. Cite the
run in your PR. Test → rewrite, never rewrite → hope.

## Adding an agent adapter

Adapters live in `adapters/<agent>/` and add **in-session** enforcement for one
agent. They must not carry process content — a copy of the procedure is a copy
that drifts. An adapter file points at the neutral file and translates
vocabulary.

To add one:

1. Create `adapters/<agent>/` with whatever config that agent reads.
2. Make each entry point a thin wrapper: register the name/description the agent
   needs, then "read `.porting/<file>` and follow it".
3. Map the process's capability table
   (["What this process assumes of you"](porting/process.md#what-this-process-assumes-of-you))
   onto that agent — in particular how it runs a **background** command and how
   it opens a **fresh context**.
4. Add an `install.sh` case that copies the adapter and then *verifies* it landed.
   Silent adapter-install failure has bitten before: `cp -R dir/` means
   "contents" under BSD `cp` but nests a subdirectory under GNU `cp`, which
   dropped every hook on Linux installs with no symptom but an ignorable
   warning (2026-07-04). Assert an expected file is present and executable.
5. Note it in the `adapters/` table in [`AGENTS.md`](AGENTS.md) and the README.

An adapter is a convenience. `scripts/build.sh`, `scripts/cit-with-logs.sh`,
`scripts/lint-compose.sh` and the `pre-push` rail are the real gates, and they
must stay sufficient on their own — if a rule only holds when a particular
agent's hook fires, it is not enforced.

## Scripts

`scripts/` is POSIX `sh`, runs on a FreeBSD build host, and must work as an
unprivileged user with `doas` or `sudo` available (see the `PODMAN=` detection in
`cit-with-logs.sh`). Keep them dependency-free beyond `dbuild`, `podman` and base
utilities.
