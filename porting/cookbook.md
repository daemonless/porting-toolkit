# FreeBSD daemonless porting cookbook

Error-signature-keyed fixes for porting apps to FreeBSD daemonless images. **Look here BEFORE guessing. Append a new entry every time you solve something new** — that's what makes the Nth port fast. Each entry: *signature → root cause → fix → why*.

**How to look up:** grep this file for the most distinctive literal line of your
error first (`grep -n -F "..."`), then by keyword (`sqlite`, `sharp`, `gyp`,
`Temporal`, `hang`), then skim the section for your runtime. Apply matches
verbatim — these fixes are build-verified; your variation of them is not.

---

## Node / JavaScript

### `pkg install nodeXX` → "No packages available" / not found
**Cause:** the requested node (e.g. `node26`) is only in FreeBSD's **`latest`** pkg branch; the base image is on **`quarterly`**, which lags (tops out at e.g. node25).
**Fix:** build on a base tag that bakes in the `latest` branch — the fleet convention — instead of editing `/etc/pkg/FreeBSD.conf` in the Containerfile. Set it per variant in `.daemonless/config.yaml`:
```yaml
build:
  variants:
    - tag: latest
      args:
        BASE_VERSION: "15-latest"   # check the tag exists: skopeo list-tags
```
with `ARG BASE_VERSION` feeding the `FROM` line of **every** stage that installs it.
**Why:** quarterly is a frozen snapshot; new major runtimes land in latest first. #1 cause of "package not found". The base's `-latest` tags exist for exactly this, and a `sed` buried in the Containerfile is invisible in the variant list.

### Runtime crash: `ReferenceError: Temporal is not defined`
**Cause:** FreeBSD's `node26` is compiled **without** the TC39 Temporal global. Official Node 26 ships it; on the FreeBSD build even `--harmony-temporal` is a no-op.
**Fix:** add a polyfill dep and preload it (in the launcher, or the s6 run script on legacy `base`):
```
# inject dep:  p.dependencies['temporal-polyfill']='0.3.2'
# launcher:    NODE_FLAGS="--import temporal-polyfill/global"
```
**Why:** Temporal is gated behind a V8 build flag the FreeBSD port doesn't enable. (Worth a ports PR.)

### `better-sqlite3` build fails: `no member named 'GetPrototype'`/`'GetIsolate'`/`'This'`
**Cause:** node26's V8 removed those APIs; `better-sqlite3` ≤11.x uses them.
**Fix:** inject **better-sqlite3 ≥12.x** (version-gates via `V8_MAJOR_VERSION>=13` / `NODE_MODULE_VERSION>=140`). 11.x only works up to node24.
**Why:** native addons must track the V8 ABI; pin to a version supporting your node major.

### `@libsql/client` crashes on import: `Cannot find module '@libsql/freebsd-x64'`
**Cause:** the native `libsql` package ships **no FreeBSD prebuilt and no source build**; merely *importing* `@libsql/client` loads the native binding and crashes.
**Fix (cleanest first):**
1. **`node:sqlite`** (built into node ≥22, usable in 26) via `drizzle-orm/sqlite-proxy` — **drops the whole C toolchain**. Use `StatementSync.setReturnArrays(true)` for positional rows; `.columns().length` to detect readers.
2. **`better-sqlite3`** (≥12 on node26) — proven, but pulls node-gyp + toolchain.
Both need a small `database.ts` shim reproducing libsql semantics:
- a custom `db.batch([...])` (tolerates eagerly-executed `db.run()` results),
- libsql-shaped `db.run/all/get(sql)` returning **row objects** (migrations read by column name; the bare proxy returns positional arrays).
Also drop any static import of a libsql *task/queue* driver — it eval-loads the native module and crashes even when unused.
**Why:** Turso/libsql ships Rust napi prebuilds for linux/darwin/win32 only.

### `sharp` fails to load at boot (no FreeBSD prebuilt)
**Fix:** add `@img/sharp-wasm32` as a direct dep, **pinned to sharp's exact version**, + a post-install drift guard that fails the build if sharp moves off the pin. sharp auto-loads the wasm runtime.
**Why:** sharp requires its platform package to match its own version exactly.

### `@napi-rs/canvas` (or similar optional native) has no FreeBSD build
**Fix:** patch the importer to **lazy-load**: `async () => (await import('@napi-rs/canvas')).default`. Then it only fails if a code path needs it.
**Why:** a static import crashes the whole process at boot even if unused.

### pnpm fetches Linux-only binaries / refuses native build scripts
**Fix:**
- `.npmrc`: `supportedArchitectures.os[]=current`, `cpu[]=current`, `cpu[]=wasm32`.
- `pnpm-workspace.yaml`: add needed packages to `allowBuilds` (pnpm v11 treats an ignored build script as a hard error).
**Why:** upstream lockfiles assume Linux/macOS only.

### `tsx: not found` / tsx fails under `/bin/sh`
**Cause:** tsx's bin wrapper is a bash script. **Fix:** `node --import tsx script.ts`.

### `npm install -g` CLI fails as unprivileged user: `ocijail: error executing container command: No such file or directory`
**Signature:** image runs (no hang), but the entrypoint immediately errors with `No such file or directory`, even though `/usr/local/bin/<tool>` exists. As `--user root` it works fine.
**Cause:** npm run as root under the base image's restrictive umask installs the global tree **mode 700 / root-only** (`drwx------ /usr/local/lib/node_modules/@scope`). A container running as the unprivileged `bsd` user can't traverse into it to reach the bin — exec returns ENOENT.
**Fix:** make the global modules world-readable/searchable **in the same `RUN` as the install, in the builder stage** — then `COPY` the finished tree into the runtime stage, as the fleet does:
```dockerfile
RUN npm install -g <tool>@<version> && \
    chmod -R a+rX /usr/local/lib/node_modules
```
**Why:** `a+rX` adds read for all and search/execute on dirs (and already-exec files) only — exactly what an unprivileged `USER` needs to run a root-installed CLI. Don't do it in a separate late layer: a recursive `chmod` rewrites every file's metadata, so the layer stores a second full copy of the tree.

### node-gyp: `cc: not found` / `ar: not found` / missing headers
**Cause:** the base jail ships no C toolchain and no `/usr/include`.
**Fix (builder stage only):** `pkg install -y FreeBSD-clang FreeBSD-lld FreeBSD-toolchain FreeBSD-clibs-dev pkgconf python3 gmake`. Better: avoid native compiles (prefer `node:sqlite`, wasm sharp) and drop the toolchain.

### A monorepo build tool crashes with `Cannot find module '<pkg>-freebsd-x64'` (glob-hasher, and NAPI-RS tools generally)
**Signature:** a build orchestrator (lage, turbo, nx, …) or its transitive deps `require()`s a NAPI-RS native addon unconditionally at module load; the error names a platform-suffixed package (`glob-hasher-freebsd-x64`, `<tool>-freebsd-x64`) that 404s on npm — no source build published either, and the wrapper has no JS fallback (throws `loadError` immediately, see the addon's own `index.js`).
**Cause:** NAPI-RS's standard `optionalDependencies` pattern only ships prebuilts for the platforms the maintainer's CI targets — almost always win32/darwin/linux, never freebsd. This hits *build-tool* dependencies (lage's `glob-hasher`) as often as app dependencies, and you can't patch a third-party minified bundle's `require()` call.
**Fix:** replace the whole package with a pure-JS shim via Yarn's `resolutions` field (works because `nodeLinker: node-modules` still uses Node's normal `require()` resolution) — the shim only needs to implement the *shape* the caller expects, not bit-for-bit identical output:
1. Read the real package's shipped `.d.ts` for the exact function signatures (`npm pack <pkg>@<version>` and inspect — don't guess).
2. Write a same-named local package (`patches/<pkg>-shim/package.json` + `index.js`) implementing those functions with Node built-ins (e.g. `fs.globSync`, `crypto.createHash` in place of a Rust glob+hash addon).
3. Wire it in before install: `"resolutions": { "<pkg>": "portal:./patches/<pkg>-shim" }` in the root `package.json`, and `COPY patches/<pkg>-shim ./patches/<pkg>-shim` before `yarn install`.
**Why it's safe, not just expedient:** for a build-cache hasher specifically, every Containerfile build starts from an empty local cache, so the hash *values* only need to be well-shaped (right type, right rough format) to avoid crashing call sites — they never need to match a previous run, because there is no previous run. Verify this reasoning holds for your specific tool before reusing the pattern; it doesn't generalise to addons whose output is checked for correctness (e.g. a real content hash compared against a lockfile).

### `tsgo` / `@typescript/native-preview` crashes: `Unable to resolve @typescript/native-preview-freebsd-x64`
**Cause:** Microsoft's experimental native (Go-compiled) TypeScript compiler, invoked as a package's `build` or `typecheck` script (`tsgo -b`, `tsgo --emitDeclarationOnly`). Same NAPI-style `optionalDependencies` gap as above — win32/darwin/linux only, and `bin/tsgo.js` throws unconditionally via `getExePath()` when no platform package resolves.
**Fix:** before reaching for the shim pattern above, check whether the workspace's `package.json` `exports`/`main` fields point at `./src/**/*.ts` directly (common in TS monorepos — `tsgo`'s only output, `.d.ts` declarations, is then never consumed by an in-repo vite/esbuild consumer, only by external publish targets or a separate CI typecheck step you aren't running). If so, `tsgo` is safe to no-op entirely: `"resolutions": { "@typescript/native-preview": "portal:./patches/tsgo-shim" }` pointing at a package whose `bin/tsgo.js` just `console.log`s and `process.exit(0)`s. If any consumed workspace's exports instead point at built `dist/` output, this shortcut doesn't apply — you actually need the declarations, and skipping `tsgo` will ship stale or missing types.
**Why:** the shim skips a type-correctness check, not a runtime behaviour — acceptable because the port ships a JS bundle already transpiled (not type-checked) by vite/esbuild, and upstream's own CI already validated types on a platform where `tsgo` runs.

### `yarn workspaces focus <ws>` build fails: `<tool>: command not found` (lage, turbo, nx)
**Signature:** you narrowed the install to the workspaces you ship, and the build then dies at the orchestrator — `./bin/…: line N: lage: command not found`, exit 127.
**Cause:** `yarn workspaces focus <ws>...` installs the named workspaces' dependencies but **not the root workspace's own `devDependencies`**. Repos that drive their build from root scripts (`yarn build:server` → `lage`/`turbo`/`nx`) keep that orchestrator as a root devDependency, so it is never installed.
**Fix:** do a full `yarn install` (matching what upstream's own Dockerfile does), and deal with unwanted native postinstalls separately — e.g. delete the offending keys from the root `package.json`'s `dependenciesMeta` before installing, with a drift guard that fails if a key is already gone:
```dockerfile
RUN node -e "const fs=require('fs'),p=JSON.parse(fs.readFileSync('package.json','utf8')); \
  for (const d of ['electron','sharp']) { \
    if (!(d in (p.dependenciesMeta||{}))) { console.error('PATCH DRIFT: dependenciesMeta.'+d+' missing'); process.exit(1); } \
    delete p.dependenciesMeta[d]; } \
  fs.writeFileSync('package.json', JSON.stringify(p,null,2)+'\n')"
```
Then `yarn workspaces focus <ws> --production` **after** the build, to trim the tree for the runtime stage — which is the step `focus` is actually for.
**Why:** `focus` is a runtime-trimming tool, not a build-time one. (Found 2026-09-28 porting actual/sync-server.)

---

## Python / FastAPI

### `pip install -r requirements.txt` fails building Rust/C deps
**Cause:** compiled deps (pydantic-core, cryptography, orjson, watchfiles = Rust; pillow, argon2-cffi, uvloop, httptools = C) have **no FreeBSD wheels**; pip builds them from source (needs rust/cargo + C toolchain).
**Fix:** install them prebuilt from `pkg` as `py3XX-*` and skip pip entirely (most FastAPI deps are packaged). No toolchain in the image.
**Verify names first:** `pkg rquery '%v' <name>` — FreeBSD naming surprises: `py312-Jinja2` (capitalised), `py312-sqlalchemy20`, `py312-pydantic2` (the v2 pkg), `py312-pillow` (lowercase). The prefix follows the branch's default Python (see below); never assume it.

### `fastapi run` not available
`fastapi-cli` is usually not packaged. Run `python3.XX -m uvicorn <pkg.module>:app --host 0.0.0.0 --port <p>` (`py3XX-uvicorn` exists).

### `SyntaxError` on newer Python syntax, or `py3XX-<dep>` not found
**Cause:** FreeBSD packages Python deps only for the **default flavour** of each pkg branch. The ports default moved from 3.11 to **3.12** on 2026-06-24 (`Mk/bsd.default-versions.mk`), so the `latest` branch has `py312-*` (e.g. `py312-pydantic2`) and has dropped the `py311-*` builds; a `quarterly` branch cut earlier may still be on 3.11.
**Fix:** check what the base's branch actually ships before writing a package name: `pkg rquery '%n-%v' 'py3*-pydantic2'`. Use that prefix and the matching `python3.XX`. If the app needs syntax newer than the branch's default, scope it with `python3.XX -m compileall <pkg>` (lists every syntax error): a few lines → a self-guarding patch that fails on drift; pervasive → a documented blocker.

### `uvicorn: Could not import module "X"`
Masks the **real** import exception. Reproduce: `python3.XX -c "import X"` (as the runtime user) to get the true traceback (missing dep, permission, or syntax).

### App imports fail for no obvious reason — check permissions
Cloned/COPY'd source often lands as `root:wheel 700`; the unprivileged runtime user (`bsd`) can't import it. `chown -R bsd:bsd /app`.

---

## General daemonless / dbuild patterns

### Catalogue metadata: set `x-daemonless: class:` — and where the config lives depends on it
**Cause:** the daemonless catalogue/README generator reads metadata from an `x-daemonless:` block, but *where* that block lives and which files an image ships depend on its **class**. dbuild's `VALID_IMAGE_CLASSES` = `service` | `cli` | `base` | `part` (default `service`). Easy to forget the field entirely, or to give a run-and-exit CLI a `compose.yaml` it should never have.
**Fix — pick the class, then follow its layout:**
- **`service`** (persistent daemon, e.g. papra, sparky, trip): `x-daemonless:` block lives in **`compose.yaml`**; also ship `.daemonless/config.yaml` (`build:` variants + `cit:` screenshot/port/health) and a `.daemonless/baseline-*.png`. Set `class: "service"` explicitly even though it's the default.
- **`cli`** (run-and-exit tool, e.g. immich-cli): **no `compose.yaml`**. Put everything in `.daemonless/config.yaml`:
  ```yaml
  x-daemonless:
    class: cli
  build:
    variants:
      - tag: latest
        containerfile: Containerfile
  cit:
    mode: command            # runs to completion, asserts exit 0 + output regex
    expect_output: '\d+\.\d+\.\d+'   # keep generic, don't pin the exact version
  ```
- **`base`** (image for `FROM`): no deployment docs.
- **`part`** (one piece of a stack, installed by the stack — e.g. `immich-server`): no deployment docs, and catalogues leave it out.
**Also:** `category:` must be one of dbuild's `VALID_CATEGORIES` (Base, Databases, Development, Downloaders, Infrastructure, Media Management, Media Servers, Monitoring, Network, Photos & Media, Productivity, Security, Utilities). `"Apps"` is **not** valid and won't slot into the catalogue.
**Why:** the catalogue and README layout branch on `class`; a CLI rendered as a service (or vice-versa) generates wrong deployment docs. Schema source of truth: `dbuild/dbuild/config.py` (`Metadata`, `VALID_IMAGE_CLASSES`, `VALID_CATEGORIES`).

### Generated files carry the wrong image name (`ghcr.io/daemonless/<app>-daemonless`, `…-fork`, `…-port`)
**Signature:** after `dbuild generate`, the README, the registry refs in `compose.yaml` and the built image tag all use a name you never typed — usually your checkout's directory name, e.g. `papra-daemonless` instead of `papra`. Nothing errors; the build is green and the artefacts are all subtly wrong.
**Cause:** `dbuild` derives the image name from the **working directory** and has **no config override** — `_detect_image_name()` in `dbuild/dbuild/config.py` is literally `return base.name.lower()`. Fork checkouts are the usual trap, because `git clone` of `you/papra-daemonless` gives you a `papra-daemonless/` directory, and a local `papra/` may already be taken by the upstream app's source. Note the `.lower()`: a directory with capitals (`SparkyFitness/`) silently becomes `sparkyfitness` — right answer, but not because you chose it.
**Fix:** rename the checkout to exactly the target image name, then regenerate:
```sh
cd .. && mv papra-daemonless papra && cd papra
DBUILD_REGISTRY=ghcr.io/daemonless dbuild generate
```
If the upstream-app directory already owns the name, nest them — `~/src/upstream/papra` and `~/src/images/papra` — rather than suffixing the image repo.
**Catch it early:** `scripts/lint-compose.sh` compares the directory name against the `ghcr.io/daemonless/*` refs in `compose.yaml` and fails on a mismatch. For a `cli`-class image there is no `compose.yaml`, so check the directory name by eye before the first `dbuild generate`.
**Why:** the name is an input to generation, not a recorded setting — so it is wrong from the first generate and stays wrong through every artefact.

### `base:15-pkg` → `manifest unknown` (and other invented base tags)
**Signature:** `dbuild build` or `podman pull` fails on the `FROM` line with `reading manifest <tag> in ghcr.io/daemonless/base: manifest unknown`. Or worse: docs and `BUILD-NOTES.md` name a tag the image was never actually built against, and nobody notices because the build used a different one.
**Cause:** the base repos (`base`, `base-exec`, `base-rcd`, `base-core`) **do not share a tag scheme** — e.g. `base` has no `-pkg` tags while `base-core` uses them — and it is easy to carry a tag across from the wrong one, or from a doc. Any list of tags written down goes stale; don't trust one, including in this file's history.
**Fix:** list the tags before writing one down, and again before you record it in `BUILD-NOTES.md`:
```sh
skopeo list-tags docker://ghcr.io/daemonless/<base-repo> | jq -r '.Tags[]' | grep -v -- '-dl'
```
**Why:** the `-quarterly`/`-latest` suffix selects the **pkg branch** baked into the image, not the FreeBSD minor — so the two repos' suffixes mean different things and neither is guessable. (Found 2026-09-28: a port brief and the process doc both said `base:15-pkg`; the image actually built against `base:15`, and the notes initially claimed the tag that does not exist.)

### "Package X not found" generally
Check the base image's pkg branch first (`quarterly` vs `latest`).

### A patch silently does nothing / unpatched code ships
**Cause:** `COPY patches/x dest/x` **creates** `dest/x` if upstream moved/renamed it — unpatched source then ships and crashes.
**Fix:** guard before COPY:
```dockerfile
RUN for f in dest/a dest/b ; do test -f "$f" || { echo "PATCH DRIFT: $f gone upstream"; exit 1; }; done
```

### A `.patch` fails to apply: `Hunk #N FAILED`, `1 out of 1 hunks failed`, `.rej` saved
**Cause:** the patch's context lines (or `@@ -N` line numbers) don't match the real upstream file — usually a hand-written/reconstructed diff against the wrong version. `--fuzz=0` correctly refuses it.
**Critical:** `dbuild generate` + `lint-compose.sh` **never apply patches** — they pass on a broken patch. Only `dbuild build` catches this. Never call a patch done until a build applies it.
**Fix — generate the patch from a real diff against the *pinned* upstream, not from memory:**
```sh
git clone --depth 1 --branch <TAG> <upstream-url> /tmp/src
cp /tmp/src/<rel/path> /tmp/orig            # then edit /tmp/src/<rel/path>
diff -u --label a/<rel/path> --label b/<rel/path> /tmp/orig /tmp/src/<rel/path> > patches/foo.patch
patch -p1 --dry-run --fuzz=0 < patches/foo.patch   # must report "Hunk #1 succeeded"
```
Note the COPY-source path may differ from the `-p1` path (e.g. upstream `backend/trip/...` → image `/app/trip/...`); set the `diff` labels to the *in-image* path.

### `dbuild build` "succeeded" but the image is broken
Read the inner build log, not the wrapper exit code. Grep `error:` / `Failed` / `gyp ERR`.

### `dbuild generate` wrote README.md (+ Containerfile) with the wrong registry org (your fork instead of `ghcr.io/daemonless`)
**Cause:** `dbuild` auto-derives the registry org from `git remote get-url origin` (`config.py:_detect_registry`). When you run from a fork, origin is your own account, so generated docs/image refs point at your fork's org instead of `ghcr.io/daemonless`.
**Fix:** force the upstream registry when generating from a fork:
```sh
DBUILD_REGISTRY=ghcr.io/daemonless dbuild generate
```
Precedence: the top-level `dbuild --registry <r> …` flag / `DBUILD_REGISTRY` env → org from `origin` → fallback `ghcr.io/daemonless`.
`README.md` is generated **and shipped**, so don't restore it — regenerate it with the daemonless registry and commit the result. Check: `grep -rhoE 'ghcr\.io/[a-z0-9.-]+/' README.md Containerfile* compose.yaml | sort -u` prints only `ghcr.io/daemonless/`.

### Build hangs for 10+ min AFTER the `RUN` finishes — `storage-applyLayer` pegged at 100% CPU
**Signature:** the last build output is the end of a `RUN` (e.g. `pkg clean` done), then minutes of silence; `ps` shows `storage-applyLayer .../zfs/graph/<hash> (podman)` in **R** state burning CPU, `podman ps` goes sluggish.
**Cause:** podman's **ZFS storage driver** commits a layer by unpacking it file-by-file into a per-layer ZFS dataset. A `node_modules`-heavy layer (node + npm + a JS app = thousands of tiny files) makes this O(files) commit grind for 10+ min. It's CPU-bound (R), not stuck (D), and not a disk-space issue.
**Fix:** nothing required — it finishes; just wait. To reduce it: keep the node layer lean, or use the overlay/vfs storage driver for build hosts. Disk: `df`/`zfs list` to rule out a full pool.
**Why:** ZFS driver = dataset-per-layer; file-count, not byte-count, dominates commit time.

### Large JS monorepo build OOMs or destabilises the build host
**Signature:** upstream's own Dockerfile sets a large `NODE_OPTIONS=--max_old_space_size=<N>` (e.g. 8192) for its client/webpack/vite build step; the build host has less physical memory than that heap size assumes, and/or runs other services concurrently.
**Fix:** start well below upstream's value (e.g. half) and only raise it if the build actually OOMs: `ENV NODE_OPTIONS=--max_old_space_size=4096` (scoped to the builder stage only, before the memory-heavy build step — never carried into the runtime stage). Check the real usable memory first (FreeBSD: `sysctl hw.usermem`, not `hw.physmem` — physical RAM minus what's already reserved/in-use by other services on a shared build host).
**Why:** upstream's value is tuned for their own CI runners, which are usually dedicated and larger than a shared build/dev host; a large heap during a JS bundler build (V8 GC working set, not the artifact size) is a common way to wedge or crash a shared machine, not just fail the build cleanly. (Found 2026-09-28 building actual/sync-server: host has 16GB physical but ~9GB `hw.usermem`; `--max_old_space_size=4096` built clean at that ceiling.)

### Two `dbuild build`s (or build + `podman pull`) at once wedge podman
**Signature:** everything hangs; `podman ps` times out; nothing is downloading (`sockstat` shows no registry connection).
**Cause:** podman serialises on a single image-store lock. Concurrent build/pull operations queue behind a held lock; a stuck one wedges the lot.
**Fix:** run builds **one at a time**, and not alongside a `podman-compose pull`. Recovery: stop the extra builds, kill any orphaned `buildah`/stuck `podman images` PIDs; running containers (`conmon`) are unaffected and keep serving.
**Why:** daemonless podman has no broker arbitrating concurrent store access — the lock is it.

### `dbuild build` dies with exit 137; the log just stops mid-build (often inside `npm ci`)
**Signature:** the shell tool returns "Exit code 137" with no build error above it; the tee'd log ends mid-step; the session may end right there.
**Cause:** the agent harness SIGKILLs foreground shell commands at its max timeout (commonly ~10 min). A cold FreeBSD image build (pkg install + npm ci + compile + ZFS layer commits) routinely takes longer. Nothing is wrong with the build — the harness killed it. (2026-07-04: this ended a whole port session mid-`npm ci`, before `WIP.md` could be written.)
**Fix:** run `scripts/build.sh` detached — your agent's background-execution mode (Claude Code: `run_in_background: true`), else `nohup`/`tmux`/a second terminal — then grep `build.log` after it completes. Never foreground a build.
**Why:** the timeout is a harness ceiling, not a build failure; backgrounded commands aren't subject to it.

### CIT wastes 120s: `No ready signal after 120s (continuing anyway)`
**Signature:** CIT passes, but only after a full 120-second stall before the port/health probes.
**Cause:** dbuild's health-mode CIT greps container logs for default ready patterns (`Warmup complete|services.d.*done|Application started|Startup complete|listening on|is ready`). If the app's startup line matches none of them (e.g. IPP logs `Server started on port 3000`), dbuild burns the whole `wait` window before probing.
**Fix:** tell dbuild the app's real startup line in `.daemonless/config.yaml`:
```yaml
cit:
  ready: "Server started on port"   # the literal line the app logs when up
```
(or have the launcher echo a line containing `listening on`).
**Why:** the ready gate is log-regex-based; an unmatched pattern silently degrades to a fixed sleep on every test run.

### Container gets `UND_ERR_CONNECT_TIMEOUT` reaching the host or a sibling container
**Signature:** app logs `TypeError: fetch failed … ConnectTimeoutError (attempted address: 10.88.0.1:<port>)` (or a sibling container's `10.88.0.x`), while host→container curl works fine.
**Cause:** pf on the FreeBSD host filters podman-bridge traffic — bridge→host and container→container connections can be blocked. Only host→container is guaranteed.
**Fix:** when a test needs a reachable helper (e.g. a smoke test's dummy upstream), share ONE network namespace: `podman run --network container:<main> -e <PORT_VAR>=19998 <image>` and point the main app at `http://127.0.0.1:19998`.
**Why:** loopback inside a single netns never crosses the bridge, so no firewall policy applies. (Found 2026-07-04 building the immich-public-proxy smoke test.)

---

## Go
- Mostly static; watch cgo deps needing system libs.
- **A Go app in FreeBSD ports is the cheapest port there is.** Check `pkg rquery '%o|%n|%v' <app>`
  before planning anything: a CGO-free Go binary packaged in ports means no
  builder stage, no toolchain, no source, no native-module hazards — the same
  two-line `pkg install` shape as `ffmpeg`. Verified on blocky (2026-10-31):
  `dns/blocky`, zero runtime deps (`pkg rquery '%dn-%dv'` empty), one `FROM`.

### A hand-written config template goes stale silently — validate it at build time
**Signature:** none at build time. At runtime, a container that restarts forever,
or worse, one that starts against a config the app partially ignored.
**Cause:** images that ship a default/sample config have a hand-written file that
nothing checks. The app's config schema changes on a version bump and the
template is now wrong, but no build step reads it.
**Fix:** run the app's own config validator against the template in the build,
and make it a copy so you never write into a volume mount point:
```dockerfile
RUN test -f /usr/local/share/<app>/config.yml.default \
    && cp /usr/local/share/<app>/config.yml.default /tmp/config-check.yml \
    && <app> validate --config /tmp/config-check.yml \
    && rm /tmp/config-check.yml
```
**Why:** it converts a runtime crash into a build failure, and it is the only
thing that notices the template drifted. Caught a real error first time out on
blocky (see the next entry). If the app has no validator subcommand, the
fallback is a start-with-timeout smoke step — weaker, but not nothing.

### `blocky validate` fails with `configuration path does not exist` even though `BLOCKY_CONFIG_FILE` is set
**Cause:** `validate`'s `RunE` calls `os.Stat(configPath)` **before** `initConfig()`,
and `initConfig` is the only place the env var is read (`cmd/validate.go`,
`cmd/root.go` at v0.35.0). The root command's `PreRunE` is **not persistent**, so
subcommands don't inherit it. With only the env var set, `validate` stats the
flag default `./config.yml` and misses.
**Fix:** pass the flag explicitly — `blocky validate --config /path/to/config.yml`.
**Why:** and note the inverse, which is the sharper edge: because the env var is
only consulted while `--config` is at its default, **passing `--config` to the
serve command silently disables `BLOCKY_CONFIG_FILE`**. Pick one mechanism per
call site and comment it, or a later edit will quietly break the documented
override. (Generalises to any cobra app that resolves an env-var fallback inside
a config loader rather than in flag binding.)

### blocky config: `field loading not found in type config.Config`
**Cause:** `loading:` is **not** a top-level key. It is nested under `blocking:`
(and separately under `filtering:`). Same trap for anything else that looks
global in the docs — read `docs/config.yml` at the **pinned tag** for the nesting,
not the prose in `configuration.md`.
**Fix:** indent it under `blocking:`. Also `blockType: zeroIp` — lowercase `p`;
`zeroIP` is rejected.
**Why:** blocky unmarshals strictly (`additional properties 'loading' not allowed`),
so a misplaced key is a hard failure rather than a silently ignored one — which is
the good outcome, provided something runs the validator. See the entry above.

### An image whose app binds a privileged port (<1024) on FreeBSD must run as root
**Cause:** FreeBSD reserves ports below 1024 to root and has **no capability
mechanism** to delegate a single port. Linux images solve this with
`cap_net_bind_service` (`setcap`, or `docker run --cap-add NET_BIND_SERVICE`);
there is no FreeBSD equivalent.
**Fix:** on **base-exec**, set `ENV DAEMONLESS_USER=root` — `/init` otherwise
drops to `bsd` via `dsu`. On legacy **base** (s6), omit `USER` and drop the
`exec s6-setuidgid bsd` tail from the run script. Either way set
`user: "root"` in `compose.yaml`'s `x-daemonless` block. Document why at the
call site — it reads like an oversight otherwise, and it is the one thing a
reviewer will stop on.
**Why:** there are three alternatives, not two, and you should reject all three
explicitly or a reviewer will think you rejected straw men:
`net.inet.ip.portrange.reservedhigh=0` is a per-jail sysctl that unreserves
*every* low port in the jail (ports from `reservedlow` to `reservedhigh` are
root-only; `reservedlow` defaults to 0, so `reservedhigh` is the one that
matters); `mac_portacl` needs a kernel module loaded on the
**host** plus a policy keyed to a uid inside the container, which is host state
an image cannot carry — it breaks the property that the image is self-contained.
**The third is the one that actually works and is upstream's own suggestion:
run on a high port** (e.g. `5353`) as the unprivileged user and publish
`53:5353/udp` on the host — no capability, no sysctl, no kernel module, no host
state. Reject it only if you can say why. On blocky the reason is `appjail:
true`: the container gets its OWN address, so users point a resolver straight at
it on :53 and there is no host port to map — binding :53 *inside* the container
is what makes its address usable as a nameserver. Under plain podman with
published ports, the high-port route is the better answer and the image does not
need root at all.

### CI `lint` job fails: `Invalid category '<X>'. Valid: Base, Databases, ...`
**Signature:** the build and CIT jobs go green, `scripts/lint-compose.sh` passes
locally, and the `build / lint` job fails with
`Invalid category 'Networking'. Valid: Base, Databases, Development, Downloaders,
Infrastructure, Media Management, Media Servers, Monitoring, Network, Photos &
Media, Productivity, Security, Utilities` — then `1 repo with errors`.
**Cause:** `dbuild lint` (what CI runs) validates `x-daemonless.category`
against a closed list. `scripts/lint-compose.sh` (the toolkit's linter) only
cross-checks compose against the Containerfile LABEL, so two matching-but-invalid
values pass locally and fail in CI. The plausible-but-wrong values are the trap:
**`Networking` is invalid, it is `Network`**; likewise there is no `Apps`,
`Tools` or `Media`.
**Fix:** `dbuild lint` from the repo root **before pushing** — it reproduces the
CI failure exactly and prints the current valid list. Then fix `compose.yaml` and
re-run `dbuild generate`.
**Why:** the two linters check disjoint things and neither supersedes the other.
Run both. And template the label rather than hardcoding it —
`io.daemonless.category="{{ category }}"` in the `.j2` — or fixing the category
means fixing it twice and `lint-compose` will flag the drift in between.
(Found on blocky 2026-10-31: first CI run on `main` went red on exactly this
while every local gate was green.)

### Porting an image off s6: `base` → `base-exec`
**Cause:** the project is moving away from s6 (maintainer, 2026-10-31). `base`
still works, but new single-process images should use `base-exec`, whose layout
is NOT the s6 layout — `/etc/services.d` and `/etc/cont-init.d` simply do not
exist there, and writing to them is silently ignored.
**Fix:** the four-part move, verified on blocky:
```
FROM ghcr.io/daemonless/base-exec:${BASE_VERSION}   # was base:${BASE_VERSION}
root/etc/services.d/<app>/run   →  root/daemonless/libexec/<app>  (sets env, then exec)
                                   + CMD ["/daemonless/libexec/<app>"]
root/etc/cont-init.d/NN-foo     →  root/daemonless/init.d/NN-foo   (NN > 10)
(stay root?)                    →  ENV DAEMONLESS_USER=root
```
`root/healthz` is unchanged and still overrides the base's generic one. Drop
`s6-setuidgid` from the old run script: `/init` already drops to
`DAEMONLESS_USER` via `dsu` before it execs `CMD`. Copy a sibling's layout
(`navidrome`, `radarr`) rather than inventing one.
**Why, and the two traps:**
1. **No supervisor.** `/init` runs `init.d/*` (the base's, then yours, in
   lexical order), then `custom.d/*`, then **execs `CMD`** — the app replaces `/init`, gets the runtime's signals, and its exit
   is the container's. Restart is the runtime's job, so set
   `restart: unless-stopped` in `compose.yaml`. If you actually need in-container
   supervision of 2+ services, that is `base-rcd` (`rcd(8)` units in
   `/usr/local/etc/rcd.d`), not `base-exec`.
2. **Init scripts run as root**, after the base's `init.d/10-usermod` has
   chowned `/config` to PUID:PGID. So any file your `init.d` script CREATES
   under `/config` is root-owned, and CIT fails with
   `ownership (PUID=1000): paths under /config not owned by 1000:1000`. Chown it
   yourself (`chown bsd:bsd "$f"` — `bsd` is already remapped to PUID:PGID),
   guarded by `[ "$(id -u)" = 0 ]` so a `--user` run skips it.

### `dbuild init`'s scaffold is legacy-shaped — replace it, don't edit around it
**Cause:** `dbuild init` still scaffolds the s6 layout on `base`:
`FROM ghcr.io/daemonless/base:${BASE_VERSION}`,
`root/etc/services.d/<app>/run` (with `s6-setuidgid`), and a generic
`root/healthz`. The source template (`Containerfile.j2`) carries a placeholder
`DOWNLOAD_URL="https://example.com/<app>-${APP_VERSION}.tar.gz"`.
**Fix:** treat it as a starting point for metadata only. For a new image, move
to `base-exec` with an `init.d` + `libexec` layout (see "Porting an image off
s6" above), and replace the `example.com` URL with the real pinned release
asset — or delete the source template entirely if the image is pkg-only.
**Why:** a placeholder URL fails loudly at build time, which is fine; the
s6 layout is the quiet trap, because on `base-exec` `/etc/services.d` is
silently ignored: the container boots, runs no app, and `/init` sleeps.
