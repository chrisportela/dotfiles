#!/usr/bin/env bash
# Open a fresh update PR, schedule auto-merge, then close any older open
# update PRs with the same branch prefix with a "Superseded by #N" comment.
#
# Shared by the update-flake and update-packages workflows: each updater
# script creates a unique timestamped branch under its own prefix, so this
# script always creates a new PR (never updates an existing one). After
# enabling auto-merge on the new PR it looks for any other open PRs whose
# head branch starts with UPDATE_BRANCH_PREFIX and supersedes them: post a
# comment, close the PR, delete the branch. This keeps exactly one open
# update PR per prefix at a time.
#
# Adapted from cafecito-extensions scripts/ci/create-update-pr.sh, with the
# branch prefix parameterized so the two bots don't close each other's PRs.
#
# Required env:
#   FORGEJO_TOKEN         bot PAT with repository write and PR write scopes
#   PR_TITLE              title for the pull request
#   PR_BODY_FILE          path to a file containing the PR body (markdown)
#   UPDATE_BRANCH         head branch (e.g. chore/flake-update-20260824-060000)
#   UPDATE_BRANCH_PREFIX  prefix identifying this bot's PRs (e.g. chore/flake-update)
#
# Optional env (auto-provided under Forgejo Actions):
#   FORGEJO_API_URL  defaults to "${GITHUB_SERVER_URL}/api/v1"
#   FORGEJO_REPO     defaults to "$GITHUB_REPOSITORY" (owner/repo)
#
# Local usage:
#   UPDATE_BRANCH=chore/flake-update-20260824-060000 \
#   UPDATE_BRANCH_PREFIX=chore/flake-update \
#   PR_TITLE="chore(deps): update nix flake inputs" PR_BODY_FILE=/tmp/body.md \
#   FORGEJO_TOKEN=xxx FORGEJO_REPO=cmp/dotfiles \
#   FORGEJO_API_URL=https://git.cafecito.cloud/api/v1 \
#   scripts/ci/create-update-pr.sh

set -euo pipefail

: "${FORGEJO_TOKEN:?FORGEJO_TOKEN required}"
: "${PR_TITLE:?PR_TITLE required}"
: "${PR_BODY_FILE:?PR_BODY_FILE required}"
: "${UPDATE_BRANCH:?UPDATE_BRANCH required}"
: "${UPDATE_BRANCH_PREFIX:?UPDATE_BRANCH_PREFIX required}"

api="${FORGEJO_API_URL:-${GITHUB_SERVER_URL:?GITHUB_SERVER_URL or FORGEJO_API_URL required}/api/v1}"
repo="${FORGEJO_REPO:-${GITHUB_REPOSITORY:?GITHUB_REPOSITORY or FORGEJO_REPO required}}"

BASE_BRANCH="main"

auth=(-H "Authorization: token ${FORGEJO_TOKEN}")
ct_json=(-H "Content-Type: application/json")

pr_body=$(cat "$PR_BODY_FILE")

# ── 1. Create the PR ──────────────────────────────────────────────────────────

echo "==> Creating PR: ${PR_TITLE} (${UPDATE_BRANCH} → ${BASE_BRANCH})"
create_body=$(jq -nc \
  --arg title "$PR_TITLE" \
  --arg body  "$pr_body" \
  --arg head  "$UPDATE_BRANCH" \
  --arg base  "$BASE_BRANCH" \
  '{title: $title, body: $body, head: $head, base: $base}')
response=$(curl -sS --fail-with-body -X POST \
  "${auth[@]}" "${ct_json[@]}" \
  -d "$create_body" \
  "${api}/repos/${repo}/pulls")
pr_index=$(echo "$response" | jq -r '.number // empty')
if [ -z "$pr_index" ]; then
  printf 'ERROR: failed to create PR. Response: %s\n' "$response" >&2
  exit 1
fi
echo "==> Opened PR #${pr_index}"

# ── 2. Schedule auto-merge when all required checks pass ─────────────────────
#
# Requires branch protection on 'main' with required status checks configured
# (Forgejo repo settings). Without required checks, auto-merge triggers on the
# first passing check rather than waiting for all of them.

echo "==> Enabling auto-merge on PR #${pr_index}..."
merge_json=$(jq -nc '{
  Do: "merge",
  merge_when_checks_succeed: true,
  delete_branch_after_merge: true
}')

http_code=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
  "${auth[@]}" "${ct_json[@]}" \
  -d "$merge_json" \
  "${api}/repos/${repo}/pulls/${pr_index}/merge")

case "$http_code" in
  200|204)
    echo "==> Auto-merge enabled (HTTP ${http_code})"
    ;;
  409)
    # Already scheduled — idempotent re-run, not an error.
    echo "==> Auto-merge already scheduled (HTTP 409)"
    ;;
  405)
    # Merge conditions not met (e.g. conflicts). Auto-merge still queued on some versions.
    echo "==> Auto-merge queued, waiting on merge conditions (HTTP 405)"
    ;;
  *)
    # Don't fail the job — the PR is open and CI is running. Auto-merge can be
    # enabled via the web UI if the API call fails (e.g. unsupported Forgejo version).
    echo "WARNING: unexpected response from merge endpoint (HTTP ${http_code})." >&2
    echo "WARNING: Enable auto-merge manually in the Forgejo UI for PR #${pr_index}." >&2
    ;;
esac

# ── 3. Supersede older update PRs with the same prefix ───────────────────────
#
# Find every other open PR whose head branch starts with UPDATE_BRANCH_PREFIX.
# For each:
#   a) Post a "Superseded by #N" comment.
#   b) Close the PR.
#   c) Delete its head branch.
# All three calls are best-effort (|| true) so a failed cleanup never fails this
# step after the new PR is already open and auto-merge is scheduled.

echo "==> Looking for older update PRs (${UPDATE_BRANCH_PREFIX}*) to supersede..."
open_prs=$(curl -sS "${auth[@]}" \
  "${api}/repos/${repo}/pulls?state=open&type=pulls&limit=50")

# Emit "number<TAB>head.ref" for each candidate, then process line-by-line.
echo "$open_prs" | jq -r \
  --arg prefix "$UPDATE_BRANCH_PREFIX" \
  --arg new "$UPDATE_BRANCH" \
  '.[] | select(.head.ref | startswith($prefix))
       | select(.head.ref != $new)
       | "\(.number)\t\(.head.ref)"' |
while IFS=$'\t' read -r old_num old_ref; do
  [ -z "$old_num" ] && continue
  echo "==> Superseding PR #${old_num} (${old_ref})"

  # a. Post comment
  comment_body=$(jq -nc --arg n "$pr_index" \
    '{body: "Superseded by #\($n) — replaced by a newer update run."}')
  curl -sS "${auth[@]}" "${ct_json[@]}" -X POST -d "$comment_body" \
    "${api}/repos/${repo}/issues/${old_num}/comments" >/dev/null || true

  # b. Close the PR
  curl -sS "${auth[@]}" "${ct_json[@]}" -X PATCH -d '{"state":"closed"}' \
    "${api}/repos/${repo}/pulls/${old_num}" >/dev/null || true

  # c. Delete its head branch. The API route treats the entire value after
  #    /branches/ as the branch name, slashes included — pass it raw.
  curl -sS "${auth[@]}" -X DELETE \
    "${api}/repos/${repo}/branches/${old_ref}" >/dev/null || true

  echo "==> Superseded PR #${old_num}"
done

echo "==> PR #${pr_index} is ready — CI will run and auto-merge when all checks pass."
