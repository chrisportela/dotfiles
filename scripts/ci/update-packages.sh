#!/usr/bin/env bash
# Run every package's passthru.updateScript, verify each changed package
# still builds, and push a single batched chore/package-updates-<timestamp>
# branch. Packages whose verify build fails are rolled back and reported in
# the PR body instead of committed.
#
# CI-safe re-implementation of pkgs/update.nix, which is written for
# interactive use and does two things a bot must not do: `git add -A`
# (stages the entire tree) and `--impure` eval (builtins.currentSystem).
# Staging here is scoped to pkgs/ — the update scripts only ever modify
# their own package directory (vendored files included, e.g. opencode's
# node_modules.nix / hashes.json and claude-session's SKILL.md).
#
# Each verified package is committed to the work branch immediately, so a
# later package's rollback (checkout + clean of pkgs/) can never destroy an
# earlier package's verified changes.
#
# Writes step outputs to $GITHUB_OUTPUT:
#   changed    "true"  if the branch was pushed (gate for the PR step)
#   title      Conventional-commit PR title
#   body_file  Path to a markdown file with the full PR body
#   branch     Name of the pushed branch
#
# Required env (auto-provided under Forgejo Actions):
#   GITHUB_OUTPUT   writable file for step output key=value pairs
#
# Optional env:
#   DRY_RUN       "true" → run updates and print the summary, then discard
#   GH_API_TOKEN  GitHub API token for update scripts that hit
#                 api.github.com (avoids anonymous rate limits)

set -euo pipefail

DRY_RUN="${DRY_RUN:-false}"
SYSTEM="x86_64-linux"

echo "==> Toolchain:"
echo "    $(nix --version) ($(command -v nix))"
echo "    $(git --version) ($(command -v git))"
echo "    CI=${CI:-<unset>}"

if [ -n "${GH_API_TOKEN:-}" ]; then
  export GITHUB_TOKEN="$GH_API_TOKEN"
  echo "    GITHUB_TOKEN=<from GH_API_TOKEN>"
fi

write_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1" >> "$GITHUB_OUTPUT"
  fi
  echo "output: $1"
}

# Discard any uncommitted pkgs/ changes (staged, unstaged, and untracked).
rollback_pkgs() {
  git reset -q -- pkgs/ || true
  git checkout -q -- pkgs/ 2>/dev/null || true
  git clean -qfd pkgs/ || true
}

if [ -n "$(git status --porcelain pkgs/)" ]; then
  echo "ERROR: pkgs/ is dirty before starting; refusing to run." >&2
  exit 1
fi

# All verified updates are committed incrementally onto this branch.
stamp=$(date -u +%Y%m%d-%H%M%S)
branch="chore/package-updates-${stamp}"
base_ref=$(git rev-parse HEAD)
git switch -C "$branch"

# ── Discover and update packages with an updateScript ────────────────────────

mapfile -t all_pkgs < <(
  nix eval --json --no-warn-dirty ".#packages.$SYSTEM" \
    --apply 'pkgs: builtins.attrNames pkgs' | jq -r '.[]'
)

updated=()   # "name<TAB>old<TAB>new" for the PR body
failed=()    # "name<TAB>reason"
warnings_file=$(mktemp)

for pkg in "${all_pkgs[@]}"; do
  script_json=$(nix eval --json --no-warn-dirty \
    ".#packages.$SYSTEM.$pkg.passthru.updateScript" 2>/dev/null) || continue

  echo ""
  echo "==> Updating $pkg"

  old_version=$(nix eval --raw --no-warn-dirty ".#packages.$SYSTEM.$pkg.version" 2>/dev/null || echo "?")

  # updateScript can be a string (store path) or a list (command + args).
  # The store copy isn't executable — copy to a tempfile like pkgs/update.nix.
  script_type=$(echo "$script_json" | jq -r 'type')
  cmd_args=()
  if [ "$script_type" = "array" ]; then
    mapfile -t cmd_args < <(echo "$script_json" | jq -r '.[]')
  else
    cmd_args=("$(echo "$script_json" | jq -r '.')")
  fi
  # Nix ≥ 2.35 lazy trees: eval returns /nix/store/*-source/... paths
  # without materializing them in the store, so the path may not exist —
  # especially after this loop's own commits create a tree state nothing
  # has built yet. The script is in the checkout anyway; map it back.
  script_src="${cmd_args[0]}"
  if [ ! -e "$script_src" ]; then
    case "$script_src" in
      /nix/store/*-source/*)
        script_src="$PWD/${script_src#/nix/store/*-source/}"
        ;;
    esac
  fi
  if [ ! -e "$script_src" ]; then
    echo "==> WARNING: update script for $pkg not found at ${cmd_args[0]}; skipping." >&2
    failed+=("$pkg"$'\t'"update script path missing")
    continue
  fi
  tmp=$(mktemp)
  cp "$script_src" "$tmp"
  chmod +x "$tmp"
  cmd_args[0]="$tmp"

  update_log=$(mktemp)
  if ! UPDATE_NIX_ATTR_PATH="$pkg" UPDATE_NIX_PNAME="$pkg" \
      "${cmd_args[@]}" 2>&1 | tee "$update_log"; then
    echo "==> WARNING: update script for $pkg exited non-zero; rolling back." >&2
    failed+=("$pkg"$'\t'"update script failed")
    rollback_pkgs
    rm -f "$tmp" "$update_log"
    continue
  fi
  rm -f "$tmp"

  # Some update scripts (opencode) warn on stdout without failing when
  # vendored files drift from upstream — surface those in the PR body.
  grep -i "warn" "$update_log" | sed "s/^/- \`$pkg\`: /" >> "$warnings_file" || true
  rm -f "$update_log"

  if [ -z "$(git status --porcelain pkgs/)" ]; then
    echo "==> $pkg: no changes."
    continue
  fi

  # Stage before building — flake eval can't see unstaged new files.
  git add pkgs/

  echo "==> Verifying $pkg builds..."
  if nix build --no-link --no-warn-dirty ".#packages.$SYSTEM.$pkg"; then
    new_version=$(nix eval --raw --no-warn-dirty ".#packages.$SYSTEM.$pkg.version" 2>/dev/null || echo "?")
    echo "==> $pkg: ${old_version} → ${new_version} (verified)"
    updated+=("$pkg"$'\t'"$old_version"$'\t'"$new_version")
    git commit -q -m "chore(pkgs): update ${pkg} ${old_version} → ${new_version}"
  else
    echo "==> ERROR: $pkg build failed after update; rolling back its changes." >&2
    failed+=("$pkg"$'\t'"build failed after update")
    rollback_pkgs
    continue
  fi
done

# ── Summarize ────────────────────────────────────────────────────────────────

echo ""
echo "==> Updated: ${#updated[@]}  failed: ${#failed[@]}"

if [ "${#updated[@]}" -eq 0 ]; then
  echo "==> No package updates. No PR needed."
  rm -f "$warnings_file"
  write_output "changed=false"
  exit 0
fi

if [ "${#updated[@]}" -eq 1 ]; then
  title="chore(pkgs): update ${updated[0]%%$'\t'*}"
else
  title="chore(pkgs): update ${#updated[@]} packages"
fi

body_file="/tmp/update-packages-body.md"
{
  echo "## Package updates"
  echo ""
  for row in "${updated[@]}"; do
    IFS=$'\t' read -r name old new <<< "$row"
    echo "- **${name}**: ${old} → ${new}"
  done
  if [ "${#failed[@]}" -gt 0 ]; then
    echo ""
    echo "### Skipped (rolled back — needs manual attention)"
    echo ""
    for row in "${failed[@]}"; do
      IFS=$'\t' read -r name reason <<< "$row"
      echo "- **${name}**: ${reason}"
    done
  fi
  if [ -s "$warnings_file" ]; then
    echo ""
    echo "### Warnings from update scripts"
    echo ""
    cat "$warnings_file"
  fi
  echo ""
  echo "---"
  echo "_Generated by \`update-packages\` workflow · $(date -u '+%Y-%m-%d')_"
} > "$body_file"

cat "$body_file"
rm -f "$warnings_file"

write_output "title=${title}"
write_output "body_file=${body_file}"

if [ "$DRY_RUN" = "true" ]; then
  echo "==> Dry run — resetting to ${base_ref}, skipping push."
  git reset -q --hard "$base_ref"
  write_output "changed=false"
  exit 0
fi

echo "==> Pushing ${branch}..."
git push origin "$branch"

echo "==> Branch pushed."
write_output "branch=${branch}"
write_output "changed=true"
