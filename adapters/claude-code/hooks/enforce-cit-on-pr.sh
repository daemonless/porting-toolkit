#!/bin/sh
# PreToolUse(Bash): block git push / gh pr create if CIT hasn't passed.
# Checks for a .cit-passed marker written by scripts/cit-with-logs.sh on success.
# Exit 2 = hard block. Non-destructive: the agent just needs to run CIT first.

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

case "$cmd" in
  *git\ push*|*gh\ pr\ create*)
    if [ ! -f .cit-passed ]; then
      echo "BLOCKED: CIT has not passed in this session. Run \`scripts/cit-with-logs.sh\` (or \`dbuild test\`) first. A .cit-passed marker is written on success." >&2
      exit 2
    fi
    ;;
esac
exit 0
