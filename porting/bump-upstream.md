# Bump upstream version

You are updating an existing daemonless image to the latest upstream release. This is lighter than a full port — the image already works, you're just moving the version pin forward.

**First, read [`cookbook.md`](cookbook.md)** — version bumps can surface new native deps or syntax changes.

The operating rules and AI policy in [`process.md`](process.md) apply here too:
background builds, `.j2`-only edits, and **the human opens the PR**.

## Phase 1 — Detect current and latest versions
1. Read `Containerfile.j2` and find the pinned `ARG <APP>_VERSION=X.Y.Z`.
2. Query the upstream repo for the latest release tag:
   ```sh
   gh api repos/<owner>/<repo>/releases/latest --jq '.tag_name'
   ```
3. If already on latest, report "up to date" and stop.
4. Read the upstream changelog/release notes between current and latest for breaking changes.

## Phase 2 — Check patch compatibility
For each file in `patches/`:
1. Read the patch and identify what upstream file + line it targets.
2. Fetch the target file at the new tag and verify the patched content still exists:
   - For `.patch` files: `patch -p1 --dry-run --fuzz=0 < patches/foo.patch`
   - For script patches: check the string/pattern the script searches for
3. If a patch no longer applies:
   - Check if the upstream fix makes the patch unnecessary (drop it)
   - Or update the patch for the new code
   - Record what changed in `PROCESS-LOG.md`, for the human writing the PR description

## Phase 3 — Check for new native deps
1. Diff the upstream dependency file (package.json, requirements.txt, go.mod) between old and new tag.
2. For any new compiled/native deps, check FreeBSD availability (cookbook first, then `pkg rquery`).
3. Flag any new blockers before building.

## Phase 4 — Update + build + CIT
1. Update the `ARG <APP>_VERSION` in `Containerfile.j2` (a pkg image has no pin: the version comes from the package, so a bump is a rebuild).
2. `DBUILD_REGISTRY=ghcr.io/daemonless dbuild generate`, then `scripts/build.sh` in the background — read its PASS/FAIL verdict.
3. `scripts/cit-with-logs.sh` — CIT plus the smoke test; only this writes `.cit-passed`.
4. If Python: run `python3.XX -m compileall` to check for new syntax incompatibilities.

## Phase 5 — PR
1. Update `BUILD-NOTES.md` with the new version.
2. Branch and commit.
3. Record, for the human writing the PR description: old version → new version, any patch changes, any new deps handled.
4. **Hand it to the human to submit, and stop.** Per the AI policy, the body must
   be their words and they must be able to defend the bump in review.

## On failure
Write `WIP.md` with: the target version, which phase failed, the error, what to try next.
