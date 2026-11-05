#!/bin/sh
# Cross-checks compose.yaml metadata against Containerfile LABELs, applies the
# toolkit's quality floors, and checks no porting artifact is tracked.
# Not a substitute for `dbuild lint`, which CI runs; run both.
#
# Usage: scripts/lint-compose.sh [compose.yaml] [Containerfile]
#   With no Containerfile argument, checks every generated variant:
#   Containerfile and Containerfile.<tag> (e.g. Containerfile.pkg).
#   compose.yaml is optional: a cli-class image ships none.

set -e

COMPOSE="${1:-compose.yaml}"
ERRORS=0

warn() {
  echo "MISMATCH: $1" >&2
  ERRORS=$((ERRORS + 1))
}

info() {
  echo "INFO: $1" >&2
}

# Same exclusions as dbuild's variant detection (_IGNORE_SUFFIXES).
if [ -n "$2" ]; then
  CONTAINERFILES="$2"
  [ -f "$2" ] || { echo "ERROR: $2 not found" >&2; exit 1; }
else
  CONTAINERFILES=""
  for cf in Containerfile Containerfile.*; do
    [ -f "$cf" ] || continue
    case "$cf" in *.j2|*.bak|*.orig|*.swp|*.tmp|*.linux) continue ;; esac
    CONTAINERFILES="$CONTAINERFILES $cf"
  done
fi
if [ -z "$CONTAINERFILES" ]; then
  echo "ERROR: no generated Containerfile or Containerfile.<tag> found — run \`dbuild generate\`" >&2
  exit 1
fi

HAVE_COMPOSE=false
if [ -f "$COMPOSE" ]; then
  HAVE_COMPOSE=true
elif [ ! -f .daemonless/config.yaml ]; then
  echo "ERROR: neither $COMPOSE nor .daemonless/config.yaml found — is this an image repo?" >&2
  exit 1
else
  info "no $COMPOSE (expected for a cli-class image); skipping compose cross-checks"
fi

# ---- Directory name == image name -------------------------------------------
# dbuild names the image after the working directory and has no override.
DIRNAME=$(basename "$(pwd)")
if $HAVE_COMPOSE; then
  compose_images=$(grep -oE 'ghcr\.io/daemonless/[A-Za-z0-9._-]+' "$COMPOSE" 2>/dev/null \
                   | sed 's|.*/||' | sort -u)
  if [ -n "$compose_images" ] && ! echo "$compose_images" | grep -qxF "$DIRNAME"; then
    warn "image name: directory is '$DIRNAME' but compose.yaml references $(echo "$compose_images" | tr '\n' ' ')"
    echo "          dbuild names the image after the DIRECTORY. Rename the checkout to match" >&2
    echo "          the intended image name, then re-run \`dbuild generate\`." >&2
  fi
fi

# ---- compose.yaml values (basic grep — no yaml parser needed) ---------------
compose_ports_all=""
compose_category=""
compose_title=""
compose_volumes_doc=""
compose_upstream=""
compose_freshports=""
if $HAVE_COMPOSE; then
  compose_ports_all=$(grep -oE '^[[:space:]]*- "?[0-9]+:[0-9]+' "$COMPOSE" 2>/dev/null \
                      | grep -oE '[0-9]+:' | tr -d ':' | sort -u)
  compose_category=$(grep 'category:' "$COMPOSE" | head -1 | sed 's/.*category: *"\(.*\)"/\1/')
  compose_title=$(grep 'title:' "$COMPOSE" | head -1 | sed 's/.*title: *"\(.*\)"/\1/')
  # Anchor at the start of the line: a description with a slash is not a path.
  compose_volumes_doc=$(grep -A2 'volumes:' "$COMPOSE" \
                        | sed -n 's|^[[:space:]]*\(/[^:]*\):[[:space:]]*".*|\1|p' | head -1)
  compose_upstream=$(grep 'upstream_url:' "$COMPOSE" | sed 's/.*upstream_url: *"\(.*\)"/\1/')
  compose_freshports=$(grep 'freshports_url:' "$COMPOSE" | sed 's/.*freshports_url: *"\(.*\)"/\1/')
fi

label() {  # label <file> <key>
  grep "$2=" "$1" | head -1 | sed "s/.*$2=\"\([^\"]*\)\".*/\1/"
}

first_title=""
for CF in $CONTAINERFILES; do
  label_port=$(label "$CF" 'io\.daemonless\.port')
  label_category=$(label "$CF" 'io\.daemonless\.category')
  label_volumes=$(label "$CF" 'io\.daemonless\.volumes')
  label_health=$(label "$CF" 'io\.daemonless\.healthcheck-url')
  label_title=$(label "$CF" 'org\.opencontainers\.image\.title')
  [ -n "$first_title" ] || first_title="$label_title"
  # An image can expose several ports (service + API), so compare against sets.
  expose_ports_all=$(grep '^EXPOSE' "$CF" 2>/dev/null \
                     | sed 's/^EXPOSE//' | tr ' ' '\n' | grep -oE '^[0-9]+' | sort -u || true)

  if [ -n "$label_port" ] && [ -n "$compose_ports_all" ] \
     && ! echo "$compose_ports_all" | grep -qxF "$label_port"; then
    warn "$CF port: LABEL=$label_port is not among compose.yaml's published ports ($(echo "$compose_ports_all" | tr '\n' ' '))"
  fi
  if [ -n "$label_port" ] && [ -n "$expose_ports_all" ] \
     && ! echo "$expose_ports_all" | grep -qxF "$label_port"; then
    warn "$CF port: LABEL=$label_port is not among EXPOSE's ports ($(echo "$expose_ports_all" | tr '\n' ' '))"
  fi
  if [ -n "$label_category" ] && [ -n "$compose_category" ] && [ "$label_category" != "$compose_category" ]; then
    warn "$CF category: LABEL=\"$label_category\" vs compose.yaml=\"$compose_category\""
  fi
  if [ -n "$label_title" ] && [ -n "$compose_title" ] && [ "$label_title" != "$compose_title" ]; then
    warn "$CF title: LABEL=\"$label_title\" vs compose.yaml=\"$compose_title\""
  fi
  if [ -n "$label_volumes" ] && [ -n "$compose_volumes_doc" ] \
     && ! echo "$label_volumes" | grep -qF "$compose_volumes_doc"; then
    warn "$CF volumes: LABEL=\"$label_volumes\" but compose docs reference \"$compose_volumes_doc\""
  fi

  # A shipped root/healthz needs a LABEL pointing at it: external tooling finds
  # it that way (CIT probes over HTTP and does not use the script).
  if [ -f root/healthz ] && [ -z "$label_health" ]; then
    warn "$CF healthcheck: root/healthz is shipped but no io.daemonless.healthcheck-url LABEL points at it"
  fi
  # Only a literal label is comparable; dbuild leaves ${ARG} references unexpanded.
  case "$label_health" in
    ''|*'${'*) : ;;
    *)
      if [ -n "$label_port" ] && ! echo "$label_health" | grep -qF "$label_port"; then
        warn "$CF healthcheck: healthcheck-url ($label_health) does not reference the declared port ($label_port)"
      fi
      ;;
  esac

  # Floor: no compiler/toolchain in the RUNTIME (last) stage.
  runtime_stage=$(awk '/^FROM /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$CF")
  toolchain_hits=$(printf '%s' "$runtime_stage" | grep -nE 'FreeBSD-(clang|lld|toolchain|clibs-dev)|node-gyp' || true)
  if [ -n "$toolchain_hits" ]; then
    warn "$CF runtime stage installs build toolchain (keep it builder-only): $(printf '%s' "$toolchain_hits" | head -3 | tr '\n' ' ')"
  fi
done

if [ -n "$compose_freshports" ] && [ -n "$first_title" ]; then
  app_name=$(echo "$first_title" | tr '[:upper:]' '[:lower:]')
  if ! echo "$compose_freshports" | grep -qiF "$app_name"; then
    info "freshports_url ($compose_freshports) doesn't reference the app name — verify it exists"
  fi
fi

# upstream_url is the app's real upstream; org.opencontainers.image.source
# carries the daemonless repo.
if [ -n "$compose_upstream" ] && echo "$compose_upstream" | grep -q 'github\.com/daemonless/'; then
  info "upstream_url ($compose_upstream) points at daemonless — it should be the app's own upstream repo"
fi

# ---- Quality floors on the templates ----------------------------------------
for J2 in Containerfile.j2 Containerfile.*.j2; do
  [ -f "$J2" ] || continue
  # Floor 1: a source build must pin a release tag, never a moving ref.
  if grep -qE 'ARG +[A-Za-z_]*VERSION *= *"?(main|master|HEAD)"?[[:space:]]*$' "$J2" \
     || grep -qE '(--branch|-b) +(main|master)([[:space:]]|"|$)' "$J2"; then
    warn "version pin: $J2 builds a moving ref (main/master) — pin a release tag"
  fi
  # Floor 2: patches apply strictly and are guarded against upstream drift.
  if [ -d patches ] && [ -n "$(ls patches/ 2>/dev/null)" ]; then
    if grep -q 'patch ' "$J2" && ! grep -q 'fuzz=0' "$J2"; then
      warn "patches: $J2 applies patches without --fuzz=0 — context drift will apply silently wrong"
    fi
    if grep -qE 'COPY +patches/' "$J2" && ! grep -q 'test -f' "$J2"; then
      warn "patches: $J2 has COPY without a 'test -f' patch-rot guard — a moved upstream file ships unpatched"
    fi
  fi
done

# ---- Pristine repo: no porting artifacts in the commit ----------------------
# .gitignore covers the default case; this catches `git add -f` or a path the
# repo tracked before the toolkit was installed. See .porting/shipped-files.md.
if git rev-parse --git-dir >/dev/null 2>&1; then
  stowaways=$(git ls-files -- scripts .porting .claude CLAUDE.md AGENTS.md \
              PORT-BRIEF.md PROCESS-LOG.md RUN-RECORD.md BUILD-NOTES.md WIP.md \
              JOURNAL.log build.log cit-output.log .cit-passed 2>/dev/null)
  if [ -n "$stowaways" ]; then
    warn "pristine repo: porting artifacts are tracked and would land in the PR: $(printf '%s' "$stowaways" | tr '\n' ' ')"
    echo "          These are porting-time only. \`git rm --cached\` them; see .porting/shipped-files.md." >&2
    echo "          A runtime script belongs in root/, a build step in Containerfile.j2 or patches/." >&2
  fi
fi

if [ "$ERRORS" -eq 0 ]; then
  echo "lint-compose: all checks passed ($(echo $CONTAINERFILES))"
  exit 0
else
  echo "lint-compose: $ERRORS mismatch(es) found" >&2
  exit 1
fi
