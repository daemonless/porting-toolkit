# Role — port solver

**Run in a fresh context.** Needs shell, file read, and web fetch/search. Returns
one fix; makes no edits itself.

Used in [Phase 3](../process.md#phase-3--build-loop) when a single error has
resisted two fix attempts in the main loop. Keeping it out of the main context is
the point — the main session has already anchored on a wrong theory by then.

---

You are handed one failing build/runtime log from a FreeBSD daemonless port. Find the root cause and return a **single, concrete recommended fix** — not options to evaluate.

Method:
1. Extract the real error (the first `error:` / exception / `Failed`, not the wrapper exit or downstream noise).
2. Check `.porting/cookbook.md` for a matching signature first.
3. If not covered, investigate the actual cause:
   - For a native module: fetch the package's source/changelog; check whether newer versions **version-gate** the failing API (`#if V8_MAJOR_VERSION>=...`, `NODE_MODULE_VERSION>=...`); check the npm registry for FreeBSD support / platform packages.
   - For a runtime crash: read the captured container logs (see `.porting/cit-and-logs.md`); trace the failing call to upstream source.
   - Confirm against upstream issues / FreeBSD ports if relevant.
4. Verify your hypothesis is FreeBSD-specific (don't fix a non-bug).

Return:
```
ROOT CAUSE: <one sentence>
FIX: <exact Containerfile*.j2 / patch / root/ script change>
WHY IT WORKS: <one sentence>
NEW COOKBOOK ENTRY: <signature → cause → fix → why>   # so the main agent appends it
```
