#!/usr/bin/env bash
# Smoke tests for claude-sandbox-init.
# Prereq: `make build` so the claude-sandbox docker image exists.
# Usage: ./test-init.sh   (or: make test)

set -uo pipefail

REPO="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
SCRIPT="$REPO/claude-sandbox-init"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1${2:+ -- $2}"; FAIL=$((FAIL+1)); }

assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3" "expected '$2', got '$1'"; fi
}
assert_file_exists() {
  if [ -e "$1" ]; then pass "$2"; else fail "$2" "missing: $1"; fi
}
assert_contains_text() {
  if grep -qF "$2" "$1"; then pass "$3"; else fail "$3" "expected '$2' in $1"; fi
}
count_occurrences() {
  grep -cF "$1" "$2" 2>/dev/null
}

if ! docker image inspect claude-sandbox >/dev/null 2>&1; then
  echo "claude-sandbox image not built. Run 'make build' first." >&2
  exit 2
fi

echo "Test 1: idempotent re-run on a fresh dir"
T1=$(mktemp -d)
( cd "$T1" && "$SCRIPT" . >/dev/null && "$SCRIPT" . >/dev/null )
assert_file_exists "$T1/Makefile" "Makefile created"
assert_file_exists "$T1/claude-sandbox.mk" "claude-sandbox.mk created"
assert_file_exists "$T1/claude-sandbox-compose.yml" "claude-sandbox-compose.yml created"
assert_file_exists "$T1/claude" "claude/ created"
assert_file_exists "$T1/commandhistory" "commandhistory/ created"
n=$(count_occurrences "### BEGIN claude-sandbox ###" "$T1/Makefile")
assert_eq "$n" "1" "exactly one BEGIN marker after two runs"
rm -rf "$T1"

echo ""
echo "Test 2: append into existing project Makefile"
T2=$(mktemp -d)
printf '%s\n' 'all: build' '' 'build:' '	@echo building' > "$T2/Makefile"
( cd "$T2" && "$SCRIPT" . >/dev/null )
assert_eq "$(head -1 "$T2/Makefile")" "all: build" "original content remains first"
assert_contains_text "$T2/Makefile" "include claude-sandbox.mk" "include line appended"
( cd "$T2" && "$SCRIPT" . >/dev/null )
n=$(count_occurrences "### BEGIN claude-sandbox ###" "$T2/Makefile")
assert_eq "$n" "1" "no duplicate block on re-run"
rm -rf "$T2"

echo ""
echo "Test 3: invalid CLAUDE_SANDBOX_HOME -> actionable error"
T3=$(mktemp -d)
output=$(cd "$T3" && CLAUDE_SANDBOX_HOME=/nonexistent-claude-sandbox "$SCRIPT" . 2>&1)
rc=$?
assert_eq "$rc" "1" "exits 1 on bad CLAUDE_SANDBOX_HOME"
if grep -qF "/nonexistent-claude-sandbox" <<<"$output"; then
  pass "error message names the bad path"
else
  fail "error message names the bad path" "output was: $output"
fi
rm -rf "$T3"

echo ""
echo "Test 4: resolution via symlink (no env var)"
T4=$(mktemp -d)
ln -s "$SCRIPT" "$T4/init-symlink"
( cd "$T4" && unset CLAUDE_SANDBOX_HOME && "$T4/init-symlink" . >/dev/null )
assert_file_exists "$T4/claude-sandbox.mk" "symlinked invocation generated files"
rm -rf "$T4"

echo ""
echo "Test 5: claude/ and commandhistory/ contents are preserved across re-run"
T5=$(mktemp -d)
( cd "$T5" && "$SCRIPT" . >/dev/null )
echo "sentinel" > "$T5/claude/marker.txt"
echo "sentinel" > "$T5/commandhistory/marker.txt"
( cd "$T5" && "$SCRIPT" . >/dev/null )
assert_file_exists "$T5/claude/marker.txt" "claude/marker.txt survived re-run"
assert_file_exists "$T5/commandhistory/marker.txt" "commandhistory/marker.txt survived re-run"
rm -rf "$T5"

echo ""
echo "Test 6: image-existence check is wired into the run targets"
T6=$(mktemp -d)
( cd "$T6" && "$SCRIPT" . >/dev/null )
assert_contains_text "$T6/claude-sandbox.mk" "SANDBOX_REPO :=" "SANDBOX_REPO is defined"
assert_contains_text "$T6/claude-sandbox.mk" "_sandbox-check-image:" "_sandbox-check-image target exists"
if grep -qE '^sandbox-run:.*_sandbox-check-image' "$T6/claude-sandbox.mk"; then
  pass "sandbox-run depends on _sandbox-check-image"
else
  fail "sandbox-run depends on _sandbox-check-image"
fi
if grep -qE '^sandbox-run-research:.*_sandbox-check-image' "$T6/claude-sandbox.mk"; then
  pass "sandbox-run-research depends on _sandbox-check-image"
else
  fail "sandbox-run-research depends on _sandbox-check-image"
fi
repo=$(grep -m1 '^SANDBOX_REPO :=' "$T6/claude-sandbox.mk" | sed 's/^SANDBOX_REPO := //')
if [ -d "$repo" ] && [ -f "$repo/Dockerfile" ]; then
  pass "SANDBOX_REPO points to a valid claude-sandbox repo"
else
  fail "SANDBOX_REPO points to a valid claude-sandbox repo" "got: $repo"
fi
if ( cd "$T6" && make _sandbox-check-image >/dev/null 2>&1 ); then
  pass "_sandbox-check-image succeeds when image is present"
else
  fail "_sandbox-check-image succeeds when image is present"
fi
rm -rf "$T6"

echo ""
echo "==================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "==================="
[ "$FAIL" -eq 0 ]
