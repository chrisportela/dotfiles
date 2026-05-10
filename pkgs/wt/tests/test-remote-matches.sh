#!/usr/bin/env bash
# Integration test for wt's wt_remote_matches helper.
# Builds a real repo with two remotes and verifies the helper's output for
# branches present on one, both, and neither remote.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Re-declare the helper here so this test runs standalone without
# needing to parse bash out of a Nix string. Keep in sync with
# pkgs/wt/default.nix.
wt_remote_matches() {
  git for-each-ref --format='%(refname:lstrip=2)' "refs/remotes/*/$1" 2>/dev/null
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Two bare "remotes" + a working clone with both as remotes.
git init --quiet --bare "$tmp/origin.git"
git init --quiet --bare "$tmp/upstream.git"
git clone --quiet "$tmp/origin.git" "$tmp/repo"
cd "$tmp/repo"
git config user.email test@example.com
git config user.name test
git remote add upstream "$tmp/upstream.git"

# Initial commit on main; push to both remotes so each has a real history.
echo hi > README
git add README
git commit --quiet -m init
git push --quiet -u origin HEAD:main
git push --quiet upstream HEAD:main

# Branch present on origin only.
git checkout --quiet -b origin-only
echo a > a; git add a; git commit --quiet -m a
git push --quiet origin origin-only
git checkout --quiet main
git branch --quiet -D origin-only

# Branch present on both origin and upstream.
git checkout --quiet -b shared
echo b > b; git add b; git commit --quiet -m b
git push --quiet origin shared
git push --quiet upstream shared
git checkout --quiet main
git branch --quiet -D shared

# Refresh remote-tracking refs so refs/remotes/*/<name> exists.
git fetch --quiet --all

# Test 1: branch on origin only → exactly one match.
actual=$(wt_remote_matches origin-only)
[ "$actual" = "origin/origin-only" ] || fail "origin-only: got '$actual' want 'origin/origin-only'"
pass "wt_remote_matches: single remote returns one short ref"

# Test 2: branch on both remotes → two matches (sorted for determinism).
actual=$(wt_remote_matches shared | sort)
expected="origin/shared
upstream/shared"
[ "$actual" = "$expected" ] || fail "shared: got '$actual' want '$expected'"
pass "wt_remote_matches: multi-remote returns one short ref per remote"

# Test 3: branch nowhere → empty output.
actual=$(wt_remote_matches does-not-exist)
[ -z "$actual" ] || fail "does-not-exist: got '$actual' want empty"
pass "wt_remote_matches: nonexistent branch returns empty"

echo "All wt_remote_matches checks passed."
