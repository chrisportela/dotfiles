# llmfit Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Nix package wrapping the upstream `AlexsJones/llmfit` v0.9.2 pre-built binaries, exposed as `self.packages.<system>.llmfit`, with a version-gated overlay and a manual update script.

**Architecture:** Mirror the existing `pkgs/cursor-agent/` pattern: per-platform `fetchurl` sources, a thin `stdenv.mkDerivation` that copies the binary into `$out/bin`, and a version-gated overlay entry. Linux uses the upstream `musl` static build so no `autoPatchelfHook` is required. The package is registered in `flake.nix` `packages` only — no home-module wiring.

**Tech Stack:** Nix (flakes), `stdenv.mkDerivation`, `fetchurl`. No Rust toolchain involved (binary repackaging only).

**Spec:** `docs/superpowers/specs/2026-04-06-llmfit-package-design.md`

**Branch:** `add-llm-fit` (already current; this plan executes inside the existing worktree at `/home/cmp/src/dotfiles/.worktrees/llmfit`)

---

## Reference data (already computed during planning)

**Pinned version:** `0.9.2` (released 2026-04-06)

**Per-platform asset URLs and SRI hashes:**

| System            | URL                                                                                                                         | SRI hash                                              |
|-------------------|-----------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------|
| `x86_64-linux`    | `https://github.com/AlexsJones/llmfit/releases/download/v0.9.2/llmfit-v0.9.2-x86_64-unknown-linux-musl.tar.gz`              | `sha256-UCx92aAC+ISDraISokNbnjNbfCF5X2tbvW7weuVrboQ=` |
| `aarch64-linux`   | `https://github.com/AlexsJones/llmfit/releases/download/v0.9.2/llmfit-v0.9.2-aarch64-unknown-linux-musl.tar.gz`             | `sha256-Ir7CAyXQTDGXVLiQue96efms6MdGBkM0/dZ7S6yQZks=` |
| `x86_64-darwin`   | `https://github.com/AlexsJones/llmfit/releases/download/v0.9.2/llmfit-v0.9.2-x86_64-apple-darwin.tar.gz`                    | `sha256-ICRoPw7F4sAFo54Wuv49yUrBc+da7ezuaWSwAU/SZaA=` |
| `aarch64-darwin`  | `https://github.com/AlexsJones/llmfit/releases/download/v0.9.2/llmfit-v0.9.2-aarch64-apple-darwin.tar.gz`                   | `sha256-zCO+Da9A3xQbIajGrWPTK1zv7vhnXUW6/MrIVI1aAi0=` |

**Tarball layout (verified during planning):** Each tarball contains a single top-level directory `llmfit-v0.9.2-<target>/` with `llmfit`, `LICENSE`, and `README.md` inside. Because there is exactly one top-level directory, `stdenv` auto-detects `sourceRoot` — **do not set `sourceRoot` in the derivation.**

---

## File structure

| Path                              | Action  | Responsibility                                                       |
|-----------------------------------|---------|----------------------------------------------------------------------|
| `pkgs/llmfit/package.nix`         | Create  | The derivation: per-platform sources + install of `bin/llmfit`       |
| `pkgs/llmfit/README.md`           | Create  | Purpose, dependencies, how to run `update.sh`                        |
| `pkgs/llmfit/update.sh`           | Create  | Bumps `version` + the four hashes from upstream releases             |
| `flake.nix`                       | Modify  | Register `llmfit` in the `packages` attrset                          |
| `overlays/default.nix`            | Modify  | Add a version-gated `llmfit` overlay entry                           |

No tests files — Nix package verification is the build itself plus a binary smoke run.

---

## Task 1: Create `pkgs/llmfit/package.nix`

**Files:**
- Create: `pkgs/llmfit/package.nix`

- [ ] **Step 1: Write the derivation**

Create `/home/cmp/src/dotfiles/.worktrees/llmfit/pkgs/llmfit/package.nix` with this exact content:

```nix
{
  lib,
  fetchurl,
  stdenv,
}:

let
  inherit (stdenv) hostPlatform;
  version = "0.9.2";
  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-x86_64-unknown-linux-musl.tar.gz";
      hash = "sha256-UCx92aAC+ISDraISokNbnjNbfCF5X2tbvW7weuVrboQ=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-aarch64-unknown-linux-musl.tar.gz";
      hash = "sha256-Ir7CAyXQTDGXVLiQue96efms6MdGBkM0/dZ7S6yQZks=";
    };
    x86_64-darwin = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-x86_64-apple-darwin.tar.gz";
      hash = "sha256-ICRoPw7F4sAFo54Wuv49yUrBc+da7ezuaWSwAU/SZaA=";
    };
    aarch64-darwin = fetchurl {
      url = "https://github.com/AlexsJones/llmfit/releases/download/v${version}/llmfit-v${version}-aarch64-apple-darwin.tar.gz";
      hash = "sha256-zCO+Da9A3xQbIajGrWPTK1zv7vhnXUW6/MrIVI1aAi0=";
    };
  };
in
stdenv.mkDerivation {
  pname = "llmfit";
  inherit version;

  src = sources.${hostPlatform.system} or (throw "llmfit: unsupported system ${hostPlatform.system}");

  # Tarball contains a single top-level directory (llmfit-v${version}-<target>/);
  # stdenv auto-detects sourceRoot, so we deliberately do NOT set it.

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 llmfit -t $out/bin
    install -Dm644 LICENSE -t $out/share/licenses/llmfit
    install -Dm644 README.md -t $out/share/doc/llmfit
    runHook postInstall
  '';

  passthru = {
    inherit sources;
    updateScript = ./update.sh;
  };

  meta = {
    description = "Right-sizes LLM models to your system's RAM, CPU, and GPU";
    homepage = "https://github.com/AlexsJones/llmfit";
    license = lib.licenses.mit;
    platforms = builtins.attrNames sources;
    mainProgram = "llmfit";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
```

**Why each piece:**
- `inherit (stdenv) hostPlatform;` — matches the style used in `pkgs/cursor-agent/package.nix`.
- `or (throw …)` — gives a clearer error than the default attr-not-found one when someone tries to build on Windows or freebsd.
- No `sourceRoot` — verified during planning that each tarball has exactly one top-level directory, so stdenv auto-detects it.
- `dontBuild = true;` — there's no compile step; the binary is already built.
- `install -Dm755 llmfit -t $out/bin` — single binary, no symlink dance like cursor-agent (which has many auxiliary files).
- `LICENSE` and `README.md` are also in the tarball; we install them under `share/` for tidiness (and so the MIT license text travels with the binary).
- `passthru.updateScript = ./update.sh;` — the file doesn't exist yet but `./update.sh` is just a path, not evaluated until something calls the update script. Safe to reference up front; we'll create the file in Task 7.
- `meta.platforms` is derived from `sources` so adding a platform updates both at once.
- `sourceProvenance = [ binaryNativeCode ]` — required by nixpkgs lint when shipping pre-built binaries.

- [ ] **Step 2: Stage the new file so flake eval can see it**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit add pkgs/llmfit/package.nix
```

(Reminder from `CLAUDE.md`: "New files must be `git add`ed before `nix build` — flake evaluation can't see untracked files.")

---

## Task 2: Wire `llmfit` into `flake.nix` packages

**Files:**
- Modify: `flake.nix` — `packages` attrset around line 156 (next to `wt`)

- [ ] **Step 1: Add the package entry**

In `/home/cmp/src/dotfiles/.worktrees/llmfit/flake.nix`, locate the line:

```nix
              wt = pkgs.callPackage ./pkgs/wt/default.nix { };
```

Insert immediately **after** it (so the new line precedes the `pi = …` and `default = …` entries):

```nix
              llmfit = pkgs.callPackage ./pkgs/llmfit/package.nix { };
```

The result should look like:

```nix
              wt = pkgs.callPackage ./pkgs/wt/default.nix { };
              llmfit = pkgs.callPackage ./pkgs/llmfit/package.nix { };
              pi = self.nixosConfigurations.rpi4.config.system.build.sdImage;
```

**Why here:** keeps `pi` and `default` together at the bottom (they're special — `pi` is a NixOS image, `default` is the home-manager activation). `wt` and `llmfit` are both standalone CLIs in this dotfiles repo, so they cluster naturally.

- [ ] **Step 2: Stage the change**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit add flake.nix
```

---

## Task 3: Build the package and smoke-test the binary

- [ ] **Step 1: Build `llmfit`**

```bash
cd /home/cmp/src/dotfiles/.worktrees/llmfit
nix build .#llmfit
```

Expected: build completes silently and produces a `result` symlink. No errors. If the build fails with `install: cannot stat 'llmfit'`, the tarball layout assumption is wrong — re-inspect with `tar -tzf $(nix eval --raw .#llmfit.src)` and adjust the `installPhase` (most likely add an explicit `sourceRoot = "llmfit-v${version}-<target-for-current-host>"`). This is unlikely; the layout was verified during planning.

- [ ] **Step 2: Smoke-run the binary**

```bash
./result/bin/llmfit --version
```

Expected: prints something containing `0.9.2` and exits 0. If `--version` is not a flag, try `./result/bin/llmfit --help` — same exit-0 expectation.

If neither works, the tarball was unpacked but the binary is broken on this host (rare for a static musl binary). Investigate before proceeding.

- [ ] **Step 3: Confirm the result symlink doesn't pollute git**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit status --short
```

Expected: no `result` line (the repo's `.gitignore` already excludes `result-*` and `result`). If `result` shows up, do not stage it; investigate `.gitignore` instead.

---

## Task 4: Add the version-gated overlay entry

**Files:**
- Modify: `overlays/default.nix` — add a new attribute alongside `cursor-agent` and `claude-code`

- [ ] **Step 1: Add the overlay**

In `/home/cmp/src/dotfiles/.worktrees/llmfit/overlays/default.nix`, locate the `cursor-agent` block (lines 40-52) and the `opencode` block (lines 54-66). Insert this **between** them — so the order becomes `cursor-agent`, `llmfit`, `opencode`:

```nix
  llmfit = (
    final: prev:
    let
      ours = self.packages.${final.stdenv.system}.llmfit;
    in
    {
      llmfit =
        if prev ? llmfit && prev.lib.versionAtLeast prev.llmfit.version ours.version then
          prev.llmfit
        else
          ours;
    }
  );
```

**Why version-gated:** mirrors `cursor-agent` and `claude-code`. If nixpkgs ever ships a newer `llmfit`, the overlay yields the upstream one and our local pin self-deprecates.

**Why between cursor-agent and opencode:** alphabetical-ish ordering (`c` < `l` < `o`) and groups it with the other coding-agent-adjacent overlays.

- [ ] **Step 2: Verify the overlay evaluates**

The overlay isn't applied to `importedPkgs` in `flake.nix` (no consumer today), so the easiest eval check is to query the overlay attrset directly:

```bash
nix eval --raw .#overlays.llmfit --apply 'o: builtins.typeOf o'
```

Expected: `lambda`

This confirms the new attribute parses and is a function.

- [ ] **Step 3: Re-build to make sure nothing regressed**

```bash
nix build .#llmfit
```

Expected: still succeeds (the overlay change is purely additive and shouldn't affect this build, but cheap insurance).

- [ ] **Step 4: Stage the overlay change**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit add overlays/default.nix
```

---

## Task 5: Write `pkgs/llmfit/README.md`

**Files:**
- Create: `pkgs/llmfit/README.md`

- [ ] **Step 1: Write the README**

Create `/home/cmp/src/dotfiles/.worktrees/llmfit/pkgs/llmfit/README.md` with this exact content:

```markdown
# llmfit

Terminal tool that right-sizes LLM models to your system's RAM, CPU, and GPU.
Upstream: <https://github.com/AlexsJones/llmfit>.

## Updating

Run from the repo root:

```bash
./pkgs/llmfit/update.sh
```

The script reads the latest GitHub release tag, fetches each platform's
`.sha256` sidecar file, converts the digest to a Nix SRI hash, and rewrites
the `version` and `hash = …` lines in `package.nix`.

## How it works

Pre-built tarballs are downloaded per-platform from
`github.com/AlexsJones/llmfit/releases`. Linux uses the upstream
`x86_64-unknown-linux-musl` / `aarch64-unknown-linux-musl` builds — they're
statically linked, so no `autoPatchelfHook` is required.

The overlay in `overlays/default.nix` exposes a version-gated `llmfit`
attribute: if nixpkgs ever ships a newer `llmfit`, the overlay yields the
upstream one instead of our local pin. The overlay is **not** applied to the
flake's active package set today (no module references `pkgs.llmfit`); it's
exposed under `self.overlays.llmfit` for opt-in use.

## Dependencies

None at runtime (statically linked binary on Linux, Mach-O binary on macOS).
Build-time: nothing beyond `stdenv` and `fetchurl`.
```

**Notes for the engineer:**
- The two ` ``` ` fences inside the file are intentional Markdown — the inner one is the bash block.
- The "How it works" section explicitly notes the overlay is not active. This is so a future reader doesn't try to debug why `pkgs.llmfit` is undefined and conclude the overlay is broken.

- [ ] **Step 2: Stage the README**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit add pkgs/llmfit/README.md
```

---

## Task 6: Format, full-flake build, commit the package

- [ ] **Step 1: Run treefmt**

```bash
cd /home/cmp/src/dotfiles/.worktrees/llmfit
nix fmt
```

Expected: any reformatting happens silently. If files were rewritten, re-stage them:

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit add pkgs/llmfit/package.nix flake.nix overlays/default.nix pkgs/llmfit/README.md
```

- [ ] **Step 2: Build the entire flake**

```bash
nix build .
```

Expected: builds the home-manager activation package successfully, proving we didn't accidentally break anything else. This may take a few minutes the first time.

- [ ] **Step 3: Commit the package, README, flake wiring, and overlay**

```bash
cd /home/cmp/src/dotfiles/.worktrees/llmfit
git commit -m "$(cat <<'EOF'
feat(pkgs): add llmfit package

Wraps the upstream pre-built release tarballs (musl static on Linux,
Mach-O on macOS) for github.com/AlexsJones/llmfit v0.9.2. Exposed as
self.packages.<system>.llmfit with a version-gated overlay; not yet
wired into any home module.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 4: Verify the commit landed**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit log --oneline -1
```

Expected: shows `feat(pkgs): add llmfit package` as HEAD.

---

## Task 7: Scaffold `pkgs/llmfit/update.sh` (with a learning-mode TODO)

**Files:**
- Create: `pkgs/llmfit/update.sh` (executable)

This task creates the script *with* a clearly-marked TODO block. Task 8 is where the user fills in the TODO.

- [ ] **Step 1: Write the scaffold**

Create `/home/cmp/src/dotfiles/.worktrees/llmfit/pkgs/llmfit/update.sh` with this exact content:

```bash
#!/usr/bin/env nix
#!nix shell --ignore-environment nixpkgs#cacert nixpkgs#bash nixpkgs#curl nixpkgs#nix nixpkgs#gnused nixpkgs#coreutils nixpkgs#gnugrep --command bash

set -euo pipefail

pkg=pkgs/llmfit/package.nix
repo="AlexsJones/llmfit"

# Resolve latest release tag from GitHub (unauthenticated; the API allows this).
tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
  | grep -m1 '"tag_name"' \
  | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
version="${tag#v}"

current=$(sed -nE 's/.*version = "([^"]+)".*/\1/p' "$pkg" | head -1)

echo "Latest version: $version"
echo "Current version: $current"

if [ "$version" = "$current" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating $current -> $version"

# Update version line
sed -i "s|version = \"$current\"|version = \"$version\"|" "$pkg"

# Per-platform asset suffix table.
declare -A targets=(
  [x86_64-linux]="x86_64-unknown-linux-musl"
  [aarch64-linux]="aarch64-unknown-linux-musl"
  [x86_64-darwin]="x86_64-apple-darwin"
  [aarch64-darwin]="aarch64-apple-darwin"
)

for system in "${!targets[@]}"; do
  target="${targets[$system]}"
  asset="llmfit-v${version}-${target}.tar.gz"
  url="https://github.com/$repo/releases/download/v${version}/${asset}"

  # ─── TODO (learning-mode contribution) ────────────────────────────────────
  # Fetch the per-asset .sha256 sidecar from "${url}.sha256" and convert it
  # into a Nix SRI hash assigned to the shell variable $sri.
  #
  # Two reasonable approaches:
  #
  #   (1) Fast — trust the upstream sidecar:
  #       hex=$(curl -fsSL "${url}.sha256" | awk '{print $1}')
  #       sri=$(nix hash convert --hash-algo sha256 --to sri --from base16 "$hex")
  #
  #   (2) Verify — re-download the tarball and have nix compute the hash:
  #       store=$(nix-prefetch-url "$url" --name "llmfit-${version}-${target}.tar.gz")
  #       sri=$(nix hash convert --to sri --hash-algo sha256 "$store")
  #
  # Approach (1) is faster and simpler; approach (2) catches the (rare) case
  # where the sidecar and tarball don't match. Pick one and replace the
  # placeholder line below.
  sri="REPLACE_ME"
  # ──────────────────────────────────────────────────────────────────────────

  if [ "$sri" = "REPLACE_ME" ]; then
    echo "ERROR: update.sh has an unfilled TODO block (sri = REPLACE_ME)" >&2
    exit 1
  fi

  echo "  $system: $sri"

  # Replace the hash on the line that follows this platform's URL.
  awk -v target="$target" -v newhash="$sri" '
    found && /hash =/ { sub(/hash = "sha256-[^"]*"/, "hash = \"" newhash "\""); found=0 }
    /url =/ && index($0, target) { found=1 }
    { print }
  ' "$pkg" > "$pkg.tmp" && mv "$pkg.tmp" "$pkg"
done

echo "Updated llmfit to $version"
```

**Why each piece:**
- The `#!/usr/bin/env nix` shebang + `#!nix shell --ignore-environment …` is the same pattern as `pkgs/cursor-agent/update.sh`. It runs the script reproducibly without needing a project shell.
- `--ignore-environment` means the script gets a clean PATH; we explicitly include every binary we use (`bash`, `curl`, `sed`, `awk`, `grep`, `nix`, `coreutils`, `cacert`).
- The latest-tag fetch uses the unauthenticated GitHub API endpoint — no `gh` CLI dependency, no token required.
- The `awk` block at the bottom is the same hash-splicing trick `cursor-agent/update.sh` uses: it walks the file, remembers when it saw a `url = …` line containing the target string, and rewrites the *next* `hash = …` line.
- The fail-fast guard (`if [ "$sri" = "REPLACE_ME" ]`) makes it impossible to accidentally run the scaffolded script and silently corrupt `package.nix`. The TODO must be filled before the script does anything destructive.

- [ ] **Step 2: Make it executable and stage it**

```bash
chmod +x /home/cmp/src/dotfiles/.worktrees/llmfit/pkgs/llmfit/update.sh
git -C /home/cmp/src/dotfiles/.worktrees/llmfit add pkgs/llmfit/update.sh
```

---

## Task 8: USER STEP — fill in the `update.sh` TODO block

This is the **learning-mode contribution moment**. The implementing engineer is Chris (the user). The agent should pause here and explicitly hand off.

- [ ] **Step 1: Hand off to the user**

Print this message:

> The `update.sh` scaffold is in place at `pkgs/llmfit/update.sh`. The TODO block (between the dashed comment lines) needs your call: do you want approach (1) — fast, trust the upstream sidecar — or approach (2) — slower, but re-verifies the tarball locally?
>
> Replace the `sri="REPLACE_ME"` line with the 1–2 lines from your chosen approach. About 5–10 lines of code total. Tell me when it's done and I'll smoke-test it.

Wait for the user to edit the file and confirm.

- [ ] **Step 2: Re-stage after the user's edit**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit add pkgs/llmfit/update.sh
```

---

## Task 9: Smoke-test the user-completed `update.sh`

- [ ] **Step 1: Run it (no-op expected, since we're already on `0.9.2`)**

```bash
cd /home/cmp/src/dotfiles/.worktrees/llmfit
./pkgs/llmfit/update.sh
```

Expected output:
```
Latest version: 0.9.2
Current version: 0.9.2
Already up to date.
```

If it complains about `REPLACE_ME`, the user's edit didn't take — go back to Task 8. If it tries to update *to* 0.9.2 from 0.9.2 (i.e., the early-out check failed), check the `current=$(sed …)` line for typos.

- [ ] **Step 2: Confirm `package.nix` is unchanged**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit diff pkgs/llmfit/package.nix
```

Expected: empty (the no-op path doesn't touch the file).

- [ ] **Step 3: (Optional) Force-test the update path**

This is genuinely optional and only worth doing if the user wants extra confidence in their TODO block. To exercise the rewrite paths without committing the change:

```bash
# Temporarily downgrade the pinned version to force an update
sed -i 's|version = "0.9.2"|version = "0.9.1"|' pkgs/llmfit/package.nix
./pkgs/llmfit/update.sh
# Should print "Updating 0.9.1 -> 0.9.2" and rewrite the hashes back.

git -C /home/cmp/src/dotfiles/.worktrees/llmfit diff pkgs/llmfit/package.nix
# Should show only the version line restored to 0.9.2 plus four hash lines
# that match the values committed in Task 6 — i.e., a "round trip" diff.

# Restore from the committed state to be safe.
git -C /home/cmp/src/dotfiles/.worktrees/llmfit restore pkgs/llmfit/package.nix
```

If the round-trip diff produces hashes *different* from what's already committed, the user's `nix hash convert` line is wrong (e.g., wrong `--from` flag or missing sha256: prefix). Fix it before continuing.

- [ ] **Step 4: Re-build the package once more**

```bash
nix build .#llmfit
```

Expected: still succeeds (sanity check after any test rewrites).

---

## Task 10: Commit `update.sh`

- [ ] **Step 1: Confirm the working tree state**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit status --short
```

Expected: only `pkgs/llmfit/update.sh` is staged. Nothing else modified.

- [ ] **Step 2: Commit**

```bash
cd /home/cmp/src/dotfiles/.worktrees/llmfit
git commit -m "$(cat <<'EOF'
feat(pkgs): add llmfit update script

Reads the latest GitHub release tag, refreshes the four per-platform
hashes in package.nix. Uses the upstream .sha256 sidecars (or
nix-prefetch-url, depending on the chosen approach).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 3: Verify**

```bash
git -C /home/cmp/src/dotfiles/.worktrees/llmfit log --oneline -3
```

Expected: shows the two new commits (`feat(pkgs): add llmfit update script` and `feat(pkgs): add llmfit package`) on top of the design-doc commit (`docs(specs): add llmfit package design`).

---

## Done criteria

All of these must be true:

- [ ] `nix build .#llmfit` succeeds and `result/bin/llmfit` runs.
- [ ] `nix build .` (full home-manager activation) still succeeds.
- [ ] `nix fmt` leaves no changes.
- [ ] `nix eval --raw .#overlays.llmfit --apply 'o: builtins.typeOf o'` returns `lambda`.
- [ ] `./pkgs/llmfit/update.sh` is executable and prints "Already up to date." on the pinned version.
- [ ] Two new commits exist on `add-llm-fit`: `feat(pkgs): add llmfit package` and `feat(pkgs): add llmfit update script`.
- [ ] `git status` is clean.
