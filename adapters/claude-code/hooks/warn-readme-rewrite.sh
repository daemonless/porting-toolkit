#!/bin/sh
# PostToolUse(Bash): after a `dbuild generate`, warn if README.md now contains fork URLs
# (dbuild regenerates README from local context and rewrites the daemonless registry URL).
# Non-blocking: prints guidance Claude will see.

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

case "$cmd" in
  *dbuild*generate*)
    if [ -f README.md ] && grep -qiE 'ghcr\.io/[^d]|ghcr\.io/d[^a]' README.md 2>/dev/null; then
      echo "NOTE: README.md may have been rewritten with fork URLs by \`dbuild generate\`. Restore it to upstream before committing — only Containerfile/.j2 and patches/ belong in the PR." >&2
    fi
    ;;
esac
exit 0
