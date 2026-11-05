#!/bin/sh
# PostToolUse(Bash): after a `dbuild generate`, warn if the generated files name
# a registry other than ghcr.io/daemonless. dbuild derives the registry from the
# git remote, so generating from a fork writes the fork's org.
# README.md is generated and shipped; the fix is to regenerate, not to restore.
# Non-blocking: prints guidance the agent will see.

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

case "$cmd" in
  *dbuild*generate*)
    case "$cmd" in *--check*) exit 0 ;; esac
    others=$(grep -hoE 'ghcr\.io/[A-Za-z0-9.-]+/' README.md Containerfile Containerfile.* compose.yaml 2>/dev/null \
             | sort -u | grep -vx 'ghcr.io/daemonless/')
    if [ -n "$others" ]; then
      echo "NOTE: generated files reference $(echo "$others" | tr '\n' ' ')instead of ghcr.io/daemonless/. Re-run \`DBUILD_REGISTRY=ghcr.io/daemonless dbuild generate\` and commit the regenerated README.md." >&2
    fi
    ;;
esac
exit 0
