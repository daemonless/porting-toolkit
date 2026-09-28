#!/bin/sh
# Functional probe — proves the app WORKS, not just that it boots.
# CIT's health check only proves a process listens; this exercises the app's
# actual purpose once, against the freshly built image. Copy to
# scripts/smoke-test.sh, fill the PROBE section from PORT-BRIEF.md's
# "Functional probe", and make it executable — cit-with-logs.sh runs it
# automatically after dbuild test passes, and only writes .cit-passed if it
# exits 0.
#
# Keep it to ONE meaningful assertion. If the app needs env to boot in
# isolation (e.g. a dummy upstream URL), set it here — same values CIT uses.

set -u

IMAGE_NAME=$(basename "$(pwd)")
IMAGE="ghcr.io/daemonless/${IMAGE_NAME}:build-latest"
NAME="smoke-${IMAGE_NAME}"
PORT="<app port, e.g. 3000>"

PODMAN="podman"
if [ "$(id -u)" -ne 0 ]; then
  if command -v doas >/dev/null 2>&1; then PODMAN="doas podman";
  elif command -v sudo >/dev/null 2>&1; then PODMAN="sudo podman"; fi
fi

cleanup() { $PODMAN rm -f "$NAME" >/dev/null 2>&1; }
trap cleanup EXIT INT TERM
cleanup

echo "[smoke] starting $IMAGE as $NAME"
$PODMAN run --rm -d --name "$NAME" \
  -e "<REQUIRED_ENV=dummy value, or delete this line>" \
  "$IMAGE" >/dev/null || { echo "[smoke] FAIL: container would not start" >&2; exit 1; }

IP=$($PODMAN inspect -f '{{.NetworkSettings.IPAddress}}' "$NAME")

# Wait for ready (up to 60s)
i=0
until curl -fsS -o /dev/null "http://${IP}:${PORT}/" 2>/dev/null; do
  i=$((i + 1))
  [ "$i" -ge 30 ] && { echo "[smoke] FAIL: not listening after 60s" >&2; exit 1; }
  sleep 2
done

# --- PROBE (from PORT-BRIEF.md "Functional probe") ---------------------------
# Exercise the app's purpose, not just its listener. Examples:
#   IPP:    a bogus share path must return the app's OWN 404 page (routing +
#           render work), not an empty reply / connection error.
#   an API: one real endpoint returns well-formed JSON.
BODY=$(curl -fsS "http://${IP}:${PORT}/<probe path>" 2>&1) || true
if printf '%s' "$BODY" | grep -q "<expected content>"; then
  echo "[smoke] PASS: <one line saying what this proved>"
  exit 0
else
  echo "[smoke] FAIL: probe response did not contain expected content:" >&2
  printf '%s\n' "$BODY" | head -20 >&2
  exit 1
fi
