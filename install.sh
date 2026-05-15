#!/usr/bin/env bash
#
# pst installer.
#
# ============================================================================
# AUDITOR'S TOUR (this is what you're piping into bash — read it first)
# ============================================================================
#
#   Quick assurances (verify by grepping this file):
#     ✓ Reads EXACTLY 3 URLs, all from raw.githubusercontent.com/amerry19/pst-cli/main:
#         /bin/pst                    (the CLI binary)
#         /skills/claude-code.md      (if Claude Code detected)
#         /skills/codex.md            (if Codex detected)
#     ✓ Does NOT: make any other network calls, send telemetry, modify
#       login scripts, change $PATH, install background services, or
#       touch anything outside ~/.local/bin or /opt/homebrew/bin or
#       /usr/local/bin (whichever is on your $PATH and writable),
#       ~/.claude/skills/pst/, and ~/.codex/AGENTS.md.
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

  if [ -f "$HOME/.codex/AGENTS.md" ]; then
    strip_pst_block "$HOME/.codex/AGENTS.md"
    ok "Cleaned ~/.codex/AGENTS.md of pst section (if present)"
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

# Claude Code: ~/.claude/skills/pst/SKILL.md
if [ -d "$HOME/.claude" ]; then
  info "Detected Claude Code — installing skill"
  mkdir -p "$HOME/.claude/skills/pst"
  fetch "$REPO_RAW/skills/claude-code.md" "$HOME/.claude/skills/pst/SKILL.md"
  ok "~/.claude/skills/pst/SKILL.md"
  INSTALLED_FOR+=("Claude Code")
fi

# Codex: append delimited section to ~/.codex/AGENTS.md
if [ -d "$HOME/.codex" ]; then
  info "Detected Codex — installing skill block in ~/.codex/AGENTS.md"
  AGENTS_FILE="$HOME/.codex/AGENTS.md"
  touch "$AGENTS_FILE"
  strip_pst_block "$AGENTS_FILE"   # remove any prior block first (idempotent)

  BLOCK=$(mktmp)
  fetch "$REPO_RAW/skills/codex.md" "$BLOCK"

  {
    [ -s "$AGENTS_FILE" ] && printf '\n'
    printf '%s\n' "$MARKER_BEGIN"
    cat "$BLOCK"
    printf '\n%s\n' "$MARKER_END"
  } >> "$AGENTS_FILE"

  ok "~/.codex/AGENTS.md (pst section added)"
  INSTALLED_FOR+=("Codex")
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
else
  printf 'No supported agent harness detected (Claude Code, Codex). pst CLI still works\n'
  printf 'from any shell.\n\n'
fi

cat <<'EOF'
Docs:        https://github.com/amerry19/pst-cli
Uninstall:   curl -fsSL https://raw.githubusercontent.com/amerry19/pst-cli/main/install.sh | bash -s -- --uninstall
EOF

} # ---- end partial-download guard ----
