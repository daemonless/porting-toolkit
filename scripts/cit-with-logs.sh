#!/bin/sh
# Wraps `dbuild test` with automatic full log capture.
# On failure, the real stack trace is in cit-output.log (not dbuild's truncated tail).
# On success, writes a .cit-passed marker so the enforce-cit hook allows PRs.
#
# Usage: scripts/cit-with-logs.sh [--variant TAG]
#
# Requires: dbuild, podman

set -e

VARIANT="latest"
case "$1" in
  --variant) VARIANT="$2"; shift 2 ;;
esac

IMAGE_NAME=$(basename "$(pwd)")
LOG_FILE="cit-output.log"
MARKER=".cit-passed"

# dbuild runs podman with privilege escalation when not root (its _priv_prefix);
# we must match it or `podman ps`/`podman logs` silently see no containers.
PODMAN="podman"
if [ "$(id -u)" -ne 0 ]; then
  if command -v doas >/dev/null 2>&1; then
    PODMAN="doas podman"
  elif command -v sudo >/dev/null 2>&1; then
    PODMAN="sudo podman"
  fi
fi

# Clean previous state
rm -f "$LOG_FILE" "$MARKER"

echo "[cit] Starting dbuild test (variant: $VARIANT) with log capture..."

# Run dbuild test in background
dbuild --variant "$VARIANT" test >"${LOG_FILE}.dbuild" 2>&1 &
DBUILD_PID=$!

# Wait for the CIT container to appear (up to 30s)
CIT_CONTAINER=""
for i in $(seq 1 30); do
  CIT_CONTAINER=$($PODMAN ps --format '{{.Names}}' 2>/dev/null | grep -iE "cit.*${IMAGE_NAME}|${IMAGE_NAME}.*cit" | head -1)
  if [ -n "$CIT_CONTAINER" ]; then
    break
  fi
  sleep 1
done

if [ -n "$CIT_CONTAINER" ]; then
  echo "[cit] Found container: $CIT_CONTAINER — capturing logs..."

  # Wait for meaningful output (up to 120s)
  DEADLINE=$(($(date +%s) + 120))
  while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    if $PODMAN logs "$CIT_CONTAINER" 2>&1 | grep -qiE "Migrations|Starting|Error|listening|startup complete|ready" 2>/dev/null; then
      break
    fi
    sleep 2
  done

  # Capture full logs (filter kevent noise)
  $PODMAN logs "$CIT_CONTAINER" 2>&1 | grep -ivE "kevent\(\)" > "$LOG_FILE" 2>/dev/null || true
  echo "[cit] Logs written to $LOG_FILE"
else
  echo "[cit] WARNING: could not find CIT container — logs not captured"
fi

# Wait for dbuild test to finish.
# Same `set -e` trap as the smoke call further down: a bare `wait` that returns
# non-zero terminates the script, so `RESULT=$?` never runs and the "CIT FAILED
# — full logs in cit-output.log" branch below was unreachable dead code. Nobody
# noticed because CIT has passed on every image it was handed. Keep this in a
# condition. (Pre-existing; found 2026-10-31 alongside the smoke-capture bug.)
if wait "$DBUILD_PID"; then
  RESULT=0
else
  RESULT=$?
fi

echo ""
cat "${LOG_FILE}.dbuild"
# Keep dbuild's own stdout as evidence, don't just print and discard it: the
# PROCESS-LOG's Phase 4 section is supposed to quote a real CIT transcript, and
# deleting this left porters paraphrasing from memory (found 2026-09-28).
{
  echo ""
  echo "===== dbuild test stdout ($(date -u '+%Y-%m-%dT%H:%M:%SZ')) ====="
  cat "${LOG_FILE}.dbuild"
} >> "$LOG_FILE" 2>/dev/null || true
rm -f "${LOG_FILE}.dbuild"

if [ "$RESULT" -eq 0 ]; then
  echo ""
  echo "[cit] CIT PASSED"
  # Functional probe: CIT proves the app boots; the smoke test proves it works.
  # .cit-passed (which gates git push / PR) is only written once BOTH are green.
  if [ -x scripts/smoke-test.sh ]; then
    echo "[cit] Running functional probe (scripts/smoke-test.sh)..."
    # Retain the probe's output for the same reason the dbuild stdout above is
    # retained, and it was missed here: BUILD-NOTES and PROCESS-LOG are supposed
    # to quote a real transcript, and with the probe's stdout discarded a
    # reviewer has to take the functional gate on trust. The 2026-09-28 fix
    # eight lines up solved this for `dbuild test` only. (Found 2026-10-31 by
    # the port-auditor on blocky; reported as a toolkit defect.)
    # NOT `smoke-test.sh | tee -a`: this is /bin/sh, there is no PIPESTATUS, and
    # a pipeline's status is the LAST command's — so tee would always succeed and
    # the gate would pass unconditionally. Capture to a temp file, then keep the
    # probe's real exit status.
    # The probe call MUST stay inside a condition. This script runs under
    # `set -e` (line 10), where a bare failing simple command terminates the
    # shell immediately — so `cmd; RESULT=$?` never reaches the assignment, the
    # append below never runs, and a FAILING smoke test produces a bare non-zero
    # exit with no transcript and no diagnostic. That is the exact case this
    # capture was added for, so getting it wrong defeats the whole fix.
    # `set -e` is disarmed inside an if/while condition, which is why the
    # original `if scripts/smoke-test.sh; then` was safe.
    SMOKE_OUT="${LOG_FILE}.smoke"
    if scripts/smoke-test.sh >"$SMOKE_OUT" 2>&1; then
      SMOKE_RESULT=0
    else
      SMOKE_RESULT=$?
    fi
    # Unconditionally, before the verdict: print and retain on BOTH paths.
    cat "$SMOKE_OUT"
    {
      echo ""
      echo "===== smoke-test.sh output ($(date -u '+%Y-%m-%dT%H:%M:%SZ')) ====="
      cat "$SMOKE_OUT"
    } >> "$LOG_FILE" 2>/dev/null || true
    rm -f "$SMOKE_OUT"
    if [ "$SMOKE_RESULT" -eq 0 ]; then
      echo "[cit] SMOKE PASSED"
    else
      echo "[cit] SMOKE FAILED — the image boots but does not do its job. No marker written." >&2
      exit 1
    fi
  else
    echo "[cit] NOTE: no scripts/smoke-test.sh — only boot is proven, not function." >&2
    echo "[cit] Create one from templates/smoke-test.sh (see PORT-BRIEF 'Functional probe')." >&2
  fi
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$MARKER"
  exit 0
else
  echo ""
  echo "[cit] CIT FAILED — full logs in $LOG_FILE:"
  echo "---"
  cat "$LOG_FILE" 2>/dev/null || echo "(no logs captured)"
  echo "---"
  exit 1
fi
