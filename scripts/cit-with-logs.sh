#!/bin/sh
# Wraps `dbuild test` with full container log capture, then runs the
# functional probe (scripts/smoke-test.sh). Writes .cit-passed only when BOTH
# pass. The marker records the git tree that was tested, so the pre-push rail
# can refuse a push whose content differs from what passed.
#
# Usage: scripts/cit-with-logs.sh [--variant TAG]
#   Without --variant, tests the variant `dbuild test` picks by default (the
#   first one `dbuild detect` lists). Variant tags come from
#   .daemonless/config.yaml or Containerfile.<tag>; not every image has `latest`.
#
# Requires: dbuild, podman, python3, git

set -e

VARIANT=""
case "$1" in
  --variant) VARIANT="$2"; shift 2 ;;
esac

IMAGE_NAME=$(basename "$(pwd)")
LOG_FILE="cit-output.log"
MARKER=".cit-passed"

# dbuild's AppJail backend pipes output through $PAGER; an interactive pager
# hangs a non-interactive run.
export PAGER=cat

# dbuild runs podman with privilege escalation when not root; match it, or
# `podman ps`/`podman logs` see no containers.
PODMAN="podman"
if [ "$(id -u)" -ne 0 ]; then
  if command -v doas >/dev/null 2>&1; then
    PODMAN="doas podman"
  elif command -v sudo >/dev/null 2>&1; then
    PODMAN="sudo podman"
  fi
fi

if [ -z "$VARIANT" ]; then
  VARIANT=$(dbuild detect --format json 2>/dev/null \
    | python3 -c 'import json,sys; m=json.load(sys.stdin); print(m[0]["tag"] if m else "")' 2>/dev/null || true)
  if [ -z "$VARIANT" ]; then
    echo "[cit] ERROR: could not read the variant list from \`dbuild detect\`. Pass --variant TAG." >&2
    exit 1
  fi
fi

# Fail before the long test run, not after it.
if [ ! -f scripts/smoke-test.sh ]; then
  echo "[cit] ERROR: no scripts/smoke-test.sh. CIT proves the image boots; the smoke test proves it works." >&2
  echo "[cit] Create it from .porting/templates/smoke-test.sh (see PORT-BRIEF 'Functional probe'). No marker written." >&2
  exit 1
fi
if [ ! -x scripts/smoke-test.sh ]; then
  echo "[cit] ERROR: scripts/smoke-test.sh is not executable. Run: chmod +x scripts/smoke-test.sh" >&2
  exit 1
fi

rm -f "$LOG_FILE" "$MARKER"

echo "[cit] Starting dbuild test (variant: $VARIANT) with log capture..."
dbuild --variant "$VARIANT" test >"${LOG_FILE}.dbuild" 2>&1 &
DBUILD_PID=$!

# Find the CIT container (up to 30s), then follow its logs until it exits, so a
# crash late in the run is captured, not just the first lines.
CIT_CONTAINER=""
for _ in $(seq 1 30); do
  CIT_CONTAINER=$($PODMAN ps --format '{{.Names}}' 2>/dev/null | grep -iE "cit.*${IMAGE_NAME}|${IMAGE_NAME}.*cit" | head -1 || true)
  [ -n "$CIT_CONTAINER" ] && break
  kill -0 "$DBUILD_PID" 2>/dev/null || break
  sleep 1
done

FOLLOW_PID=""
if [ -n "$CIT_CONTAINER" ]; then
  echo "[cit] Found container: $CIT_CONTAINER — following its logs..."
  $PODMAN logs -f "$CIT_CONTAINER" >"${LOG_FILE}.raw" 2>&1 &
  FOLLOW_PID=$!
else
  echo "[cit] WARNING: could not find the CIT container — container logs not captured" >&2
fi

# `wait` must stay inside a condition: under `set -e` a bare failing wait
# exits the script before the failure branch below can run.
if wait "$DBUILD_PID"; then
  RESULT=0
else
  RESULT=$?
fi

if [ -n "$FOLLOW_PID" ]; then
  # The follower ends when the container is removed; give it a moment, then stop it.
  sleep 2
  kill "$FOLLOW_PID" 2>/dev/null || true
  wait "$FOLLOW_PID" 2>/dev/null || true
  grep -ivE 'kevent\(\)' "${LOG_FILE}.raw" > "$LOG_FILE" 2>/dev/null || true
  rm -f "${LOG_FILE}.raw"
  echo "[cit] Container logs written to $LOG_FILE"
fi

echo ""
cat "${LOG_FILE}.dbuild"
{
  echo ""
  echo "===== dbuild test stdout ($(date -u '+%Y-%m-%dT%H:%M:%SZ')) ====="
  cat "${LOG_FILE}.dbuild"
} >> "$LOG_FILE"
rm -f "${LOG_FILE}.dbuild"

if [ "$RESULT" -ne 0 ]; then
  echo ""
  echo "[cit] CIT FAILED — full logs in $LOG_FILE:"
  echo "---"
  cat "$LOG_FILE"
  echo "---"
  exit 1
fi

echo ""
echo "[cit] CIT PASSED"

# The image the test used: build-<tag>, else <tag> (dbuild's own fallback).
# Read from podman so the registry (fork or daemonless) matches what was built.
SMOKE_IMAGE=$($PODMAN images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
  | grep -E "/${IMAGE_NAME}:build-${VARIANT}\$" | head -1 || true)
if [ -z "$SMOKE_IMAGE" ]; then
  SMOKE_IMAGE=$($PODMAN images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
    | grep -E "/${IMAGE_NAME}:${VARIANT}\$" | head -1 || true)
fi
if [ -z "$SMOKE_IMAGE" ]; then
  echo "[cit] ERROR: no local image */${IMAGE_NAME}:build-${VARIANT} for the smoke test. No marker written." >&2
  exit 1
fi
export SMOKE_IMAGE SMOKE_VARIANT="$VARIANT"

echo "[cit] Running functional probe against $SMOKE_IMAGE..."
# Capture to a file, not `| tee`: /bin/sh has no pipefail, so a pipeline would
# report tee's status and the gate would always pass.
SMOKE_OUT="${LOG_FILE}.smoke"
if scripts/smoke-test.sh >"$SMOKE_OUT" 2>&1; then
  SMOKE_RESULT=0
else
  SMOKE_RESULT=$?
fi
cat "$SMOKE_OUT"
{
  echo ""
  echo "===== smoke-test.sh output ($(date -u '+%Y-%m-%dT%H:%M:%SZ')) ====="
  cat "$SMOKE_OUT"
} >> "$LOG_FILE"
rm -f "$SMOKE_OUT"

if [ "$SMOKE_RESULT" -ne 0 ]; then
  echo "[cit] SMOKE FAILED — the image boots but does not do its job. No marker written." >&2
  exit 1
fi
echo "[cit] SMOKE PASSED"

# Record the tree that passed: the working tree as `git add -A` would stage
# it, hashed in a scratch copy of the index so the real one is untouched.
TREE=""
if git rev-parse --git-dir >/dev/null 2>&1; then
  TMP_INDEX=$(mktemp)
  REAL_INDEX=$(git rev-parse --git-path index)
  if [ -f "$REAL_INDEX" ]; then cp "$REAL_INDEX" "$TMP_INDEX"; else rm -f "$TMP_INDEX"; fi
  TREE=$(GIT_INDEX_FILE="$TMP_INDEX" sh -c 'git add -A :/ && git write-tree')
  rm -f "$TMP_INDEX"
fi
{
  echo "tree $TREE"
  echo "variant $VARIANT"
  echo "date $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
} > "$MARKER"
echo "[cit] Wrote $MARKER (tree ${TREE:-none})"
exit 0
