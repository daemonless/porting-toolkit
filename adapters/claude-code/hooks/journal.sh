#!/bin/sh
# PostToolUse(Bash): append every command to JOURNAL.log automatically.
# The journal is the always-current record of what was actually run — it does not
# depend on the model's logging discipline. If a session dies without warning
# (tool-timeout SIGKILL, crash), the journal is what the next session recovers
# from; WIP.md and PROCESS-LOG.md are curated narrative on top of it.
# Non-blocking; never fails the tool call.

input=$(cat)
printf '%s' "$input" | python3 -c "
import sys, json, datetime
try:
    d = json.load(sys.stdin)
    cmd = (d.get('tool_input', {}).get('command') or '').replace('\n', ' ; ')[:300]
    if cmd:
        ts = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
        with open('JOURNAL.log', 'a') as f:
            f.write(f'{ts}  {cmd}\n')
except Exception:
    pass
" 2>/dev/null
exit 0
