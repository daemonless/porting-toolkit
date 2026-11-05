#!/bin/sh
# PreToolUse(Edit|Write|MultiEdit): block edits to a GENERATED Containerfile.
# Any Containerfile or Containerfile.<variant> with a matching .j2 beside it is
# produced by `dbuild generate`; edit the .j2 instead.
# Reads the tool-call JSON on stdin; exit 2 = block (message on stderr is shown to Claude).

input=$(cat)
path=$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null)

case "$path" in
  *.j2) exit 0 ;;
  Containerfile|*/Containerfile|Containerfile.*|*/Containerfile.*)
    if [ -f "$path.j2" ]; then
      echo "BLOCKED: $path is generated. Edit $path.j2 instead, then run \`dbuild generate\`." >&2
      exit 2
    fi
    ;;
esac
exit 0
