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
