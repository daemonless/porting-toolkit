#!/bin/sh
# Cross-checks compose.yaml metadata against Containerfile LABELs.
# Flags mismatches that would confuse the daemonless catalog or runtime.
#
# Usage: scripts/lint-compose.sh [compose.yaml] [Containerfile]

set -e

COMPOSE="${1:-compose.yaml}"
CONTAINERFILE="${2:-Containerfile}"
ERRORS=0

if [ ! -f "$COMPOSE" ]; then
  echo "ERROR: $COMPOSE not found" >&2
  exit 1
fi
if [ ! -f "$CONTAINERFILE" ]; then
  echo "ERROR: $CONTAINERFILE not found" >&2
  exit 1
fi

warn() {
  echo "MISMATCH: $1" >&2
  ERRORS=$((ERRORS + 1))
}

info() {
  echo "INFO: $1" >&2
}

# ---- Directory name == image name -------------------------------------------
# `dbuild` derives the image name from the working directory and has no config
# override, so a repo checked out as `foo-daemonless` builds `foo-daemonless`:
# wrong README, wrong registry refs, wrong built tag. Catch it here, because the
# only other symptom is a reviewer noticing the name in the PR.
DIRNAME=$(basename "$(pwd)")
compose_images=$(grep -oE 'ghcr\.io/daemonless/[A-Za-z0-9._-]+' "$COMPOSE" 2>/dev/null \
                 | sed 's|.*/||' | sort -u)
if [ -n "$compose_images" ]; then
  if ! echo "$compose_images" | grep -qxF "$DIRNAME"; then
    warn "image name: directory is '$DIRNAME' but compose.yaml references $(echo "$compose_images" | tr '\n' ' ')"
    echo "          dbuild names the image after the DIRECTORY. Rename the checkout to match" >&2
    echo "          the intended image name, then re-run \`dbuild generate\`." >&2
  fi
fi

# Extract values from Containerfile LABELs
label_port=$(grep 'io.daemonless.port=' "$CONTAINERFILE" | sed 's/.*io.daemonless.port="\([^"]*\)".*/\1/')
label_category=$(grep 'io.daemonless.category=' "$CONTAINERFILE" | sed 's/.*io.daemonless.category="\([^"]*\)".*/\1/')
label_volumes=$(grep 'io.daemonless.volumes=' "$CONTAINERFILE" | sed 's/.*io.daemonless.volumes="\([^"]*\)".*/\1/')
label_health=$(grep 'io.daemonless.healthcheck-url=' "$CONTAINERFILE" | sed 's/.*io.daemonless.healthcheck-url="\([^"]*\)".*/\1/')
label_title=$(grep 'org.opencontainers.image.title=' "$CONTAINERFILE" | sed 's/.*org.opencontainers.image.title="\([^"]*\)".*/\1/')
expose_port=$(grep '^EXPOSE' "$CONTAINERFILE" | awk '{print $2}')

# Extract values from compose.yaml (basic grep — no yaml parser needed)
compose_port=$(grep -E '^\s+- [0-9]+:[0-9]+' "$COMPOSE" | head -1 | sed 's/.*- \([0-9]*\):.*/\1/')
compose_category=$(grep 'category:' "$COMPOSE" | head -1 | sed 's/.*category: *"\(.*\)"/\1/')
compose_title=$(grep 'title:' "$COMPOSE" | head -1 | sed 's/.*title: *"\(.*\)"/\1/')
# Anchor to the START of the line, not the last slash on it. The previous
# `sed 's/.*\(\/[^:]*\).*/\1/'` was greedy, so a description containing any
# further slash ("read-only", a URL) made it report a path that isn't one —
# with no error message pointing at the cause. (Found on blocky 2026-10-31.)
compose_volumes_doc=$(grep -A2 'volumes:' "$COMPOSE" \
                      | sed -n 's|^[[:space:]]*\(/[^:]*\):[[:space:]]*".*|\1|p' | head -1)
compose_upstream=$(grep 'upstream_url:' "$COMPOSE" | sed 's/.*upstream_url: *"\(.*\)"/\1/')
compose_freshports=$(grep 'freshports_url:' "$COMPOSE" | sed 's/.*freshports_url: *"\(.*\)"/\1/')

# Cross-check port.
# These compare the declared primary port against the SET of ports the image
# exposes/publishes, not against a single value. The old equality test assumed
# one port per image, so anything with a service port plus an API port (a DNS
# resolver, a mail server) reported mismatches that were not mismatches.
# (Found on blocky 2026-10-31, which exposes 53/udp, 53/tcp and 4000.)
compose_ports_all=$(grep -oE '^[[:space:]]*- "?[0-9]+:[0-9]+' "$COMPOSE" 2>/dev/null \
                    | grep -oE '[0-9]+:' | tr -d ':' | sort -u)
expose_ports_all=$(grep '^EXPOSE' "$CONTAINERFILE" 2>/dev/null \
                   | sed 's/^EXPOSE//' | tr ' ' '\n' | grep -oE '^[0-9]+' | sort -u)

if [ -n "$label_port" ] && [ -n "$compose_ports_all" ]; then
  if ! echo "$compose_ports_all" | grep -qxF "$label_port"; then
    warn "port: Containerfile LABEL=$label_port is not among compose.yaml's published ports ($(echo "$compose_ports_all" | tr '\n' ' '))"
  fi
fi
if [ -n "$label_port" ] && [ -n "$expose_ports_all" ]; then
  if ! echo "$expose_ports_all" | grep -qxF "$label_port"; then
    warn "port: Containerfile LABEL=$label_port is not among EXPOSE's ports ($(echo "$expose_ports_all" | tr '\n' ' '))"
  fi
fi

# Cross-check category
if [ -n "$label_category" ] && [ -n "$compose_category" ] && [ "$label_category" != "$compose_category" ]; then
  warn "category: Containerfile LABEL=\"$label_category\" vs compose.yaml=\"$compose_category\""
fi

# Cross-check title
if [ -n "$label_title" ] && [ -n "$compose_title" ] && [ "$label_title" != "$compose_title" ]; then
  warn "title: Containerfile LABEL=\"$label_title\" vs compose.yaml=\"$compose_title\""
fi

# Check volumes documentation matches actual VOLUME
if [ -n "$label_volumes" ] && [ -n "$compose_volumes_doc" ]; then
  if ! echo "$label_volumes" | grep -qF "$compose_volumes_doc"; then
    warn "volumes: Containerfile LABEL=\"$label_volumes\" but compose docs reference \"$compose_volumes_doc\""
  fi
fi

# Healthcheck wiring: a shipped root/healthz with no LABEL pointing at it is
# dead weight — dbuild's CIT probes the endpoint over HTTP, so external tooling
# is the only consumer of the script, and it finds it via the label.
if [ -f root/healthz ] && [ -z "$label_health" ]; then
  warn "healthcheck: root/healthz is shipped but no io.daemonless.healthcheck-url LABEL points at it"
fi
# Only comparable when the label is a literal: dbuild keeps ARG references
# (`${HEALTHCHECK_ENDPOINT}`) unexpanded in the generated Containerfile, and a
# literal-vs-port comparison on those is a guaranteed false positive.
case "$label_health" in
  ''|*'${'*) : ;;
  *)
    if [ -n "$label_port" ] && ! echo "$label_health" | grep -qF "$label_port"; then
      warn "healthcheck: LABEL healthcheck-url ($label_health) does not reference the declared port ($label_port)"
    fi
    ;;
esac

# Check freshports URL looks real (not a copy-paste placeholder)
if [ -n "$compose_freshports" ]; then
  app_name=$(echo "$label_title" | tr '[:upper:]' '[:lower:]')
  if ! echo "$compose_freshports" | grep -qi "$app_name" 2>/dev/null; then
    info "freshports_url ($compose_freshports) doesn't reference the app name — verify it exists"
  fi
fi

# Check upstream_url points to daemonless, not upstream (common copy-paste error)
if [ -n "$compose_upstream" ]; then
  if ! echo "$compose_upstream" | grep -q 'daemonless/' 2>/dev/null; then
    info "upstream_url ($compose_upstream) should point to daemonless/<image>, not the upstream repo"
  fi
fi

# ---- Quality floors (mechanical standards — model-independent) ----
J2="${3:-Containerfile.j2}"
if [ -f "$J2" ]; then
  # Floor 1: upstream must be pinned to a release tag, never a moving ref
  if grep -qE 'ARG +[A-Za-z_]*VERSION *= *"?(main|master|latest|HEAD)"?[[:space:]]*$' "$J2" \
     || grep -qE '(--branch|-b) +(main|master)([[:space:]]|"|$)' "$J2"; then
    warn "version pin: $J2 builds a moving ref (main/master/latest) — pin a release tag"
  fi

  # Floor 2: patches must apply strictly and be guarded against upstream drift
  if [ -d patches ] && [ -n "$(ls patches/ 2>/dev/null)" ]; then
    if grep -q 'patch ' "$J2" && ! grep -q 'fuzz=0' "$J2"; then
      warn "patches: applied without --fuzz=0 — context drift will apply silently wrong"
    fi
    if grep -qE 'COPY +patches/' "$J2" && ! grep -q 'test -f' "$J2"; then
      warn "patches: COPY without a 'test -f' patch-rot guard — a moved upstream file ships unpatched"
    fi
  fi
fi

# Floor 3: no compiler/toolchain in the RUNTIME stage (builder stage is fine)
runtime_stage=$(awk '/^FROM /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$CONTAINERFILE")
toolchain_hits=$(printf '%s' "$runtime_stage" | grep -nE 'FreeBSD-(clang|lld|toolchain|clibs-dev)|node-gyp' || true)
if [ -n "$toolchain_hits" ]; then
  warn "runtime stage installs build toolchain (keep it builder-only): $(printf '%s' "$toolchain_hits" | head -3 | tr '\n' ' ')"
fi

# ---- Pristine repo: no porting artifacts in the commit ----------------------
# No surveyed daemonless image repo tracks scripts/, adapter config or the
# porting paperwork (see .porting/shipped-files.md). .gitignore covers the
# default case; this catches an earlier `git add -f` or a pre-existing path.
if [ -d .git ]; then
  stowaways=$(git ls-files -- scripts .porting .claude CLAUDE.md AGENTS.md \
              PORT-BRIEF.md PROCESS-LOG.md RUN-RECORD.md WIP.md \
              JOURNAL.log build.log cit-output.log .cit-passed 2>/dev/null)
  if [ -n "$stowaways" ]; then
    warn "pristine repo: porting artifacts are tracked and would land in the PR: $(printf '%s' "$stowaways" | tr '\n' ' ')"
    echo "          These are porting-time only. \`git rm --cached\` them; see .porting/shipped-files.md." >&2
    echo "          A runtime script belongs in root/, a build step in Containerfile.j2 or patches/." >&2
  fi
fi

# Summary
if [ "$ERRORS" -eq 0 ]; then
  echo "lint-compose: all checks passed"
  exit 0
else
  echo "lint-compose: $ERRORS mismatch(es) found" >&2
  exit 1
fi
