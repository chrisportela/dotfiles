# CI & automation

CI runs on **Forgejo Actions** (`git.cafecito.cloud`, remote `liara`) — the
primary. GitHub is a manually-pushed mirror with a slimmer informational
workflow. The old Hydra jobset (`cmp-dotfiles` on hydra.cafecito.cloud) is
retired; the `hydraJobs` flake output is kept as the machine-readable job
list that `scripts/ci/plan-jobs.sh` derives the CI matrices from.

## Workflows

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `.forgejo/workflows/ci.yml` | every PR to main, push to main | The merge gate. Staged: `check` (flake check `--all-systems`) and `plan` run first; stage 1 builds every package/devShell/home activation as its own matrix job on all three platforms; stage 2 (`hosts`, `hosts-darwin`) assembles the ada/flamme/lux/roxy closures from the warm store; `pi` (rpi4 SD image) rebuilds on main only. |
| `.forgejo/workflows/update-flake.yml` | Mon 06:00 UTC, manual (`dry_run`) | `nix flake update` → PR from `chore/flake-update-<ts>` → auto-merge when all checks pass → supersedes older flake-update PRs. |
| `.forgejo/workflows/update-packages.yml` | Thu 06:00 UTC, manual (`dry_run`) | Runs every `passthru.updateScript`, verifies each changed package builds (failures rolled back + reported), batches into a PR from `chore/package-updates-<ts>` → auto-merge. |
| `.github/workflows/nix.yml` | push main, PRs (GitHub) | Informational: flake check + darwin build pushed to the public cachix (`chrisportela-dotfiles`) for consumers without tailnet access. |

## Runners & platforms

| Platform | Runner | Notes |
| --- | --- | --- |
| x86_64-linux | `lucy-docker` (infra repo) | Docker containers sharing the host `/nix/store` + nix-daemon (`NIX_REMOTE=daemon`). Jobs must run the `.forgejo/actions/setup-nix` local action. Job timeout 3h; if a single leaf ever outgrows it, move that job to `nix-heavy:host` (infra WIP, 8h). |
| aarch64-linux | same | binfmt emulation — the build hosts set `boot.binfmt.emulatedSystems = ["aarch64-linux"]`, so the daemon accepts aarch64 builds. |
| aarch64-darwin | `darwin` → lux (`modules/darwin/forgejo-runner`) | Native launchd runner; if lux is offline, PRs wait for it. |

## Cache (niks3)

No workflow pushes to any cache. The build hosts run a `post-build-hook`
that pushes everything the daemon builds to `https://niks3.cafecito.cloud`:

- linux hosts (liara/lucy/ada): infra repo, `cafecito.nixCachePush` (in
  flight there — until it lands, linux CI still gates merges, the cache just
  fills in later);
- lux: `modules/darwin/nix-cache-push` in this repo.

Retention: every merge to main re-runs the full build set, so the cache
always holds the current closures (`cache-targets` is part of
`hydraJobs.packages` and rebuilds every run). gcroots created inside docker
jobs do not survive (they point at ephemeral container paths), so retention
is entirely niks3-side — **verify in the infra repo that niks3's GC window
comfortably exceeds the weekly update cadence.** The `cachix-helper`
push+pin flow stays for the public cachix cache.

## Server-side setup checklist (not doable from this repo)

1. **Bot PAT**: create/reuse a bot Forgejo account with write access to
   `cmp/dotfiles`; generate a PAT with `write:repository` scope; add it as
   Actions secret `DEPS_BOT_TOKEN`. The built-in `GITHUB_TOKEN` cannot be
   used — Forgejo suppresses workflows for events it creates
   (anti-recursion), so a PR opened with it would never run CI and never
   auto-merge.
2. **Branch protection on `main`**: `enable_push: true` (do not block the
   bots' direct pushes of update branches), no push whitelist,
   `enable_status_check: true` with context pattern `ci / *` (or, if the
   glob doesn't match the matrix-expanded names on the current Forgejo
   version, enumerate `ci / check (pull_request)`,
   `ci / hosts (pull_request)`, `ci / hosts-darwin (pull_request)` — the
   `needs:` edges make those transitively cover stage 1). Without required
   status checks, `merge_when_checks_succeed` fires on the *first* passing
   check.
3. **lux runner secret** (declarative pre-registered runner): generate with
   `openssl rand -hex 20`, register it on liara with
   `forgejo-cli actions register --name lux --secret <secret>` (prints the
   runner UUID), store the secret with `cd secrets && agenix -e
   lux-forgejo-runner-secret.age` (replaces the committed placeholder), and
   set the printed UUID in `hosts/darwin/lux.nix`
   (`chrisportela.forgejo-runner.uuid`, currently a zeros placeholder). No
   registration token involved; the connection is declared in the runner's
   config file.
4. **lux niks3 token**: mint on liara (infra repo), then `agenix -e
   lux-niks3-api-token.age`.
5. **Optional** Actions secret `GH_API_TOKEN` (a GitHub read-only token) so
   package update scripts that hit api.github.com avoid anonymous rate
   limits.
6. **Hydra**: disable/delete the `cmp-dotfiles` project on
   hydra.cafecito.cloud (its spec.json was removed from this repo and it
   was evaluating a stale branch anyway).

## Gotchas encoded in the scripts (don't regress these)

- Bots never run `nix fmt` (formatter drift produces noisy diffs) and never
  regenerate the vendored IFD-workaround files (`pkgs/opencode/*.nix`,
  `pkgs/claude-session/skill/SKILL.md`) — those belong to the package
  update scripts, and a nixpkgs bump that invalidates them is *supposed* to
  fail CI and hold the PR for a human.
- `virby` is rev-pinned in its input URL; `nix flake update` correctly
  leaves it alone.
- New/changed files must be `git add`ed before `nix build` (flake eval
  can't see untracked files) — `update-packages.sh` stages `pkgs/` before
  each verify build.
- `pkgs/update.nix` (the interactive updater) is not CI-safe (`git add -A`,
  `--impure`); CI uses `scripts/ci/update-packages.sh` instead.
- The host `/nix/store` the docker jobs mount is **multi-arch**: successful
  emulated aarch64-linux builds leave aarch64 `nix-*` packages whose store
  path names are identical to the x86_64 ones (only the hash differs). A
  foreign-arch binary runs on the host via binfmt but fails inside a
  container with exec ENOENT ("cannot execute: required file not found")
  because the qemu interpreter path only exists in the host mount
  namespace. `.forgejo/actions/setup-nix` therefore filters candidates by
  ELF machine type and proves the chosen `nix` executes before using it —
  never select a store binary by glob order alone.
