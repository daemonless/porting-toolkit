# dbuild CIT testing + reliable log capture

`dbuild test` runs the container integration test (screenshot and/or health-gate mode per `.daemonless/config.yaml`). It is the only proof the image actually *runs* — a tagged build is not.

## The problem
On failure, `dbuild test` prints only a truncated tail of the container logs — usually missing the real stack trace (it scrolls off during the s6 restart loop). But the CIT container stays alive for the **health-timeout window (~120s)** before cleanup.

## Automated log capture (preferred)

Use the toolkit's `scripts/cit-with-logs.sh`:
```sh
scripts/cit-with-logs.sh
```

This wraps `dbuild test`, automatically captures full container logs during the health-timeout window, and writes them to `cit-output.log`. On failure, it prints the captured logs so you can see the real stack trace without a manual race.

## Manual log capture (fallback)

If the script isn't available, capture logs yourself during the ~120s window:
```sh
# 1) start the test in the background
dbuild --variant latest test >test.log 2>&1 &

# 2) within ~120s, find the cit container and dump its FULL logs
c=$(podman ps --format '{{.Names}}' | grep -i 'cit.*<image>' | head -1)
until podman logs "$c" 2>&1 | grep -qiE "Migrations|Starting|Error|listening"; do sleep 2; done
podman logs "$c" 2>&1 | grep -ivE "kevent\(\)"   # the real stack trace lives here
```

## What CIT actually checks
- **screenshot mode:** waits for `health` endpoint, waits `screenshot_wait`s for hydration, captures the port, diffs against `.daemonless/baseline-*.png`. The screenshot diff is the pass/fail gate — a broken `/api/health` can still pass the *screenshot* but is a real bug (it breaks compose healthchecks / monitoring), so verify health returns 200 too.
- **health mode:** polls the health endpoint until 200.

## Common runtime failures to look for in the captured logs
- config-parse crash before the DB opens (e.g. missing `Temporal` global) — cookbook.
- `Migrations failed` — DB driver shape mismatch (libsql vs better-sqlite3/node:sqlite) — cookbook.
- native module load error at boot (`Cannot find module '@...'`) — cookbook (lazy-load / swap).
- nginx `connect() failed (61: Connection refused)` to the backend = the node/app process crashed; scroll up for *its* error.
