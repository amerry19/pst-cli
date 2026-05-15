#!/usr/bin/env bash
# Integration tests for pst. Hits the real macOS Keychain under a
# disposable service namespace so we don't touch real secrets.
#
# Run from repo root:  test/test_pst.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PST="$REPO_DIR/bin/pst"
export PST_SERVICE="pst-tests-$$"   # unique per test run

PASS=0
FAIL=0
ERRORS=()

# ----- tiny assert helpers ------------------------------------------------

assert() {
  local label="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1))
    printf "  ✅ %s\n" "$label"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$label")
    printf "  ❌ %s\n" "$label"
  fi
}

# Plain-string contains check (avoids pipeline issues with assert + grep)
str_contains() {
  case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

str_NOT_contains() {
  case "$1" in *"$2"*) return 1 ;; *) return 0 ;; esac
}

# Save the user's actual clipboard so paste tests don't clobber it permanently.
SAVED_CLIPBOARD=$(pbpaste 2>/dev/null || true)

cleanup() {
  # Best-effort: remove any test entries we created
  for name in FOO BAR CASE_LOWERcase MY-KEY M_KEY EMPTY_TEST EXEC_TEST ROTATE_TEST EXISTS_PRESENT PASTE_TEST PROBE_RND PROBE_OPENAI PROBE_RAW TRIM_TRAILING_NEWLINE TRIM_TRAILING_SPACE TRIM_LEADING_SPACE TRIM_BOTH TRIM_INTERNAL TRIM_ONLY_WS; do
    "$PST" rm "$name" >/dev/null 2>&1 || true
  done
  # Restore the user's clipboard
  if [ -n "$SAVED_CLIPBOARD" ]; then
    printf '%s' "$SAVED_CLIPBOARD" | pbcopy 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo
echo "▶︎ pst integration tests (service=$PST_SERVICE)"
echo

# ----- set + get round-trip ----------------------------------------------

echo "set + get round-trip:"
echo "hello-world-123" | "$PST" set FOO >/dev/null
assert "set FOO from stdin succeeds" test "$?" -eq 0

VALUE=$("$PST" get FOO 2>/dev/null)
assert "get FOO returns the stored value" test "$VALUE" = "hello-world-123"
unset VALUE

# ----- update overwrites ---------------------------------------------------

echo
echo "update semantics:"
echo "second-value" | "$PST" set FOO >/dev/null
VALUE=$("$PST" get FOO 2>/dev/null)
assert "set FOO again overwrites the prior value" test "$VALUE" = "second-value"
unset VALUE

# ----- exec injects PST_VALUE ----------------------------------------------

echo
echo "exec contract:"
echo "exec-secret-xyz" | "$PST" set EXEC_TEST >/dev/null
OUT=$("$PST" exec EXEC_TEST -- bash -c 'echo "got=$PST_VALUE"')
assert "exec passes value to child as \$PST_VALUE" test "$OUT" = "got=exec-secret-xyz"
unset OUT

# ----- list shows names only, never values --------------------------------

echo
echo "list contract:"
LIST=$("$PST" list 2>/dev/null)
assert "list contains FOO" str_contains "$LIST" "FOO"
assert "list contains EXEC_TEST" str_contains "$LIST" "EXEC_TEST"
assert "list does NOT contain any stored values" str_NOT_contains "$LIST" "second-value"

# ----- rm removes ---------------------------------------------------------

echo
echo "rm:"
"$PST" rm EXEC_TEST >/dev/null 2>&1
"$PST" get EXEC_TEST >/dev/null 2>&1
RC=$?
assert "get after rm returns non-zero" test "$RC" -ne 0
unset RC

# ----- name validation rejects garbage ------------------------------------

echo
echo "name validation:"
"$PST" set "bad name" </dev/null >/dev/null 2>&1
assert "rejects names with spaces" test "$?" -ne 0

"$PST" set "../etc/passwd" </dev/null >/dev/null 2>&1
assert "rejects names with path traversal chars" test "$?" -ne 0

"$PST" set "1leading-digit" </dev/null >/dev/null 2>&1
assert "rejects names starting with a digit" test "$?" -ne 0

echo "ok" | "$PST" set "M_KEY" >/dev/null 2>&1
assert "accepts valid name with underscores" test "$?" -eq 0

echo "ok" | "$PST" set "MY-KEY" >/dev/null 2>&1
assert "accepts valid name with hyphens" test "$?" -eq 0

# ----- exec without -- separator is rejected ------------------------------

echo
echo "exec argument parsing:"
"$PST" exec FOO bash -c 'echo hi' >/dev/null 2>&1
assert "exec without -- separator is rejected" test "$?" -ne 0

"$PST" exec FOO -- >/dev/null 2>&1
assert "exec with -- but no command is rejected" test "$?" -ne 0

# ----- get on missing name fails cleanly ----------------------------------

echo
echo "missing-name handling:"
"$PST" get NOPE_NOT_THERE >/dev/null 2>&1
assert "get on missing name returns non-zero" test "$?" -ne 0

# ----- auto-trim semantics (applied to BOTH `pst set` via stdin and `pst paste`)

echo
echo "auto-trim contract:"

# Trailing newline (most common clipboard issue)
printf 'abc123\n' | "$PST" set TRIM_TRAILING_NEWLINE >/dev/null
VAL=$("$PST" get TRIM_TRAILING_NEWLINE 2>/dev/null)
assert "set: trailing newline is trimmed" test "$VAL" = "abc123"
unset VAL

# Trailing space
printf 'abc123 ' | "$PST" set TRIM_TRAILING_SPACE >/dev/null
VAL=$("$PST" get TRIM_TRAILING_SPACE 2>/dev/null)
assert "set: trailing space is trimmed" test "$VAL" = "abc123"
unset VAL

# Leading space (less common but worth being symmetric)
printf '  abc123' | "$PST" set TRIM_LEADING_SPACE >/dev/null
VAL=$("$PST" get TRIM_LEADING_SPACE 2>/dev/null)
assert "set: leading whitespace is trimmed" test "$VAL" = "abc123"
unset VAL

# Both sides
printf '  abc123  \n' | "$PST" set TRIM_BOTH >/dev/null
VAL=$("$PST" get TRIM_BOTH 2>/dev/null)
assert "set: leading + trailing whitespace is trimmed" test "$VAL" = "abc123"
unset VAL

# IMPORTANT: internal whitespace is preserved (some secrets legitimately have spaces — passphrases, etc)
printf 'foo bar baz' | "$PST" set TRIM_INTERNAL >/dev/null
VAL=$("$PST" get TRIM_INTERNAL 2>/dev/null)
assert "set: internal whitespace is preserved" test "$VAL" = "foo bar baz"
unset VAL

# If the entire value is whitespace, treat as empty input (reject)
printf '   \n  \t  ' | "$PST" set TRIM_ONLY_WS >/dev/null 2>&1
assert "set: whitespace-only value is rejected after trim" test "$?" -ne 0

# Auto-trim applies to pst paste as well — set up clipboard with trailing newline
printf 'abc123\n' | pbcopy
"$PST" paste TRIM_TRAILING_NEWLINE >/dev/null 2>&1
VAL=$("$PST" get TRIM_TRAILING_NEWLINE 2>/dev/null)
assert "paste: trailing newline is trimmed from pasteboard contents" test "$VAL" = "abc123"
unset VAL

# ----- pst paste (pasteboard intake — for agent harnesses w/o TTY) --------

echo
echo "paste contract (uses macOS pasteboard):"

# Setup: put a known value on the pasteboard
printf 'paste-secret-from-clipboard' | pbcopy

"$PST" paste PASTE_TEST >/dev/null 2>&1
assert "paste stores pasteboard contents under <NAME>" test "$?" -eq 0

PASTED=$("$PST" get PASTE_TEST 2>/dev/null)
assert "stored value matches what was on clipboard" test "$PASTED" = "paste-secret-from-clipboard"
unset PASTED

# After paste, the pasteboard MUST be cleared (so the next thing that reads
# the clipboard doesn't see the secret)
CLIPBOARD_AFTER=$(pbpaste)
assert "paste clears the pasteboard afterward" test -z "$CLIPBOARD_AFTER"
unset CLIPBOARD_AFTER

# Reject if clipboard is empty (don't silently store empty values)
pbcopy </dev/null
"$PST" paste PASTE_TEST >/dev/null 2>&1
assert "paste with empty clipboard returns non-zero" test "$?" -ne 0

# Reject invalid names like other commands
printf 'whatever' | pbcopy
"$PST" paste "bad name" >/dev/null 2>&1
assert "paste rejects invalid names" test "$?" -ne 0

# Usage when no arg
"$PST" paste >/dev/null 2>&1
assert "paste with no arg returns non-zero" test "$?" -ne 0

# ----- pst probe (safe diagnostic — guaranteed never to leak content) -----

echo
echo "probe contract (length + public prefix only — NEVER value content):"

# Setup: store secrets with known shapes
echo "rnd_aaaaaaaaaaaaaaaaaaaaaaaaaaaa" | "$PST" set PROBE_RND >/dev/null
echo "sk-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" | "$PST" set PROBE_OPENAI >/dev/null
echo "totally-random-not-a-known-shape-xxxx" | "$PST" set PROBE_RAW >/dev/null

# Length should always be reported
OUT=$("$PST" probe PROBE_RND 2>&1)
assert "probe reports length" str_contains "$OUT" "length"
assert "probe reports correct length=32" str_contains "$OUT" "32"

# Known public prefixes should be detected and reported
OUT=$("$PST" probe PROBE_RND 2>&1)
assert "probe identifies rnd_ as a Render token prefix" str_contains "$OUT" "Render"

OUT=$("$PST" probe PROBE_OPENAI 2>&1)
assert "probe identifies sk- as OpenAI-style" str_contains "$OUT" "OpenAI"

# CRITICAL: probe must NEVER print the actual content beyond the known public prefix
OUT=$("$PST" probe PROBE_RND 2>&1)
assert "probe does NOT leak suffix chars" str_NOT_contains "$OUT" "aaaaaaaa"
assert "probe does NOT leak middle chars" str_NOT_contains "$OUT" "aaaa"

OUT=$("$PST" probe PROBE_OPENAI 2>&1)
assert "probe does NOT leak any 'b' chars" str_NOT_contains "$OUT" "bbbb"

OUT=$("$PST" probe PROBE_RAW 2>&1)
assert "probe with unknown shape does NOT leak any value chars" str_NOT_contains "$OUT" "totally"
assert "probe with unknown shape does NOT leak suffix" str_NOT_contains "$OUT" "xxxx"

# probe on missing name
"$PST" probe NOPE_NOT_THERE >/dev/null 2>&1
assert "probe on missing name returns non-zero" test "$?" -ne 0

# probe with no arg
"$PST" probe >/dev/null 2>&1
assert "probe with no arg returns non-zero" test "$?" -ne 0

# probe validates names
"$PST" probe "bad name" >/dev/null 2>&1
assert "probe rejects invalid names" test "$?" -ne 0

# ----- pst exists ---------------------------------------------------------

echo
echo "exists contract:"
echo "present-value" | "$PST" set EXISTS_PRESENT >/dev/null

# Exit code semantics
"$PST" exists EXISTS_PRESENT >/dev/null 2>&1
assert "exists on a stored name returns exit 0" test "$?" -eq 0

"$PST" exists EXISTS_NOT_THERE >/dev/null 2>&1
assert "exists on a missing name returns exit 1" test "$?" -eq 1

# Crucially, exists must NOT leak the value to stdout or stderr
EXISTS_OUT=$("$PST" exists EXISTS_PRESENT 2>&1 || true)
assert "exists does NOT write the value to stdout/stderr" str_NOT_contains "$EXISTS_OUT" "present-value"
assert "exists writes nothing on stdout/stderr for present names" test -z "$EXISTS_OUT"

# Validates name like other commands
"$PST" exists "bad name" >/dev/null 2>&1
assert "exists rejects invalid names" test "$?" -ne 0

# Usage when no arg
"$PST" exists >/dev/null 2>&1
assert "exists with no arg returns non-zero" test "$?" -ne 0

# ----- version + help work ------------------------------------------------

echo
echo "meta:"
OUT=$("$PST" version)
assert "version prints something with 'pst '" str_contains "$OUT" "pst "
OUT=$("$PST" help)
assert "help mentions USAGE" str_contains "$OUT" "USAGE"

# ----- summary ------------------------------------------------------------

echo
echo "────────────────────────────────────"
printf "  passed: %d\n" "$PASS"
printf "  failed: %d\n" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo
  echo "  failed assertions:"
  for e in "${ERRORS[@]}"; do echo "    - $e"; done
  exit 1
fi
echo "  ✨ all green"
