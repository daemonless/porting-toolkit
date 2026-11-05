#!/bin/sh
# PreToolUse(Bash): builds must run in the background.
# A cold FreeBSD image build routinely outlives the Bash tool's foreground max
# timeout; the harness SIGKILLs it (exit 137) and can end the session mid-build
# with no WIP.md (this killed a whole port session on 2026-07-04). Backgrounded
# commands have no such ceiling. Exit 2 = block, message shown to Claude.

input=$(cat)
parsed=$(printf '%s' "$input" | python3 -c "
import sys, json
d = json.load(sys.stdin).get('tool_input', {})
print((d.get('command') or '').replace('\n', ' '))
print('yes' if d.get('run_in_background') else 'no')
" 2>/dev/null)

cmd=$(printf '%s' "$parsed" | sed -n 1p)
bg=$(printf '%s' "$parsed" | sed -n 2p)

case "$cmd" in
  *dbuild\ build*|*scripts/build.sh*)
    if [ "$bg" != "yes" ]; then
      echo "BLOCKED: builds must be backgrounded — a foreground build gets SIGKILLed (exit 137) at the tool timeout and can end the session. Re-run \`scripts/build.sh\` with run_in_background: true; you are re-invoked when it exits, then read its verdict (it greps build.log for you)." >&2
      exit 2
    fi
    ;;
esac
exit 0
