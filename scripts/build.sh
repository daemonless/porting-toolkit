#!/bin/sh
# The ONLY sanctioned way to build. Wraps `dbuild build` with:
#   - a staleness gate: refuses to run if Containerfile.j2 is newer than Containerfile
#     (edit .j2 → `dbuild generate` → build; never build a stale Containerfile)
#   - full log capture to build.log
#   - real-error detection: dbuild's wrapper can exit 0 while the inner build failed,
#     so the log is grepped for the known failure signatures automatically
#
# MUST run in the background — detached, nohup, another terminal, or your agent's
# background-execution mode (Claude Code: `run_in_background: true`). A cold
# FreeBSD build (pkg install + npm ci + compile + ZFS layer commits) routinely
# outlives the foreground tool timeout, which SIGKILLs it (exit 137) and can kill
# the whole session (2026-07-04). Some adapters hook-block
# foreground invocations.
#
# Usage: scripts/build.sh [dbuild build args, e.g. --variant TAG]

LOG="build.log"

if [ -f Containerfile.j2 ] && [ -f Containerfile ] && [ Containerfile.j2 -nt Containerfile ]; then
  echo "ERROR: Containerfile.j2 is newer than Containerfile — run \`dbuild generate\` first." >&2
  exit 1
fi

echo "[build] dbuild build $* > $LOG"
dbuild build "$@" >"$LOG" 2>&1
STATUS=$?

if [ "$STATUS" -ne 0 ]; then
  echo "[build] FAILED (exit $STATUS). Last 40 lines of $LOG:" >&2
  tail -40 "$LOG" >&2
  echo "[build] Now grep the full $LOG for the FIRST real error, then look up its signature in the cookbook." >&2
  exit "$STATUS"
fi

# Wrapper exit 0 is not proof — hunt the log for real failure signatures.
HITS=$(grep -nE 'error:|Failed|FAILED|gyp ERR' "$LOG" | grep -viE '0 failed|error: 0|warnings? treated' || true)
if [ -n "$HITS" ]; then
  echo "[build] exit 0 but the log contains failure signatures — inspect before trusting:" >&2
  echo "$HITS" | head -20 >&2
  echo "[build] SUSPECT — verify these are benign, or treat the build as failed." >&2
  exit 1
fi

echo "[build] PASSED — no failure signatures in $LOG. Next gate: scripts/cit-with-logs.sh"
exit 0
