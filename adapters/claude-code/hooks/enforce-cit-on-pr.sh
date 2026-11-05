#!/bin/sh
# PreToolUse(Bash):
#   - gh pr create: always blocked. The project's AI policy forbids AI-written PR
#     descriptions, so the human opens the PR.
#   - git push: blocked unless .cit-passed records the tree of HEAD, i.e. CIT and
#     the smoke test passed on exactly what is being pushed. The git pre-push
#     rail enforces the same rule for every ref; this just fails earlier.
# Exit 2 = hard block; the message on stderr is shown to the agent.

input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c "import sys,json;print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)

case "$cmd" in
  *gh\ pr\ create*)
    echo "BLOCKED: the agent does not open the PR. Per the Daemonless AI policy the human opens it and writes the description in their own words. Stop and hand over the branch and evidence (see .porting/templates/PR-BODY.md)." >&2
    exit 2
    ;;
  *git\ push*)
    if [ ! -f .cit-passed ]; then
      echo "BLOCKED: CIT has not passed. Run \`scripts/cit-with-logs.sh\` first; it writes .cit-passed when CIT and the smoke test both pass." >&2
      exit 2
    fi
    tested=$(sed -n 's/^tree //p' .cit-passed)
    head_tree=$(git rev-parse 'HEAD^{tree}' 2>/dev/null)
    if [ -z "$tested" ] || [ "$tested" != "$head_tree" ]; then
      echo "BLOCKED: HEAD differs from the tree that passed CIT (tested ${tested:-unknown}, HEAD $head_tree). Commit exactly the tested state, or re-run \`scripts/cit-with-logs.sh\`." >&2
      exit 2
    fi
    ;;
esac
exit 0
