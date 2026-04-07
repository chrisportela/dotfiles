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
