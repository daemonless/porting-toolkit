# <app> — FreeBSD daemonless build notes

| | |
|---|---|
| **Upstream** | `<owner/repo>` @ `<tag>` (<license>) |
| **Runtime** | `<pkg: <origin> / node26 + temporal-polyfill / go / python3.12>` |
| **Database** | `<node:sqlite via sqlite-proxy / better-sqlite3 / stdlib sqlite3 / none>` |
| **Base** | `base-exec:<tag>` (one process) / `base-rcd:<tag>` (several) / `base-core:<tag>` (CLI) — `base` (s6) is legacy. `BASE_VERSION` per variant as set in `.daemonless/config.yaml` |

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
- `<e.g. builds from source because the FreeBSD port lags upstream by two majors>`
