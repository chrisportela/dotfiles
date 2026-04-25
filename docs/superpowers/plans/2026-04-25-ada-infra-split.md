# Ada Infra Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip ada's host config and dotfiles modules down to a buildable, recoverable baseline; the private services move to `~/src/infra` (out of scope for this plan).

**Architecture:** Dotfiles keeps `nixosConfigurations.ada` as a recovery baseline. Three modules (`ftp`, `local-llm`, `samba`) move to infra in their entirety. `agent-vms` stays (flamme uses it); only ada's invocation moves. `cafecitocloud` is trimmed to CA-trust only; the ACME defaults move to a new infra module. Each task leaves the build green.

**Tech Stack:** Nix flakes, NixOS modules, agenix, home-manager.

**Spec:** `docs/superpowers/specs/2026-04-24-ada-infra-split-design.md`

**PR-merge precondition (not enforced by this plan):** Don't deploy dotfiles' baseline ada to the real machine before infra's ada is wired up. Note this in the PR description.

---

## File map

**Modified:**
- `hosts/nixos/ada/default.nix` — stripped of all private/dead-code blocks across Tasks 2-8.
- `modules/nixos/default.nix` — drops `ftp` and `local-llm` keys (Tasks 5, 6).
- `modules/nixos/all.nix` — drops `./ftp.nix`, `./local-llm`, `./samba` (Tasks 5, 6, 7).
- `modules/nixos/cafecitocloud/default.nix` — drops `enableACME` option + `security.acme.defaults` block (Task 8).
- `secrets/secrets.nix` — drops `ada-samba-passwords.age` entry + unused let-bindings (Task 7).

**Deleted:**
- `modules/nixos/ftp.nix` (Task 5)
- `modules/nixos/local-llm/` (whole directory) (Task 6)
- `modules/nixos/samba/` (whole directory) (Task 7)
- `secrets/ada-samba-passwords.age` (Task 7)

**Unchanged:**
- `flake.nix`
- `hosts/nixos/ada/hardware.nix`, `hosts/nixos/ada/disko.nix`
- `hosts/nixos/flamme/*`
- `lib/ssh-keys.nix`
- `modules/nixos/agent-vms/`
- `modules/nixos/cafecitocloud/cafecitocloud-root_ca.crt`

---

## Verification primitives

Most tasks end with these two builds. Both must succeed:

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.flamme.config.system.build.toplevel --no-link
```

`--no-link` avoids littering the worktree with `result-*` symlinks. Builds use cache when possible.

If a task only touches `hosts/nixos/ada/default.nix`, only the ada build is strictly required, but verifying flamme too is cheap (cached) and catches accidental regressions.

---

## Task 1: Pre-flight baseline

Confirm the starting state is green so later failures can be attributed to the changes.

**Files:** none

- [ ] **Step 1: Verify ada builds**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
```

Expected: builds successfully (probably from cache), no errors.

- [ ] **Step 2: Verify flamme builds**

```bash
nix build .#nixosConfigurations.flamme.config.system.build.toplevel --no-link
```

Expected: builds successfully.

- [ ] **Step 3: Confirm clean working tree**

```bash
git status
```

Expected: `nothing to commit, working tree clean`. If not, stop and surface what's there.

---

## Task 2: Strip elasticsearch + kibana dead code

These services are already disabled (`enable = false`, `autoStart = false`). They move to infra per spec, but the host-config side is just deletion in dotfiles.

**Files:**
- Modify: `hosts/nixos/ada/default.nix`

- [ ] **Step 1: Remove `services.elasticsearch` block**

Delete lines 176-186 (the whole `services.elasticsearch = { ... };` block plus the `# Elasticsearch (disabled)` comment immediately above it).

Resulting context: the `boot.binfmt.emulatedSystems` block (line 222 area) should now sit closer to whatever was before line 176.

- [ ] **Step 2: Remove the kibana container**

Delete the entire `virtualisation.oci-containers.containers.kibana-test = { ... };` block (lines 188-203).

- [ ] **Step 3: Remove the kibana nginx vhost**

Delete the entire `services.nginx = { ... };` block (lines 205-218) and the `users.users.nginx.extraGroups = [ "acme" ];` line (line 219).

- [ ] **Step 4: Remove `elasticsearch` from `allowedUnfree`**

In the `allowedUnfree` list near the top of the file, remove the `"elasticsearch"` entry.

- [ ] **Step 5: Verify ada builds**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
```

Expected: builds successfully.

- [ ] **Step 6: Commit**

```bash
git add hosts/nixos/ada/default.nix
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor(ada): drop disabled elasticsearch + kibana stack

Moving to infra. The services were already disabled; this just removes the
host-config noise from dotfiles.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Strip `coder-provisioner` user

Tied to the private coder workflow; moves to infra.

**Files:**
- Modify: `hosts/nixos/ada/default.nix`

- [ ] **Step 1: Remove the user and group**

Delete the entire `users.users.coder-provisioner = { ... };` block and the `users.groups.coder-provisioner = { };` line that follows it (near the bottom of the file).

- [ ] **Step 2: Verify ada builds**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
```

Expected: builds successfully.

- [ ] **Step 3: Commit**

```bash
git add hosts/nixos/ada/default.nix
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor(ada): drop coder-provisioner user

Moves with the rest of the private coder workflow to infra.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Strip ada's `agent-vms` invocation

The `modules/nixos/agent-vms/` module stays in dotfiles (flamme uses it). Only ada's invocation block moves to infra.

**Files:**
- Modify: `hosts/nixos/ada/default.nix`

- [ ] **Step 1: Remove the agent-vms block from the `chrisportela` attrset**

In the `chrisportela = { ... };` attrset, remove the `agent-vms = { ... };` block (currently the last entry, ~lines 66-73 in the pre-strip file). Keep the surrounding `network`, `gaming`, `ftp` (will be removed in Task 5), `local-llm` (will be removed in Task 6), `samba` (will be removed in Task 7), and `cafecitocloud` references intact for now.

- [ ] **Step 2: Verify both ada and flamme build**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.flamme.config.system.build.toplevel --no-link
```

Expected: both succeed. Flamme is the critical check here — it confirms the module stayed put.

- [ ] **Step 3: Commit**

```bash
git add hosts/nixos/ada/default.nix
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor(ada): drop agent-vms invocation

The module stays in dotfiles for flamme; ada's invocation moves to infra.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Strip ftp (module + ada usage)

Single host (ada) consumes it, so host invocation and module deletion go in one commit.

**Files:**
- Modify: `hosts/nixos/ada/default.nix`
- Modify: `modules/nixos/default.nix`
- Modify: `modules/nixos/all.nix`
- Delete: `modules/nixos/ftp.nix`

- [ ] **Step 1: Remove the ftp block from ada**

In `hosts/nixos/ada/default.nix`, in the `chrisportela = { ... };` attrset, remove:

```nix
ftp = {
  enable = false;
  directory = "/mnt/tank/photo-dump";
  domain = "ftp.ada.i.cafecito.cloud";
};
```

- [ ] **Step 2: Remove `ftp` key from `modules/nixos/default.nix`**

Delete the line:

```nix
ftp = ./ftp.nix;
```

- [ ] **Step 3: Remove `./ftp.nix` from `modules/nixos/all.nix`**

Delete the line:

```nix
./ftp.nix
```

- [ ] **Step 4: Delete the module file**

```bash
git rm modules/nixos/ftp.nix
```

- [ ] **Step 5: Verify both ada and flamme build**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.flamme.config.system.build.toplevel --no-link
```

Expected: both succeed.

- [ ] **Step 6: Commit**

```bash
git add hosts/nixos/ada/default.nix modules/nixos/default.nix modules/nixos/all.nix
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor(ftp): drop module + ada usage (moves to infra)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Strip ada's `local-llm` invocation and remove the module

Single host (ada) consumes it, so we can delete the host invocation and module in one commit.

**Files:**
- Modify: `hosts/nixos/ada/default.nix`
- Modify: `modules/nixos/default.nix`
- Modify: `modules/nixos/all.nix`
- Delete: `modules/nixos/local-llm/` (whole directory)

- [ ] **Step 1: Remove the local-llm enable line from ada**

In `hosts/nixos/ada/default.nix`, in the `chrisportela = { ... };` attrset, remove:

```nix
local-llm.enable = true;
```

- [ ] **Step 2: Remove `local-llm` key from `modules/nixos/default.nix`**

Delete the line:

```nix
local-llm = ./local-llm;
```

- [ ] **Step 3: Remove `./local-llm` from `modules/nixos/all.nix`**

Delete the line:

```nix
./local-llm
```

- [ ] **Step 4: Delete the module directory**

```bash
git rm -r modules/nixos/local-llm
```

- [ ] **Step 5: Verify both ada and flamme build**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.flamme.config.system.build.toplevel --no-link
```

Expected: both succeed.

- [ ] **Step 6: Commit**

```bash
git add hosts/nixos/ada/default.nix modules/nixos/default.nix modules/nixos/all.nix
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor(local-llm): drop module + ada usage (moves to infra)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Strip samba (module + ada usage + secret)

Largest task — combines the host config strip, module deletion, secret deletion, and `secrets.nix` cleanup. Done as one commit because the host config and the secret are tightly coupled (deleting one without the other leaves a dangling reference).

**Files:**
- Modify: `hosts/nixos/ada/default.nix`
- Modify: `modules/nixos/all.nix`
- Modify: `secrets/secrets.nix`
- Delete: `modules/nixos/samba/` (whole directory)
- Delete: `secrets/ada-samba-passwords.age`

Note: `samba` is **not** in `modules/nixos/default.nix`'s attrset (only in `all.nix`), so no edit is needed there.

- [ ] **Step 1: Remove the samba block from ada**

In `hosts/nixos/ada/default.nix`, in the `chrisportela = { ... };` attrset, remove the entire `samba = { ... };` block (the one with `enable`, `openFirewall`, `users`, `passwordFile`, and the `shares` attrset with `photography`, `home-shared`, `tank-shared`, `tank-public`).

- [ ] **Step 2: Remove the agenix secret reference from ada**

Delete the line:

```nix
age.secrets.ada-samba-passwords.file = ../../../secrets/ada-samba-passwords.age;
```

- [ ] **Step 3: Remove `./samba` from `modules/nixos/all.nix`**

Delete the line:

```nix
./samba
```

- [ ] **Step 4: Delete the samba module directory**

```bash
git rm -r modules/nixos/samba
```

- [ ] **Step 5: Delete the agenix secret file**

```bash
git rm secrets/ada-samba-passwords.age
```

- [ ] **Step 6: Update `secrets/secrets.nix`**

Replace the contents with:

```nix
let
  sshKeys = import ../lib/ssh-keys.nix;
in
{
  "example.age".publicKeys = sshKeys.secrets ++ [ ];
}
```

(Removes the `ada-samba-passwords.age` entry and the now-unused `ada` and `adaHost` let-bindings.)

- [ ] **Step 7: Verify both ada and flamme build**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.flamme.config.system.build.toplevel --no-link
```

Expected: both succeed.

- [ ] **Step 8: Commit**

```bash
git add hosts/nixos/ada/default.nix modules/nixos/all.nix secrets/secrets.nix
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor(samba): drop module + ada usage + secret (moves to infra)

Removes the samba module, ada's invocation (with all four shares), and the
ada-samba-passwords.age secret. Cleans up unused let-bindings in
secrets/secrets.nix.

The infra side will re-encrypt the secret with infra's keyring.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Trim `cafecitocloud` to CA-trust only

The module keeps `security.pki.certificateFiles` (so all hosts trust the CA) and drops the ACME issuance bits (which belong to hosts that serve cert-bearing services — those hosts live in infra now).

**Files:**
- Modify: `hosts/nixos/ada/default.nix`
- Modify: `modules/nixos/cafecitocloud/default.nix`

- [ ] **Step 1: Remove `enableACME = true` from ada**

In `hosts/nixos/ada/default.nix`, replace:

```nix
cafecitocloud = {
  enable = true;
  enableACME = true;
};
```

with:

```nix
cafecitocloud.enable = true;
```

- [ ] **Step 2: Trim the cafecitocloud module**

Replace the contents of `modules/nixos/cafecitocloud/default.nix` with:

```nix
{
  config,
  lib,
  ...
}:
let
  cfg = config.cafecitocloud;
in
{
  options.cafecitocloud = {
    enable = lib.mkEnableOption "Cafecito Cloud root CA trust";
  };

  config = lib.mkIf cfg.enable {
    security.pki.certificateFiles = [ ./cafecitocloud-root_ca.crt ];
  };
}
```

This drops:
- The `pkgs` argument (no longer needed)
- The `with lib;` (replaced with explicit `lib.` prefixes for clarity)
- The `enableACME` option
- The `security.acme = mkIf cfg.enableACME { ... };` block

The `cafecitocloud-root_ca.crt` file in the same directory stays untouched.

- [ ] **Step 3: Verify both ada and flamme build**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.flamme.config.system.build.toplevel --no-link
```

Expected: both succeed. (Flamme uses `cafecitocloud.enable = true` already; this confirms the trimmed module still satisfies it.)

- [ ] **Step 4: Commit**

```bash
git add hosts/nixos/ada/default.nix modules/nixos/cafecitocloud/default.nix
git -c commit.gpgsign=false commit -m "$(cat <<'EOF'
refactor(cafecitocloud): trim to CA trust only

Removes the enableACME option and security.acme.defaults block. The defaults
(server, dnsResolver=liara.gorgon-basilisk.ts.net, email, validMinDays,
renewInterval) move to a new cafecitocloud-acme module on the infra side.
All hosts that need CA trust still flip cafecitocloud.enable = true.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Final verification

Sweeping check across the whole flake to catch anything the per-task verification missed.

**Files:** none

- [ ] **Step 1: Run `nix flake check`**

```bash
nix flake check
```

Expected: passes (no eval errors, no missing files, formatting check passes).

If formatting fails, the next steps handle it.

- [ ] **Step 2: Run `nix fmt`**

```bash
nix fmt
```

Expected: either no changes (formatting already clean from edits) or changes only to files this PR touched. Per CLAUDE.md, if `nix fmt` rewrites unrelated files, **do not include them in this PR** — revert them with `git checkout -- <file>` and address the formatter drift separately.

- [ ] **Step 3: Inspect format diff**

```bash
git diff
```

If nothing: skip to Step 5. Otherwise, confirm only files this PR already touched are affected.

- [ ] **Step 4: Commit the formatting diff (only if scoped to this PR's files)**

```bash
git add -p   # interactively stage only this PR's files if needed
git -c commit.gpgsign=false commit -m "style: nix fmt"
```

- [ ] **Step 5: Final scan of `hosts/nixos/ada/default.nix`**

```bash
grep -nE "samba|ftp|local-llm|coder-provisioner|elasticsearch|kibana|ada-samba-passwords|enableACME" hosts/nixos/ada/default.nix
```

Expected: no matches.

- [ ] **Step 6: Final builds (clean cache hit)**

```bash
nix build .#nixosConfigurations.ada.config.system.build.toplevel --no-link
nix build .#nixosConfigurations.flamme.config.system.build.toplevel --no-link
```

Expected: both succeed.

- [ ] **Step 7: Show the commit log**

```bash
git log --oneline main..HEAD
```

Expected: 7 commits from Tasks 2-8, optionally one more from Step 4 if `nix fmt` produced changes. All on the `make-ada-infra` branch.

---

## Done

The dotfiles side is complete. The infra side is a separate task in a `wt`-created worktree of `~/src/infra` (see spec). PR description should call out the deploy ordering: "First deploy after merge must come from infra, not dotfiles."
