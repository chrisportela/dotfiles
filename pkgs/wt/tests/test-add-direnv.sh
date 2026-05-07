#!/usr/bin/env bash
# Integration test for wt's direnv auto-allow helpers.
# Builds a fake worktree tree with .envrcs at multiple depths and asserts
# both helpers behave correctly. Stubs `direnv` via PATH so the test
# does not depend on the real binary.

set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Re-declare the helpers here so this test runs standalone without
# needing to parse bash out of a Nix string. Keep in sync with
# pkgs/wt/default.nix. Note: the "$p" quoting in `${f#"$p"/}` is
# required by writeShellApplication's shellcheck step (SC2295);
# plain $p without quotes works identically for our paths but
# fails the build.

wt_find_envrcs() {
  local p="$1"
  find "$p" -name .envrc -not -path '*/.git/*' 2>/dev/null | sort | while IFS= read -r f; do
    printf '%s\n' "${f#"$p"/}"
  done
}

wt_allow_envrcs() {
  local p="$1" rel
  while IFS= read -r rel; do
    [ -z "$rel" ] && continue
    direnv allow "$p/$rel"
    echo "  allowed: $rel"
  done < <(wt_find_envrcs "$p")
}

tmp=$(mktemp -d)
stubdir=$(mktemp -d)
trap 'rm -rf "$tmp" "$stubdir"' EXIT

# Build a fake worktree mirroring the mlsa nested-envrc shape:
#   wt/.envrc
#   wt/infra/.envrc
#   wt/src/.envrc
mkdir -p "$tmp/wt/infra" "$tmp/wt/src"
echo 'use flake'             > "$tmp/wt/.envrc"
echo 'use flake ..#infra'    > "$tmp/wt/infra/.envrc"
echo 'source_up; layout node' > "$tmp/wt/src/.envrc"

# Test 1: wt_find_envrcs lists root + nested in sorted relative-path form.
expected=".envrc
infra/.envrc
src/.envrc"
actual=$(wt_find_envrcs "$tmp/wt")
[ "$actual" = "$expected" ] || fail "find_envrcs output: got '$actual' want '$expected'"
pass "wt_find_envrcs lists root + nested .envrcs as sorted relative paths"

# Test 2: wt_find_envrcs excludes .git/ subtree.
mkdir -p "$tmp/wt2/.git"
echo 'should-not-find' > "$tmp/wt2/.git/.envrc"
echo 'ok'              > "$tmp/wt2/.envrc"
actual=$(wt_find_envrcs "$tmp/wt2")
[ "$actual" = ".envrc" ] || fail "find_envrcs included .git/ entry: '$actual'"
pass "wt_find_envrcs excludes .git/ subtree"

# Test 3: wt_find_envrcs returns empty string when no .envrcs.
mkdir -p "$tmp/wt3"
actual=$(wt_find_envrcs "$tmp/wt3")
[ -z "$actual" ] || fail "find_envrcs on empty tree returned: '$actual'"
pass "wt_find_envrcs returns empty when no .envrcs"

# Test 4: wt_allow_envrcs calls a stubbed direnv with each absolute path.
cat > "$stubdir/direnv" <<EOF
#!/usr/bin/env bash
echo "DIRENV_CALLED \$*" >> "\$DIRENV_LOG"
EOF
chmod +x "$stubdir/direnv"

DIRENV_LOG="$tmp/direnv.log"
: > "$DIRENV_LOG"
out_file="$tmp/allow-out"
PATH="$stubdir:$PATH" DIRENV_LOG="$DIRENV_LOG" \
  wt_allow_envrcs "$tmp/wt" > "$out_file" 2>&1

grep -qxF "DIRENV_CALLED allow $tmp/wt/.envrc"        "$DIRENV_LOG" || fail "direnv not called for root .envrc"
grep -qxF "DIRENV_CALLED allow $tmp/wt/infra/.envrc"  "$DIRENV_LOG" || fail "direnv not called for infra/.envrc"
grep -qxF "DIRENV_CALLED allow $tmp/wt/src/.envrc"    "$DIRENV_LOG" || fail "direnv not called for src/.envrc"
[ "$(wc -l < "$DIRENV_LOG")" -eq 3 ] || fail "expected 3 direnv calls, got $(wc -l < "$DIRENV_LOG")"
pass "wt_allow_envrcs invokes direnv allow once per .envrc"

# Test 5: wt_allow_envrcs prints relative paths for each allowed file.
grep -qxF "  allowed: .envrc"        "$out_file" || fail "output missing 'allowed: .envrc'"
grep -qxF "  allowed: infra/.envrc"  "$out_file" || fail "output missing 'allowed: infra/.envrc'"
grep -qxF "  allowed: src/.envrc"    "$out_file" || fail "output missing 'allowed: src/.envrc'"
pass "wt_allow_envrcs prints relative paths for each allowed file"

echo "All direnv auto-allow checks passed."
