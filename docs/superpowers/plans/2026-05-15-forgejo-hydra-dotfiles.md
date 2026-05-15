# Forgejo + Hydra Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Push this `dotfiles` flake to the Forgejo instance on liara, register a declarative Hydra project for it, and expose a `hydraJobs` output covering hosts, packages, dev shells, and home activations so Hydra builds them and post-build-pushes results to both Attic caches.

**Architecture:** Three small file edits in the flake (one new `hydraJobs` output, one new `hydra/spec.nix`, one new `docs/hydra.md` runbook) plus four manual operational steps (verify Hydra→Forgejo SSH, push to Forgejo, create the Hydra project via UI, smoke-check). No changes to substituters, trusted keys, flake inputs, or git remotes — all infra-side wiring already exists for `infra/` and is reused.

**Tech Stack:** Nix flakes, Hydra declarative jobsets, Forgejo (git+ssh on port 2222), the existing `cafecito.hydra` / `cafecito.attic` NixOS modules on liara.

**Spec reference:** `docs/superpowers/specs/2026-05-15-forgejo-hydra-dotfiles-design.md`

---

## File structure

**Create:**
- `hydra/spec.nix` — declarative Hydra jobset spec; emits `spec.json` when nix-built
- `docs/hydra.md` — runbook (bootstrap recipe + day-to-day operations)

**Modify:**
- `flake.nix` — add `hydraJobs` output alongside the existing top-level outputs (`templates`, `overlays`, `nixosModules`, `nixosConfigurations`, `darwinConfigurations`)

**Out of band (manual ops, no file changes):**
- Verify Hydra on liara can SSH-fetch `cmp/dotfiles` from Forgejo (re-uses the wiring already used for `infra/`).
- `git push liara main` from the worktree.
- Create the `cmp-dotfiles` project in the Hydra web UI.
- Trigger a smoke eval and watch builds dispatch + Attic push.

---

## Verification commands used throughout

```bash
# Fast: parses and evaluates the flake without building. Catches syntax / type
# errors. Run after every flake.nix change.
nix flake show --json 2>/dev/null | jq -r 'keys[]'

# Targeted dry-run: evaluates a specific hydraJobs leaf and prints what would
# build / be fetched. Doesn't actually build.
nix build --dry-run --no-link '.#hydraJobs.<group>.<name>.x86_64-linux'

# Build the spec.nix output and inspect the produced JSON. Verifies the
# declarative jobset spec is syntactically valid and matches expectations.
cat "$(nix-build hydra/spec.nix --no-out-link)" | jq .
```

**Reminder:** New files MUST be `git add`-ed before `nix build` / `nix flake show` will see them — flake evaluation excludes untracked files. Each task that creates a file includes a `git add` step before its first verification.

---

### Task 1: Add `hydraJobs` output to `flake.nix`

**Files:**
- Modify: `flake.nix` — insert `hydraJobs` block between `overlays = overlaysSet;` and `nixosModules = ...;` (the `// { ... }` top-level section starting around line 293).

- [ ] **Step 1: Read the insertion site**

```bash
grep -n "^        overlays = overlaysSet;\|^        nixosModules\b" flake.nix
```

Expected: two line numbers, with `overlays` immediately preceding `nixosModules` (with a blank line between them in the current source).

- [ ] **Step 2: Insert the `hydraJobs` block**

Use Edit to insert after `        overlays = overlaysSet;` (and the blank line that follows it), before `        nixosModules = (import ./modules/nixos/default.nix);`:

```nix
        # Jobs Hydra (hydra.cafecito.cloud) walks. Every derivation leaf is a
        # buildable. Restricted to x86_64-linux because the liara build farm
        # only has x86_64-linux builders (ada, lucy). See docs/hydra.md for
        # the bootstrap recipe and day-to-day ops.
        #
        # Shape: hydraJobs.<group>.<name>.${system} = derivation
        hydraJobs =
          let
            sys = "x86_64-linux";
            pkgs = self.packages.${sys};
            legacy = self.legacyPackages.${sys};
          in
          {
            hosts = {
              ada.${sys} = self.nixosConfigurations.ada.config.system.build.toplevel;
              flamme.${sys} = self.nixosConfigurations.flamme.config.system.build.toplevel;
            };

            packages = {
              terraform.${sys} = pkgs.terraform;
              cachix-helper.${sys} = pkgs.cachix-helper;
              attic-helper.${sys} = pkgs.attic-helper;
              rmlint.${sys} = pkgs.rmlint;
              openclaw.${sys} = pkgs.openclaw;
              opencode-cursor.${sys} = pkgs.opencode-cursor;
              claude-code.${sys} = pkgs.claude-code;
              cursor-agent.${sys} = pkgs.cursor-agent;
              opencode.${sys} = pkgs.opencode;
              context7.${sys} = pkgs.context7;
              plane-mcp-server.${sys} = pkgs.plane-mcp-server;
              setup-envrc.${sys} = pkgs.setup-envrc;
              update.${sys} = pkgs.update;
              wt.${sys} = pkgs.wt;
              llmfit.${sys} = pkgs.llmfit;
            };

            devShells = {
              dotfiles.${sys} = self.devShells.${sys}.dotfiles;
              dev.${sys} = self.devShells.${sys}.dev;
              devops.${sys} = self.devShells.${sys}.devops;
              react-native.${sys} = self.devShells.${sys}.react-native;
            };

            # `@` is not permitted in Hydra job names. Flatten `cmp@ada` →
            # `cmp-at-ada` at the boundary; legacyPackages.homeConfigurations
            # keeps the original names.
            homeActivations = {
              cmp.${sys} = legacy.homeConfigurations.cmp.activationPackage;
              nixos.${sys} = legacy.homeConfigurations.nixos.activationPackage;
              cmp-at-ada.${sys} = legacy.homeConfigurations."cmp@ada".activationPackage;
              cmp-at-flamme.${sys} = legacy.homeConfigurations."cmp@flamme".activationPackage;
              deck-at-steamdeck.${sys} = legacy.homeConfigurations."deck@steamdeck".activationPackage;
            };
          };

```

- [ ] **Step 3: Confirm `hydraJobs` is now a flake output**

```bash
nix flake show --json 2>/dev/null | jq -r '.hydraJobs | keys[]'
```

Expected output (exact 4 lines, order may vary):

```
devShells
homeActivations
hosts
packages
```

- [ ] **Step 4: Dry-run a sample host job**

```bash
nix build --dry-run --no-link '.#hydraJobs.hosts.ada.x86_64-linux' 2>&1 | tail -5
```

Expected: no errors. Output ends either with `these N derivations will be built:` (with paths) or is empty when the closure is fully cached. No `error:` lines.

- [ ] **Step 5: Dry-run a sample package job**

```bash
nix build --dry-run --no-link '.#hydraJobs.packages.wt.x86_64-linux' 2>&1 | tail -5
```

Expected: success, no `error:` lines.

- [ ] **Step 6: Dry-run a sample home activation**

```bash
nix build --dry-run --no-link '.#hydraJobs.homeActivations.cmp-at-ada.x86_64-linux' 2>&1 | tail -5
```

Expected: success, no `error:` lines.

- [ ] **Step 7: Commit**

```bash
git add flake.nix
git commit -m "feat(flake): expose hydraJobs for Hydra CI

Adds a hydraJobs output covering nixos hosts (ada, flamme), custom
packages, dev shells, and home activations — all x86_64-linux, the
only arch the liara build farm covers. See docs/hydra.md for the
project bootstrap recipe (added in a follow-up commit)."
```

---

### Task 2: Add `hydra/spec.nix`

**Files:**
- Create: `hydra/spec.nix`

- [ ] **Step 1: Create the spec file**

Write `hydra/spec.nix` with this content:

```nix
# Declarative Hydra project spec for cmp/dotfiles.
#
# Hydra evaluates this file (via nix-build) and reads the resulting JSON
# to create / update the project's jobsets. The owning project is
# configured (one-time, via the Hydra UI) with:
#
#   declarative.spec  = "hydra/spec.nix"
#   declarative.type  = "git"
#   declarative.value = "git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git main"
#
# After bootstrap, all jobset changes happen by editing this file and
# pushing to main — Hydra picks up changes on its next evaluation of
# the project's hidden `.jobsets` jobset.
#
# Build manually: `nix-build hydra/spec.nix` → produces a `spec.json`.
let
  pkgs = import <nixpkgs> { };

  flakeUri = "git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git";

  defaults = {
    enabled = 1;
    hidden = false;
    checkinterval = 300; # seconds between evaluations
    schedulingshares = 100;
    enableemail = false;
    emailoverride = "";
    keepnr = 5;
    type = "flake";
  };

  jobsets = {
    main = defaults // {
      description = "cmp dotfiles: hosts + packages + devshells + home activations (main)";
      flake = "${flakeUri}?ref=main";
    };
  };
in
pkgs.writeText "spec.json" (builtins.toJSON jobsets)
```

- [ ] **Step 2: Build the spec**

```bash
git add hydra/spec.nix
nix-build hydra/spec.nix --no-out-link
```

Expected: a `/nix/store/...-spec.json` path is printed. No errors.

- [ ] **Step 3: Inspect the produced JSON**

```bash
cat "$(nix-build hydra/spec.nix --no-out-link)" | jq .
```

Expected output:

```json
{
  "main": {
    "checkinterval": 300,
    "description": "cmp dotfiles: hosts + packages + devshells + home activations (main)",
    "emailoverride": "",
    "enabled": 1,
    "enableemail": false,
    "flake": "git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git?ref=main",
    "hidden": false,
    "keepnr": 5,
    "schedulingshares": 100,
    "type": "flake"
  }
}
```

(Key order may differ — `jq` may sort alphabetically. Values must match.)

- [ ] **Step 4: Commit**

```bash
git add hydra/spec.nix
git commit -m "feat(hydra): add declarative jobset spec

Declares a single 'main' jobset tracking the main branch on Forgejo
(git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git). Pattern
mirrors infra/hydra/spec.nix; jobset changes happen by editing this
file and pushing."
```

---

### Task 3: Add `docs/hydra.md` runbook

**Files:**
- Create: `docs/hydra.md`

- [ ] **Step 1: Create the runbook**

Write `docs/hydra.md` with this content:

```markdown
# Hydra

This dotfiles flake is built by the shared Hydra instance on liara
(<https://hydra.cafecito.cloud>). The Hydra project `cmp-dotfiles` evaluates
this repo's `hydraJobs` (`flake.nix`) every 300 seconds against `main` on
Forgejo (`git.cafecito.cloud/cmp/dotfiles`). Every successful build is
pushed to both Attic caches (`cache.cafecito.cloud` on liara,
`nix.cafecito.cloud` on ciri) via Hydra's system-global `post-build-hook`.

Dashboard: <https://hydra.cafecito.cloud/project/cmp-dotfiles>

## Adding / changing jobsets

Edit `hydra/spec.nix` and push to `main`. Hydra re-evaluates the project's
hidden `.jobsets` jobset on its check interval and reconciles real jobsets
to match the spec.

Sanity-check the spec builds locally:

```sh
nix-build hydra/spec.nix --no-out-link  # prints path to generated spec.json
cat "$(nix-build hydra/spec.nix --no-out-link)" | jq .
```

## Adding / changing the job manifest

Edit `hydraJobs` in `flake.nix` and push. Dry-run a sample target locally first:

```sh
nix build --dry-run --no-link '.#hydraJobs.<group>.<name>.x86_64-linux'
```

The manifest is restricted to `x86_64-linux` — that's the only architecture
the liara build farm covers (`ada` + `lucy`).

## One-time bootstrap

This only happens the first time the project is brought up on Hydra.
Everything afterward is declarative via `spec.nix` + flake `hydraJobs`.

### 1. Push the flake to Forgejo

```sh
git push liara main
```

The `liara` remote (`ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git`)
is configured locally. If `cmp/dotfiles` doesn't yet exist on Forgejo, create
it via the Forgejo UI first or rely on push-create
(`cafecito.git.createRepoOnPushUser`).

### 2. Confirm Hydra can fetch from Forgejo

Hydra runs as user `hydra` on liara. Test the read path it will use:

```sh
ssh liara sudo -u hydra git ls-remote git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git refs/heads/main
```

Expected: a single line with the SHA of `main`. If this fails because the
hydra user can't authenticate, add a deploy key for the `cmp/dotfiles` repo
(public key from `ssh liara sudo -u hydra cat ~/.ssh/id_*.pub`) via the
Forgejo repo settings.

### 3. Create the Hydra project

Log in to <https://hydra.cafecito.cloud> as an admin, then **Admin → Create
project**:

- **Identifier:** `cmp-dotfiles`
- **Display name:** `cmp dotfiles`
- **Enabled:** yes
- **Declarative spec file:** `hydra/spec.nix`
- **Declarative input type:** `Git checkout`
- **Declarative input value:** `git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git main`

Hydra auto-creates the hidden `.jobsets` jobset, evaluates `hydra/spec.nix`,
and materializes the `main` jobset.

### 4. Smoke check

```sh
ssh liara sudo -u hydra hydra-eval-jobset cmp-dotfiles main
ssh liara journalctl -fu hydra-evaluator -u hydra-queue-runner
```

Then visit <https://hydra.cafecito.cloud/jobset/cmp-dotfiles/main>. Confirm
jobs queue, dispatch to ada / lucy, succeed, and the post-build-hook pushes
to both Attic caches.

## Common operations

```sh
# Manually trigger a jobset eval (don't wait for the 300s tick)
ssh liara sudo -u hydra hydra-eval-jobset cmp-dotfiles main

# Tail Hydra logs
ssh liara journalctl -fu hydra-server -u hydra-evaluator -u hydra-queue-runner

# Confirm a built path landed in Attic
attic info liara:main /nix/store/<hash>-<name>
```
```

- [ ] **Step 2: Verify the file renders without errors**

```bash
git add docs/hydra.md
glow docs/hydra.md | head -20
```

Expected: rendered markdown header `Hydra` and intro paragraph appear, no glow errors.

- [ ] **Step 3: Commit**

```bash
git add docs/hydra.md
git commit -m "docs(hydra): add runbook for cmp-dotfiles project

Documents the bootstrap recipe (push to Forgejo, verify Hydra SSH
access, create the Hydra project via UI, smoke check) and day-to-day
ops (manual eval, log tailing, Attic verification). Mirrors the
shape of infra/docs/hydra.md."
```

---

## CHECKPOINT 1 — Code changes complete

At this point the three files are committed on the `forgejo-hydra` branch. Pause before any push or manual op:
- Confirm `git log --oneline main..HEAD` shows three commits (`feat(flake)`, `feat(hydra)`, `docs(hydra)`) plus the prior spec doc commit (`docs(specs)`).
- Confirm `git diff main -- flake.nix hydra docs/hydra.md` matches expectations end-to-end.
- Confirm `nix flake show --json 2>/dev/null | jq '.hydraJobs | keys'` returns the four groups.

Below: manual ops. None of these change files in the repo; they bring the deployed Hydra into the new state.

---

### Task 4: Verify Hydra on liara can fetch `cmp/dotfiles` from Forgejo

**Files:** none.

- [ ] **Step 1: Probe the SSH read path Hydra will use**

```bash
ssh liara sudo -u hydra git ls-remote git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git refs/heads/main 2>&1
```

Three possible outcomes:

1. **One-line SHA output** — Hydra can read the repo. Continue to Task 5.
2. **`fatal: repository ... not found`** — the repo `cmp/dotfiles` doesn't exist on Forgejo yet. This is expected if you haven't pushed. Run Task 5 first, then re-run this check.
3. **`Permission denied (publickey)` or `Could not read from remote repository`** — Hydra's `~/.ssh` doesn't have a key Forgejo accepts. Add a deploy key (next step).

- [ ] **Step 2 (only if step 1 returned `Permission denied`): Add Hydra's pubkey as a deploy key**

```bash
ssh liara sudo -u hydra bash -c 'cat ~/.ssh/id_ed25519.pub 2>/dev/null || cat ~/.ssh/id_*.pub'
```

Copy the public key, then in the Forgejo UI: **`cmp/dotfiles` → Settings → Deploy Keys → Add Key**. Read-only is sufficient. After saving, re-run Step 1; expect a SHA line.

---

### Task 5: Push the flake to Forgejo

**Files:** none (operates on git remote).

- [ ] **Step 1: Confirm the `liara` remote is configured**

```bash
git remote get-url liara
```

Expected: `ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git`. If empty, the remote is missing — add with `git remote add liara ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git` (only happens if working in a checkout that didn't inherit this remote).

- [ ] **Step 2: Push the worktree branch as `main` on Forgejo**

```bash
git push liara HEAD:main
```

If `cmp/dotfiles` doesn't exist on Forgejo yet:
- If push-create-user is enabled on Forgejo, the repo will be created automatically.
- Otherwise the push will fail with `repository ... does not exist`. Create the repo in the Forgejo UI (no description needed, default settings) and re-run.

Expected on success: `* [new branch]      HEAD -> main` (or a fast-forward update line if the branch already existed remotely).

- [ ] **Step 3: Verify the push landed**

```bash
git ls-remote liara refs/heads/main
```

Expected: a single line with the SHA matching local `HEAD`.

---

### Task 6: Create the `cmp-dotfiles` Hydra project (via UI, manual)

**Files:** none.

- [ ] **Step 1: Log in to Hydra as an admin**

Open <https://hydra.cafecito.cloud> in a browser. Log in with an admin account (created previously via `hydra-create-user` per `infra/docs/hydra.md`).

- [ ] **Step 2: Create the project**

Click **Admin → Create project**. Fill in:

| Field | Value |
|---|---|
| Identifier | `cmp-dotfiles` |
| Display name | `cmp dotfiles` |
| Description | (optional) |
| Owner | your admin user |
| Enabled | ✔ |
| Visible | ✔ |
| Declarative spec file | `hydra/spec.nix` |
| Declarative input type | `Git checkout` |
| Declarative input value | `git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git main` |

Click **Create**.

- [ ] **Step 3: Confirm Hydra materialized the `main` jobset**

Visit <https://hydra.cafecito.cloud/project/cmp-dotfiles>. Within ~5 minutes (one `checkinterval`) the hidden `.jobsets` jobset evaluates `hydra/spec.nix`, then the `main` jobset appears in the project view.

To force this without waiting:

```bash
ssh liara sudo -u hydra hydra-eval-jobset cmp-dotfiles .jobsets
```

---

### Task 7: Smoke check — first eval + first build + Attic push

**Files:** none.

- [ ] **Step 1: Trigger an eval of `main`**

```bash
ssh liara sudo -u hydra hydra-eval-jobset cmp-dotfiles main
```

Expected: command returns within a few seconds (eval runs in background). No error output.

- [ ] **Step 2: Tail Hydra logs while builds dispatch**

```bash
ssh liara journalctl -fu hydra-evaluator -u hydra-queue-runner --since="2 min ago"
```

Watch for:
- `evaluator` reading the flake from `git+ssh://...cmp/dotfiles.git`
- `queue-runner` dispatching builds with `building X on ada.gorgon-basilisk.ts.net` (or `lucy.gorgon-basilisk.ts.net:2222`)

Stop with Ctrl-C once builds are visibly running. Don't wait for full completion.

- [ ] **Step 3: Confirm the jobset is alive on the dashboard**

Visit <https://hydra.cafecito.cloud/jobset/cmp-dotfiles/main>. Confirm:
- Eval count ≥ 1
- Jobs listed in the four groups (`hosts.ada.x86_64-linux`, `packages.wt.x86_64-linux`, etc.) — total around 26 jobs

- [ ] **Step 4: Pick one finished build and confirm it pushed to Attic**

Once at least one job reaches `Succeeded` (refresh the jobset page; small jobs like `wt` or `setup-envrc` finish in seconds):

```bash
# From the dashboard, copy a successful job's output store path (under
# "Build products" or via the build details page).
STORE_PATH='/nix/store/...-wt-X.Y.Z'

# Confirm it's in liara's local Attic.
ssh liara attic info liara:main "$STORE_PATH"

# Confirm it's in ciri's B2-backed Attic.
ssh liara attic info ciri:main "$STORE_PATH"
```

Both commands should return cache metadata (not `not found`). If `ciri:main` returns `not found` immediately after a build, give it 30s and retry — the post-build-hook pushes to liara first, then ciri, so there's a small lag.

- [ ] **Step 5: (Optional) Confirm a downstream host can substitute from the cache**

From any host that has `https://cache.cafecito.cloud/main` in its substituters and trusts the `main:` key (e.g. ada):

```bash
nix path-info --json "$STORE_PATH" --store https://cache.cafecito.cloud/main 2>&1 | jq .
```

Expected: a JSON object describing the path (`narHash`, `narSize`, etc.). `error: path '...' is not valid` means the path isn't in that cache yet.

---

## CHECKPOINT 2 — Bootstrap complete

At this point:
- The flake lives at `git.cafecito.cloud/cmp/dotfiles`, branch `main`.
- The Hydra project `cmp-dotfiles` exists, has eval'd at least once, and is building jobs.
- At least one job has succeeded and is present in both Attic caches.

Subsequent changes: push to `main` on Forgejo → Hydra re-evals on the next 300s tick → new derivations build and push to Attic. No further manual steps.

---

## Branch finalization

This work was done on the `forgejo-hydra` branch in a worktree. To integrate:

- If the work should land on `main` locally: `git checkout main && git merge --ff-only forgejo-hydra` (fast-forward, since `main` is at the prior `Updated flake lock` commit and all new commits sit cleanly on top).
- The `git push liara HEAD:main` in Task 5 already published to Forgejo's `main`. If `github` should also get this work, follow up with `git push github main` separately.
- Remove the worktree with `wt rm forgejo-hydra` once merged.
