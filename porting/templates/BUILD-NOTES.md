# <app> — FreeBSD daemonless build notes

| | |
|---|---|
| **Upstream** | `<owner/repo>` @ `<tag>` (<license>) |
| **Runtime** | `<node26 + temporal-polyfill / go / python3.11>` |
| **Database** | `<node:sqlite via sqlite-proxy / better-sqlite3 / stdlib sqlite3 / none>` |
| **Base** | `ghcr.io/daemonless/base:<tag>` (service) **or** `base-core:<tag>` (CLI / non-daemon) — use lowest supported minor, e.g. `15-pkg` |

## FreeBSD-specific changes (and WHY)
<!-- one line each; link the cookbook entry it came from -->
- `<change>` — `<reason>` (cookbook: `<signature>`)

## Patches (`patches/`) — why each exists
- `patches/<file>` — `<what upstream does / why FreeBSD needs the change>`. Droppable when: `<condition>`.

## Native dependencies handled
| Dep | FreeBSD status | How handled |
|---|---|---|
| `<dep>` | no prebuilt / no source build / packaged | `<wasm / pin / lazy-load / swap / pkg>` |

## Verified
- `dbuild build` ✅
- `dbuild test` ✅ — `<migrations run / /api/health 200 / screenshot matches baseline>`

## Guards in place
- Patch-rot guard (asserts patched paths still exist upstream)
- Version-drift guard(s): `<e.g. sharp ↔ @img/sharp-wasm32 exact-match>`

## Known limitations
- `<e.g. remote DB mode unsupported — local file DB only>`
- `<e.g. pinned to Python 3.11 until FreeBSD bug 285957 lands>`
