#!/usr/bin/env bash
# Integration test for wt's upstream_gone() helper.
# Builds a real temp git repo with four branch states and asserts the
# helper's return value for each.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Re-declare the helper here so this test runs standalone without
# needing to parse bash out of a Nix string. Keep in sync with
# pkgs/wt/default.nix.
upstream_gone() {
  local track
  track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$1")
  [[ "$track" == *"[gone]"* ]]
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Bare "remote" + a working clone
git init --quiet --bare "$tmp/remote.git"
git clone --quiet "$tmp/remote.git" "$tmp/repo"
cd "$tmp/repo"
git config user.email test@example.com
git config user.name test

# Initial commit on main
echo hi > README
git add README
git commit --quiet -m init
git push --quiet -u origin HEAD:main

# Case 1: branch with [gone] upstream (was pushed, then remote branch deleted)
git checkout --quiet -b gone-branch
echo x > x; git add x; git commit --quiet -m x
git push --quiet -u origin gone-branch
git push --quiet origin --delete gone-branch
git fetch --quiet --prune

# Case 2: branch with a valid upstream
git checkout --quiet -b alive-branch main
echo y > y; git add y; git commit --quiet -m y
git push --quiet -u origin alive-branch

# Case 3: local-only branch, never pushed
git checkout --quiet -b local-only main

# Case 4: a branch name that does not exist at all
# (upstream_gone on a nonexistent branch returns empty -> non-match -> false)

# Assertions
if upstream_gone gone-branch; then
  pass "gone-branch -> upstream_gone returns 0"
else
  fail "gone-branch should report upstream gone"
fi

if upstream_gone alive-branch; then
  fail "alive-branch should NOT report upstream gone"
else
  pass "alive-branch -> upstream_gone returns non-zero"
fi

if upstream_gone local-only; then
  fail "local-only (never pushed) should NOT report upstream gone"
else
  pass "local-only -> upstream_gone returns non-zero"
fi

if upstream_gone does-not-exist; then
  fail "nonexistent branch should NOT report upstream gone"
else
  pass "does-not-exist -> upstream_gone returns non-zero"
fi

echo "All upstream_gone checks passed."
