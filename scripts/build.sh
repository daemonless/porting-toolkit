#!/bin/sh
# The ONLY sanctioned way to build. Wraps `dbuild build` with:
#   - a staleness gate: refuses to run if any generated file (Containerfile,
#     Containerfile.pkg, ..., README.md) is out of date with its .j2 template
#     (edit .j2 → `dbuild generate` → build; never build a stale Containerfile)
#   - full log capture to build.log
#   - real-error detection: dbuild's wrapper can exit 0 while the inner build failed,
#     so the log is grepped for the known failure signatures automatically
#
# MUST run in the background — detached, nohup, another terminal, or your agent's
# background-execution mode (Claude Code: `run_in_background: true`). A cold
# FreeBSD build (pkg install + npm ci + compile + ZFS layer commits) routinely
# outlives the foreground tool timeout, which SIGKILLs it (exit 137) and can end
# the session. Some adapters hook-block foreground invocations.
#
# Usage: scripts/build.sh [dbuild build args, e.g. --variant TAG]

LOG="build.log"

# Prefer dbuild's content check; fall back to mtimes on a dbuild without it.
# The README is checked against the daemonless registry, which is what ships,
# even when run from a fork.
if dbuild generate --help 2>/dev/null | grep -q -- '--check'; then
  if ! DBUILD_REGISTRY="${DBUILD_REGISTRY:-ghcr.io/daemonless}" dbuild generate --check >&2; then
    echo "ERROR: generated files are stale — run \`DBUILD_REGISTRY=ghcr.io/daemonless dbuild generate\` first." >&2
    exit 1
  fi
else
  for tpl in Containerfile.j2 Containerfile.*.j2; do
    [ -f "$tpl" ] || continue
    out="${tpl%.j2}"
    if [ ! -f "$out" ] || [ "$tpl" -nt "$out" ]; then
      echo "ERROR: $tpl is newer than $out (or $out is missing) — run \`dbuild generate\` first." >&2
      exit 1
    fi
  done
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
