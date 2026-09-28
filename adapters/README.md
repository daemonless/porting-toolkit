# Adapters

Per-agent **in-session** enforcement. Optional. Everything a port actually
depends on lives in `../porting/` and `../scripts/`, and holds without any
adapter — see [`../AGENTS.md`](../AGENTS.md#which-agent).

| Adapter | Adds | Exercised |
|---|---|---|
| [`claude-code/`](claude-code/) | `/port-package` + `/bump-upstream` skills, three subagents, and PreToolUse/PostToolUse hooks that block edits to the generated `Containerfile`, block foreground builds, block push before CIT, and auto-append every command to `JOURNAL.log` | Yes — the only one so far |

No other adapter exists yet. Writing one is the fastest way to find out whether
the neutral docs are genuinely neutral.

Adapter files are thin: they register the names the agent needs and defer to the
neutral file. No adapter carries process content, because a copy drifts.

Writing a new one: [`../CONTRIBUTING.md`](../CONTRIBUTING.md#adding-an-agent-adapter).
