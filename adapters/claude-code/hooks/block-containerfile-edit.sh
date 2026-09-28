#!/bin/sh
# PreToolUse(Edit|Write|MultiEdit): block edits to a GENERATED Containerfile.
# The source of truth is Containerfile.j2; the Containerfile is produced by `dbuild generate`.
# Reads the tool-call JSON on stdin; exit 2 = block (message on stderr is shown to Claude).

input=$(cat)
path=$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

case "$path" in
  */Containerfile)
    echo "BLOCKED: $path is generated. Edit Containerfile.j2 instead, then run \`dbuild generate\`." >&2
    exit 2
    ;;
esac
exit 0
