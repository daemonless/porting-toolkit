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

# Wait for dbuild test to finish
wait "$DBUILD_PID"
RESULT=$?

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
    if scripts/smoke-test.sh; then
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
