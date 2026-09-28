#!/bin/sh
# Stop hook: gentle reminder that a port isn't done until the runtime test passes.
# Non-blocking.
echo "Reminder: a green \`dbuild build\` only proves it compiles. The port is not done until \`dbuild test\` (CIT) passes — migrations run, health returns 200, screenshot matches — and BUILD-NOTES.md is written." >&2
exit 0
