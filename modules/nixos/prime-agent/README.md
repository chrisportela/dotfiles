# prime-agent Module

Opt-in NixOS environment for [prime-agent](../../../pkgs/prime-agent/README.md)
and the tooling it drives through uv. Intended for hosts, microVMs and
containers where the agent runs.

prime-agent assumes a normal Linux userland: its Python kernel bootstrap has
uv create a venv, download a Python and install manylinux wheels (numpy,
pandas, ...), and the agent itself runs `uv run` / `uvx` freely. None of that
works on stock NixOS. This module makes it work without building or patching
any Python.

## Options

All options under `chrisportela.prime-agent`:

- `enable` — Install the wrapped prime-agent and set up the environment.
- `package` — The prime-agent package. Defaults to `pkgs.prime-agent`, falling back to `pkgs/prime-agent` from this repo (NixOS hosts do not get the home overlays).
- `pythons` — Interpreters exposed as `python3.X` on PATH. Default: `python311`–`python314`. prime-agent requests 3.11.
- `libraries` / `extraLibraries` — Shared libraries for wheels and downloaded binaries. Defaults cover libstdc++, zlib, zstd, xz, bzip2, openssl, libffi, sqlite, expat, ncurses, readline, libxml2, libxslt, glib and libuuid. Put GUI libraries (`libGL`, `xorg.libX11`, `fontconfig`) in `extraLibraries`.
- `nixLd.enable` — Enable `programs.nix-ld` with the same libraries (default on).
- `toolchain.enable` — Install gcc, gnumake, pkg-config and cmake so uv can build sdists (default on).

## What it sets up

- **Pythons from nixpkgs, unmodified.** `bin/python3.X` are symlinks to the stock cached interpreters. Nothing is overridden or wrapped, so no Python is rebuilt. `/etc/uv/uv.toml` sets `python-preference = "only-system"` and `python-downloads = "never"`, so `uv venv --python 3.11`, `uv run` and `uvx` use them instead of python-build-standalone downloads (which cannot run on NixOS). User and project uv config and `UV_*` variables still override.
- **`LD_LIBRARY_PATH` for prime-agent only.** nix-ld does not apply to nixpkgs Pythons, which load extension modules through nix's glibc loader, so wheels such as numpy need `libstdc++.so.6` on `LD_LIBRARY_PATH`. The installed `prime-agent` is a wrapper that suffixes it for the agent, its kernel and their subprocesses; nothing is set system-wide.
- **nix-ld** for prebuilt executables the agent downloads.
- uv, git and the C toolchain on the system PATH.

## Dependencies

- `pkgs/prime-agent` (the package).
- The host's nixpkgs must provide `python311`–`python314` (or override `pythons`).

## Gotchas

- **Keep `pythons` and `libraries` unmodified.** Overriding or overlaying them (for example `python311.override`) changes the derivation and forces a local rebuild instead of a cache hit.
- **Python 3.10 and older are not in nixpkgs-unstable.** A project that pins one will fail to resolve an interpreter under `python-downloads = "never"`.
- **Version bumps of the package:** the kernel is currently pinned to 3.11 upstream; check `PYTHON_VERSION` in `crates/pa-core/src/kernel/bootstrap/venv.rs` when updating and keep that version in `pythons`.
- Not enabled on any host by default.

## Example

```nix
# in a host (or microVM/container NixOS config) that imports self.nixosModules.default
{
  chrisportela.prime-agent = {
    enable = true;
    extraLibraries = with pkgs; [ libGL ]; # optional
  };
}
```
