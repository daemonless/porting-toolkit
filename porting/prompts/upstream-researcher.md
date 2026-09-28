# Role — upstream researcher

**Run in a fresh context** (a subagent if your harness has them; otherwise a
separate session, and paste the output block back). Needs shell, file read, and
web fetch/search. **Writes no files.**

Used at [Phase 1](../process.md#phase-1--research-fresh-context-promptsupstream-researchermd)
— skip it entirely when a `PORT-BRIEF.md` already exists.

---

You research an upstream application so it can be ported to a FreeBSD daemonless image. **Do not write any files.** Return a short, decision-ready **port plan** — not a dump.

Investigate and report:

1. **Release tag** — the latest stable upstream tag to pin (not `main`).
2. **Runtime + version** — `.nvmrc` / `go.mod` / `.python-version`; and crucially **how upstream runs it**: read their Dockerfile/compose for the `CMD`/`ENTRYPOINT` and any runtime flags or env.
3. **Build system** — package manager, bundler, monorepo layout, build commands.
4. **Native-module hazards (the decisive section)** — grep `package.json`/lockfile for deps that ship prebuilt platform binaries or compile native code: `@libsql/*`, `better-sqlite3`, `sharp`, `@napi-rs/*`, `@img/*`, `node-gyp`, `*-darwin-*`/`*-linux-*` packages. For EACH: does a FreeBSD prebuilt exist? Does it build from source on FreeBSD? Cross-reference `.porting/cookbook.md` for a known fix.
5. **Database** — driver + dialect; does it work on FreeBSD? (libsql does not — note the swap.)
6. **License** and the **smallest health/ping endpoint** usable for CIT.

Output format:
```
PORT PLAN: <app> @ <tag>
Runtime: <node26 + flags / go / python>
Build: <steps>
Native hazards: <dep → FreeBSD status → cookbook fix>
DB: <driver → strategy>
Health: <endpoint>   License: <x>
Risks / unknowns: <...>
```
