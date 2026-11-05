#!/bin/sh
# Install or refresh the daemonless porting toolkit into an image repo.
#
# Usage, from the image repo root:
#   /path/to/porting-toolkit/install.sh                  # first install
#   /path/to/porting-toolkit/install.sh --refresh        # update an existing install
#   /path/to/porting-toolkit/install.sh --agent none     # neutral files + git rails only
#   /path/to/porting-toolkit/install.sh --list-agents
#
# What lands where:
#   .porting/            agent-neutral process, cookbook, prompts, templates
#   scripts/             the gates: build.sh, cit-with-logs.sh, lint-compose.sh
#   pre-push git hook    the CIT rail (agent-agnostic — holds for humans too)
#   .git/info/exclude    ignore rules for the porting artifacts (not .gitignore)
#   AGENTS.md            per-image agent entry point (first install only)
#   <adapter>            optional per-agent in-session enforcement
#
# The cookbook is copied, not symlinked, so it works offline. After a port,
# PR any new cookbook entries back to the toolkit repo. --refresh never
# discards local cookbook entries: a locally edited cookbook is backed up first.

set -e

TOOLKIT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_DIR="$(pwd)"
REFRESH=false
AGENT=claude-code

while [ $# -gt 0 ]; do
  case "$1" in
    --refresh)     REFRESH=true; shift ;;
    --agent)       AGENT="$2"; shift 2 ;;
    --agent=*)     AGENT="${1#--agent=}"; shift ;;
    --list-agents) ls "$TOOLKIT_DIR/adapters"; exit 0 ;;
    -h|--help)     sed -n '2,20p' "$0"; exit 0 ;;
    *)             echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ "$TOOLKIT_DIR" = "$TARGET_DIR" ]; then
  echo "ERROR: run this from the image repo, not the toolkit repo" >&2
  exit 1
fi

if [ "$AGENT" != none ] && [ ! -d "$TOOLKIT_DIR/adapters/$AGENT" ]; then
  echo "ERROR: no adapter '$AGENT'. Available: $(ls "$TOOLKIT_DIR/adapters" | tr '\n' ' ')" >&2
  echo "       Use --agent none to install the neutral files and git rails only." >&2
  exit 2
fi

# .git is a directory in a normal clone and a file in a worktree; ask git.
IN_GIT=false
if git rev-parse --git-dir >/dev/null 2>&1; then
  IN_GIT=true
else
  echo "WARNING: not a git repo — installing anyway (the pre-push rail needs one)" >&2
fi

echo "[toolkit] Source: $TOOLKIT_DIR"
echo "[toolkit] Target: $TARGET_DIR"
echo "[toolkit] Agent:  $AGENT"

# ---- Agent-neutral content --------------------------------------------------
# NOTE the /. on the source: "copy contents" portably. A bare trailing slash
# only means contents under BSD cp; GNU cp (Linux) nests a subdir instead,
# which silently dropped every hook on non-BSD installs (2026-07-04).
# Porters append to .porting/cookbook.md. .cookbook.shipped is the copy as
# installed; if the live cookbook differs from it, keep a backup before
# overwriting so unshipped entries survive a refresh.
mkdir -p .porting
if [ -f .porting/cookbook.md ] && ! cmp -s .porting/cookbook.md .porting/.cookbook.shipped 2>/dev/null \
   && ! cmp -s .porting/cookbook.md "$TOOLKIT_DIR/porting/cookbook.md"; then
  backup=".porting/cookbook.local-$(date -u +%Y%m%dT%H%M%SZ).md"
  cp .porting/cookbook.md "$backup"
  echo "WARNING: .porting/cookbook.md had local changes — saved to $backup" >&2
  echo "         Merge any new entries back into .porting/cookbook.md and PR them to the toolkit." >&2
fi
cp -R "$TOOLKIT_DIR/porting/." .porting/
cp "$TOOLKIT_DIR/porting/cookbook.md" .porting/.cookbook.shipped
echo "[toolkit] Installed .porting/ (process, cookbook, prompts, templates)"

mkdir -p scripts
cp "$TOOLKIT_DIR/scripts/"*.sh scripts/
chmod +x scripts/*.sh
echo "[toolkit] Installed scripts/ (build, cit-with-logs, lint-compose)"

# ---- Git rails (hold no matter what drives the repo) ------------------------
if $IN_GIT; then
  HOOKS_DIR=$(git rev-parse --git-path hooks)
  mkdir -p "$HOOKS_DIR"
  if ! git rev-parse HEAD >/dev/null 2>&1; then
    echo "WARNING: repo has no commits yet — make an initial commit before starting a port" >&2
    echo "         (branch-off-upstream rules and the pre-push rail assume one)" >&2
  fi
  if [ -f "$HOOKS_DIR/pre-push" ] && ! grep -q 'cit-passed' "$HOOKS_DIR/pre-push" 2>/dev/null; then
    echo "WARNING: existing $HOOKS_DIR/pre-push left untouched — add the .cit-passed check to it manually" >&2
  else
    cp "$TOOLKIT_DIR/scripts/pre-push.git-hook" "$HOOKS_DIR/pre-push"
    chmod +x "$HOOKS_DIR/pre-push"
    echo "[toolkit] Installed git pre-push rail (blocks push without a CIT pass)"
  fi
fi

# ---- Per-agent adapter (optional) -------------------------------------------
case "$AGENT" in
  none)
    echo "[toolkit] Skipped agent adapter (--agent none)"
    ;;
  claude-code)
    SRC="$TOOLKIT_DIR/adapters/claude-code"
    if [ "$REFRESH" = true ] && [ -f .claude/settings.local.json ]; then
      cp .claude/settings.local.json "$TARGET_DIR/.settings.local.json.bak"
    fi
    for dir in agents hooks skills; do
      mkdir -p ".claude/$dir"
      cp -R "$SRC/$dir/." ".claude/$dir/"
    done
    cp "$SRC/settings.json" .claude/settings.json
    chmod +x .claude/hooks/*.sh
    if [ -f "$TARGET_DIR/.settings.local.json.bak" ]; then
      mv "$TARGET_DIR/.settings.local.json.bak" .claude/settings.local.json
      echo "[toolkit] Restored .claude/settings.local.json"
    fi
    [ -f CLAUDE.md ] || cp "$SRC/CLAUDE.md" CLAUDE.md
    echo "[toolkit] Installed .claude/ (skills, subagents, hooks, settings)"
    # Weak-model safety depends on the rails actually landing — verify, loudly.
    if [ ! -x .claude/hooks/enforce-background-build.sh ]; then
      echo "ERROR: hooks did not install correctly — do not start a port until fixed" >&2
      exit 1
    fi
    ;;
esac

# ---- Keep the image repo pristine -------------------------------------------
# A finished image repo ships the image, not the porting scaffolding; see
# porting/shipped-files.md. The ignore rules go in the clone's own
# .git/info/exclude so they never land in the image repo's .gitignore.
if $IN_GIT; then
  IGNORE_FILE=$(git rev-parse --git-path info/exclude)
  mkdir -p "$(dirname "$IGNORE_FILE")"
else
  IGNORE_FILE=.gitignore
fi
if ! grep -qF 'porting-toolkit artifacts' "$IGNORE_FILE" 2>/dev/null; then
  {
    echo ""
    echo "# --- porting-toolkit artifacts (not part of the image) ---"
    echo "# See .porting/shipped-files.md."
    for p in /scripts/ /.porting/ /.claude/ /CLAUDE.md /AGENTS.md /PORT-BRIEF.md \
             /PROCESS-LOG.md /RUN-RECORD.md /BUILD-NOTES.md /WIP.md /sbom-results/ \
             JOURNAL.log build.log cit-output.log .cit-passed; do
      echo "$p"
    done
  } >> "$IGNORE_FILE"
  echo "[toolkit] Added the porting-artifact ignore rules to $IGNORE_FILE"
else
  echo "[toolkit] $IGNORE_FILE already has the porting-artifact ignore rules"
fi

# Ignore rules do not apply to files already tracked — say so loudly.
if $IN_GIT && git rev-parse HEAD >/dev/null 2>&1; then
  tracked=$(git ls-files -- scripts .porting .claude CLAUDE.md AGENTS.md \
            PORT-BRIEF.md PROCESS-LOG.md RUN-RECORD.md BUILD-NOTES.md WIP.md 2>/dev/null | head -5)
  if [ -n "$tracked" ]; then
    echo "WARNING: these porting artifacts are already TRACKED by git — ignore rules do not apply:" >&2
    echo "$tracked" | sed 's/^/           /' >&2
    echo "         git rm --cached them before opening a PR (see .porting/shipped-files.md)" >&2
  fi
fi

# ---- Per-image AGENTS.md (first install only) -------------------------------
if [ ! -f AGENTS.md ]; then
  cp "$TOOLKIT_DIR/porting/templates/AGENTS.md" AGENTS.md
  echo "[toolkit] Created AGENTS.md from template (fill in the placeholders)"
else
  echo "[toolkit] AGENTS.md already exists — left alone"
fi

# ---- Directory name == image name -------------------------------------------
# dbuild derives the image name from the working directory and has no override,
# so this is the cheapest possible moment to catch it: before `dbuild init`.
IMGNAME=$(basename "$TARGET_DIR")
echo ""
echo "[toolkit] This directory is '$IMGNAME' — dbuild will name the image '$IMGNAME'."
case "$IMGNAME" in
  *-daemonless|*-fork|*-port|*-image|*-oci)
    echo "[toolkit] WARNING: that looks like a checkout name, not an image name." >&2
    echo "          Fork clones land as '<app>-daemonless' by default. Every generated" >&2
    echo "          artifact — README, registry refs, built tag — will carry it, silently." >&2
    echo "          Rename the directory to the intended image name BEFORE you start." >&2
    ;;
esac
if [ -f compose.yaml ]; then
  refs=$(grep -oE 'ghcr\.io/daemonless/[A-Za-z0-9._-]+' compose.yaml 2>/dev/null | sed 's|.*/||' | sort -u)
  if [ -n "$refs" ] && ! echo "$refs" | grep -qxF "$IMGNAME"; then
    echo "[toolkit] WARNING: compose.yaml references $(echo "$refs" | tr '\n' ' ')— none match '$IMGNAME'." >&2
    echo "          scripts/lint-compose.sh will fail on this until the directory is renamed." >&2
  fi
fi

echo ""
echo "[toolkit] Done. Next steps:"
echo "  1. Fill in the AGENTS.md placeholders (<APP>, <upstream URL>)"
echo "  2. Point your agent at AGENTS.md, then .porting/process.md"
if [ "$REFRESH" != true ]; then
  echo "  3. After porting, PR new cookbook entries back to the toolkit repo"
fi
