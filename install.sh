#!/usr/bin/env bash
#
# pst installer.
#
# ============================================================================
# AUDITOR'S TOUR (this is what you're piping into bash — read it first)
# ============================================================================
#
#   Quick assurances (verify by grepping this file):
#     ✓ Reads EXACTLY 2 URLs, all from raw.githubusercontent.com/amerry19/pst-cli/main:
#         /bin/pst                    (the CLI binary)
#         /skills/SKILL.md            (the agent skill — installed to whichever harnesses are detected)
#     ✓ Does NOT: make any other network calls, send telemetry, modify
#       login scripts, change $PATH, install background services, or
#       touch anything outside ~/.local/bin or /opt/homebrew/bin or
#       /usr/local/bin (whichever is on your $PATH and writable),
#       ~/.claude/skills/pst/, and ~/.codex/skills/pst/. The installer
#       also cleans up any prior AGENTS.md-style block from older versions.
#     ✓ macOS only — refuses to run on Linux or Windows.
#     ✓ Idempotent — re-run anytime to update.
#     ✓ --uninstall flag reverses everything cleanly.
#
#   Run with:
#     curl -fsSL https://raw.githubusercontent.com/amerry19/pst-cli/main/install.sh | bash
#
#   Don't trust curl-pipe-to-bash? You shouldn't — it's a real concern.
#   Same install via clone:
#     git clone https://github.com/amerry19/pst-cli.git
#     ./pst-cli/install.sh
#
#   Or pin to a release tag (replace VERSION):
#     curl -fsSL https://raw.githubusercontent.com/amerry19/pst-cli/VERSION/install.sh | bash
#
#   Uninstall:
#     curl -fsSL https://raw.githubusercontent.com/amerry19/pst-cli/main/install.sh | bash -s -- --uninstall
#
#   The whole script is wrapped in `{ ... }` so if curl drops mid-stream,
#   bash never sees the closing brace and refuses to execute partial content.
#
# ============================================================================

{ # ---- partial-download guard (closes at end of file) ----

set -euo pipefail

# ============================================================================
# §1 — Constants
# ============================================================================

REPO_RAW="https://raw.githubusercontent.com/amerry19/pst-cli/main"
MARKER_BEGIN="<!-- BEGIN: pst -->"
MARKER_END="<!-- END: pst -->"
TMPFILES=()

# ============================================================================
# §2 — Helpers
# ============================================================================

info() { printf '→ %s\n' "$*"; }
ok()   { printf '✅ %s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*" >&2; }
fail() { printf '❌ %s\n' "$*" >&2; exit 1; }

# Cleanup any tempfiles we created on exit (success or failure).
cleanup() { for f in "${TMPFILES[@]:-}"; do rm -f "$f"; done; }
trap cleanup EXIT

mktmp() {
  local f
  f=$(mktemp)
  TMPFILES+=("$f")
  printf '%s' "$f"
}

# Strip our delimited block out of a file (used by both install-replace and
# uninstall paths). Idempotent: if the markers aren't found, the file is
# unchanged.
strip_pst_block() {
  local file="$1"
  [ -f "$file" ] || return 0
  grep -q "$MARKER_BEGIN" "$file" || return 0
  local tmp; tmp=$(mktmp)
  awk -v begin="$MARKER_BEGIN" -v end="$MARKER_END" '
    $0 ~ begin { skip=1; next }
    $0 ~ end   { skip=0; next }
    !skip
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

# Download a single file from the repo to a path. Fails the whole script on
# network error so a partial install can't leave a stale binary on disk.
fetch() {
  local url="$1" dest="$2"
  curl -fsSL "$url" -o "$dest" || fail "Failed to download $url — check your network."
}

# ============================================================================
# §3 — Platform + args
# ============================================================================

[ "$(uname -s)" = "Darwin" ] || \
  fail "pst currently only supports macOS. Linux libsecret support is on the roadmap — PRs welcome at https://github.com/amerry19/pst-cli"

MODE="install"
for arg in "$@"; do
  case "$arg" in
    --uninstall) MODE="uninstall" ;;
    --help|-h)   grep '^#' "$0" 2>/dev/null | head -50 | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           fail "unknown option: $arg" ;;
  esac
done

# ============================================================================
# §4 — Pick an install directory on $PATH
# ============================================================================

INSTALL_DIR=""
for d in "$HOME/.local/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
  [[ ":$PATH:" == *":$d:"* ]] || continue
  # Existing + writable, or creatable + writable
  if   [ -d "$d" ] && [ -w "$d" ]; then INSTALL_DIR="$d"; break
  elif [ ! -d "$d" ] && mkdir -p "$d" 2>/dev/null && [ -w "$d" ]; then INSTALL_DIR="$d"; break
  fi
done

[ -n "$INSTALL_DIR" ] || cat >&2 <<EOF
Couldn't find a writable directory on your \$PATH.

Tried: ~/.local/bin, /opt/homebrew/bin, /usr/local/bin

Either add one of those to your PATH, or install manually:
  git clone https://github.com/amerry19/pst-cli.git
  ln -s "\$(pwd)/pst-cli/bin/pst" /some/dir/on/your/path/pst
EOF
[ -n "$INSTALL_DIR" ] || exit 1

PST_BIN="$INSTALL_DIR/pst"

# ============================================================================
# §5 — Uninstall path
# ============================================================================

if [ "$MODE" = "uninstall" ]; then
  info "Uninstalling pst"

  if [ -e "$PST_BIN" ] || [ -L "$PST_BIN" ]; then
    rm -f "$PST_BIN"
    ok "Removed $PST_BIN"
  else
    info "No pst binary at $PST_BIN (already gone)"
  fi

  if [ -f "$HOME/.claude/skills/pst/SKILL.md" ]; then
    rm -f "$HOME/.claude/skills/pst/SKILL.md"
    rmdir "$HOME/.claude/skills/pst" 2>/dev/null || true
    ok "Removed ~/.claude/skills/pst/"
  fi

  if [ -f "$HOME/.codex/skills/pst/SKILL.md" ]; then
    rm -f "$HOME/.codex/skills/pst/SKILL.md"
    rmdir "$HOME/.codex/skills/pst" 2>/dev/null || true
    ok "Removed ~/.codex/skills/pst/"
  fi

  # Legacy cleanup: older versions appended a block to ~/.codex/AGENTS.md.
  if [ -f "$HOME/.codex/AGENTS.md" ] && grep -q "$MARKER_BEGIN" "$HOME/.codex/AGENTS.md" 2>/dev/null; then
    strip_pst_block "$HOME/.codex/AGENTS.md"
    ok "Cleaned legacy pst section from ~/.codex/AGENTS.md"
  fi

  cat <<'EOF'

Keychain secrets stored under service "pst" are NOT removed by this uninstall.
To clear them BEFORE uninstalling next time:
  for n in $(pst list); do pst rm "$n"; done
EOF

  ok "pst uninstalled"
  exit 0
fi

# ============================================================================
# §6 — Install: download the CLI
# ============================================================================

info "Installing pst to $PST_BIN"
TMPBIN=$(mktmp)
fetch "$REPO_RAW/bin/pst" "$TMPBIN"
chmod +x "$TMPBIN"
mv "$TMPBIN" "$PST_BIN"
ok "$PST_BIN"

# ============================================================================
# §7 — Install skill files for detected agent harnesses
# ============================================================================

INSTALLED_FOR=()
CODEX_INSTALLED_FRESHLY=0

# Download the skill once; both harnesses use the same file.
SKILL_TMP=$(mktmp)
SKILL_FETCHED=0

fetch_skill_once() {
  if [ "$SKILL_FETCHED" -eq 0 ]; then
    fetch "$REPO_RAW/skills/SKILL.md" "$SKILL_TMP"
    SKILL_FETCHED=1
  fi
}

# Claude Code: ~/.claude/skills/pst/SKILL.md
if [ -d "$HOME/.claude" ]; then
  info "Detected Claude Code — installing skill"
  fetch_skill_once
  mkdir -p "$HOME/.claude/skills/pst"
  cp "$SKILL_TMP" "$HOME/.claude/skills/pst/SKILL.md"
  ok "~/.claude/skills/pst/SKILL.md"
  INSTALLED_FOR+=("Claude Code")
fi

# Codex: ~/.codex/skills/pst/SKILL.md (same primitive as Claude Code)
if [ -d "$HOME/.codex" ]; then
  info "Detected Codex — installing skill"
  fetch_skill_once
  mkdir -p "$HOME/.codex/skills/pst"
  cp "$SKILL_TMP" "$HOME/.codex/skills/pst/SKILL.md"
  ok "~/.codex/skills/pst/SKILL.md"

  # Migration: older installer versions appended a block to ~/.codex/AGENTS.md.
  # Strip it so users don't get duplicate context.
  if [ -f "$HOME/.codex/AGENTS.md" ] && grep -q "$MARKER_BEGIN" "$HOME/.codex/AGENTS.md" 2>/dev/null; then
    strip_pst_block "$HOME/.codex/AGENTS.md"
    info "Migrated: removed legacy pst section from ~/.codex/AGENTS.md"
  fi

  INSTALLED_FOR+=("Codex")
  CODEX_INSTALLED_FRESHLY=1
fi

# ============================================================================
# §8 — Next steps
# ============================================================================

printf '\n'; ok "Install complete."; printf '\n'

if ! command -v pst >/dev/null 2>&1; then
  warn "pst is installed at $PST_BIN but isn't found via PATH lookup yet."
  warn "Either restart your shell or run: hash -r"
  printf '\n'
fi

cat <<EOF
Verify:
    pst help

Try it (with something on your clipboard):
    pst paste MY_FIRST_SECRET
    pst shape MY_FIRST_SECRET
    pst rm MY_FIRST_SECRET

EOF

if [ "${#INSTALLED_FOR[@]}" -gt 0 ]; then
  printf 'Skill instructions installed for: %s\n' "$(IFS=', '; echo "${INSTALLED_FOR[*]}")"
  printf 'These agents will now know to use pst when you ask them to handle credentials.\n\n'
  if [ "$CODEX_INSTALLED_FRESHLY" -eq 1 ]; then
    printf '↻ Restart Codex to pick up the new skill.\n\n'
  fi
else
  printf 'No supported agent harness detected (Claude Code, Codex). pst CLI still works\n'
  printf 'from any shell.\n\n'
fi

cat <<'EOF'
Docs:        https://github.com/amerry19/pst-cli
Uninstall:   curl -fsSL https://raw.githubusercontent.com/amerry19/pst-cli/main/install.sh | bash -s -- --uninstall
EOF

} # ---- end partial-download guard ----
