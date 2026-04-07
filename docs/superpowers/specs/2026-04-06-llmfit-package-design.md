# llmfit package — design

**Date:** 2026-04-06
**Status:** approved
**Branch:** `add-llm-fit`

## Summary

Add a Nix package for [`AlexsJones/llmfit`](https://github.com/AlexsJones/llmfit), a Rust TUI/CLI that scores LLM models against the host's RAM, CPU, and GPU. The package wraps the upstream pre-built release tarballs (no build-from-source), is exposed only as a flake package (`self.packages.<system>.llmfit`), and is shadowed into nixpkgs via a version-gated overlay so any future `pkgs.llmfit` reference resolves to ours unless nixpkgs ships a newer version.

## Goals

- `nix run .#llmfit -- …` works on `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`.
- `nix build .#llmfit` produces a derivation containing `bin/llmfit`.
- `nix build .` (full home-manager activation) keeps working.
- `pkgs.llmfit` resolves to our package (via overlay) for any future module wiring.
- An `update.sh` script bumps version + per-platform hashes from upstream releases with a single command.

## Non-goals

- Auto-installing llmfit into any home module. The user opted to keep it as a flake package only for now.
- Building llmfit from source (the upstream tarballs are static-linkable musl/Mach-O binaries; build-from-source would pull a Rust toolchain for no benefit).
- Packaging the llmfit web dashboard or desktop app — only the `llmfit` CLI/TUI binary.
- Shipping llmfit on platforms upstream doesn't release for (Windows, x86_64 BSDs, etc.).

## Architecture

### File layout

```
pkgs/llmfit/
├── package.nix     # platform-keyed sources + stdenv.mkDerivation
├── update.sh       # bumps version + hashes from upstream releases
└── README.md       # purpose, how to update, dependencies
```

This mirrors `pkgs/cursor-agent/` and `pkgs/claude-code/` exactly.

### Per-platform sources

| Nix system        | Upstream asset                                        |
|-------------------|-------------------------------------------------------|
| `x86_64-linux`    | `llmfit-vX.Y.Z-x86_64-unknown-linux-musl.tar.gz`      |
| `aarch64-linux`   | `llmfit-vX.Y.Z-aarch64-unknown-linux-musl.tar.gz`     |
| `x86_64-darwin`   | `llmfit-vX.Y.Z-x86_64-apple-darwin.tar.gz`            |
| `aarch64-darwin`  | `llmfit-vX.Y.Z-aarch64-apple-darwin.tar.gz`           |

Initial pin: **`0.9.2`** (released 2026-04-06).

Linux uses the **musl** variant deliberately: it is statically linked, so the derivation needs no `autoPatchelfHook`, no `stdenv.cc.cc.lib`, and no `nativeBuildInputs`. The cost is ~100 KB of size; the benefit is a derivation that's ~25 lines and survives any glibc skew between hosts.

### Derivation skeleton

```nix
{ lib, fetchurl, stdenv }:
let
  version = "0.9.2";
  sources = {
    x86_64-linux  = fetchurl { url = "…linux-musl.tar.gz";   hash = "sha256-…"; };
    aarch64-linux = fetchurl { url = "…linux-musl.tar.gz";   hash = "sha256-…"; };
    x86_64-darwin = fetchurl { url = "…apple-darwin.tar.gz"; hash = "sha256-…"; };
    aarch64-darwin = fetchurl { url = "…apple-darwin.tar.gz"; hash = "sha256-…"; };
  };
in
stdenv.mkDerivation {
  pname = "llmfit";
  inherit version;

  src = sources.${stdenv.hostPlatform.system};
  sourceRoot = ".";

  installPhase = ''
    runHook preInstall
    install -Dm755 llmfit -t $out/bin
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

**Tarball-layout caveat:** the implementation step must verify the actual binary path inside each tarball. If upstream nests it under `llmfit-vX.Y.Z/`, set `sourceRoot = "llmfit-v${version}";` (or `null` and adjust the `installPhase` to find the binary). This is a known unknown — the implementation plan must include a verification step.

### Registration

**`flake.nix`** — add to the `packages` attrset (sorted to fit existing style):

```nix
llmfit = pkgs.callPackage ./pkgs/llmfit/package.nix { };
```

This sits next to `wt`, `claude-code`, etc.

**`overlays/default.nix`** — add a version-gated overlay mirroring the `cursor-agent` / `claude-code` pattern:

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

The overlay is *not* applied to `importedPkgs` in `flake.nix` today (because no module references `pkgs.llmfit`), but it's exposed via `self.overlays.llmfit` so future consumers can opt in. Adding it to the active overlay list is a separate, deliberate change.

### `update.sh` strategy

llmfit publishes GitHub releases with `<asset>.sha256` sidecar files containing the hex digest. The update script can therefore avoid `nix-prefetch-url` entirely:

1. Resolve latest tag — `gh release view --repo AlexsJones/llmfit --json tagName --jq .tagName` (or unauthenticated `curl https://api.github.com/repos/AlexsJones/llmfit/releases/latest`).
2. Extract the version (strip leading `v`).
3. Compare against the current version pinned in `package.nix`; bail early if equal.
4. For each of the four platform/asset pairs:
   - `curl -sSL <asset>.sha256` to grab the hex digest
   - convert to Nix SRI form: `nix hash convert --hash-algo sha256 --to sri sha256:<hex>`
   - sed-replace the per-platform `hash = "sha256-…"` line in `package.nix`
5. sed-replace the `version = "…"` line.

This is meaningfully simpler than `pkgs/cursor-agent/update.sh` — no per-platform `nix-prefetch-url`, no awk-based hash splicing keyed off URL paths. It does **trust upstream sidecars**: an attacker who compromised the GitHub release could publish a matching `.sha256` for a tampered tarball. For a personal dotfiles repo with manual review of the resulting diff, this trade is acceptable. (The alternative — `nix-prefetch-url` — would catch a sidecar/tarball mismatch but adds ~30s and four extra downloads per run.)

The script uses the same `nix shell --ignore-environment` shebang pattern as `cursor-agent/update.sh` so it's reproducible without a project shell.

### Learning-mode handoff

The implementation step will scaffold the script with a clear `TODO` block where the "fetch sidecar → convert to SRI" loop goes. The user writes that ~5–10 line block themselves. Two valid approaches will be documented inline:

1. **`nix-prefetch-url` per asset** — matches `cursor-agent/update.sh`; slower but verifies tarballs locally.
2. **`curl … | nix hash convert`** — faster, trusts upstream sidecars.

This is a security-vs-speed call where the user's preference matters and shapes the resulting maintenance ergonomics.

## Data flow

```
release on github.com/AlexsJones/llmfit
            ↓
        update.sh  (manual: ./pkgs/llmfit/update.sh)
            ↓
   pkgs/llmfit/package.nix  (version + 4 hashes bumped)
            ↓
 self.packages.<system>.llmfit  (via flake.nix callPackage)
            ↓
       nix build .#llmfit       →  result/bin/llmfit
       nix run   .#llmfit -- …  →  TUI runs

(future) self.overlays.llmfit applied → pkgs.llmfit available in modules
```

## Error handling

- **Unsupported platform:** `meta.platforms` lists only the four supported systems; `nix build .#llmfit` on an unsupported system fails with a clear "package … is not available on the requested hostPlatform" error from nixpkgs. No custom handling needed.
- **Tarball-layout mismatch:** if the binary isn't where `installPhase` expects it, the build fails loudly with `install: cannot stat 'llmfit'`. The implementation plan must verify layout before claiming success.
- **`update.sh` failures:** uses `set -euo pipefail`; any curl, sed, or `nix hash convert` failure aborts the run with the failing line. The script bails early if the latest version matches the current pin (no-op on `git diff`).

## Testing

The package has no unit tests of its own. Verification is:

1. **Eval** — `nix eval .#llmfit.version` returns `"0.9.2"`.
2. **Build (current host only)** — `nix build .#llmfit` succeeds and produces `result/bin/llmfit`.
3. **Smoke run** — `./result/bin/llmfit --version` (or `--help`) exits 0 and prints the expected version. This is the load-bearing test: it proves the tarball-layout assumption in `installPhase` is correct *and* the binary is executable on the build host.
4. **Full flake build** — `nix build .` still succeeds (proves we didn't break home-manager activation).
5. **Treefmt** — `nix fmt` leaves no changes (or `nix flake check` passes the formatting check).

Cross-platform builds (e.g., aarch64-linux from x86_64-linux) are *not* part of the test plan — the expectation is that each host validates its own platform on first build, and the update script's per-platform hashes guarantee determinism across platforms.

## Out-of-scope improvements

These are tempting but explicitly deferred:

- **Wiring `llmfit` into `coding-agents.nix`** — user chose flake-package-only.
- **Adding the overlay to `importedPkgs.overlays` in `flake.nix`** — no consumer today; would be a no-op churn.
- **A NixOS module exposing `programs.llmfit`** — overkill for a CLI with no daemon, no config file.
- **Cross-compiling from source for unusual targets** — not needed; upstream covers our platforms.
