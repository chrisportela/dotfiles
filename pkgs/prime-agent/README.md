# prime-agent

[Prime Agent](https://github.com/PrimeIntellect-ai/prime-agent): Prime
Intellect's RLM coding agent harness (Rust, with a persistent Python control
environment).

## Updating

Run from the repo root:

```bash
./pkgs/prime-agent/update.sh
```

It reads the latest stable release, refreshes the source hash, then builds with
a dummy `cargoHash` to learn the real one. Only stable releases work: betas
publish no `-src.tar.gz`.

## How it works

- **Source:** the release's `prime-agent-<version>-src.tar.gz`, not the git
  tree. The bundled model and MCP catalogs (`*.bundled.json`) only exist in
  that asset. It is flat, hence `stripRoot = false`.
- **Layout:** mirrors upstream's Homebrew formula. The real binary lives in
  `$out/libexec/prime-agent/` beside `prime-agent-runtime/`, `skills/` and the
  catalogs, because the binary finds them relative to `current_exe()`.
  `$out/bin/prime-agent` is a `makeWrapper` script that execs it. Do not
  switch to `wrapProgram`: it renames the binary, which breaks package-dir
  resolution and the daemon's `prime-agent` process-name matching.
- **Wrapper defaults:** `uv` on `PATH` (suffixed, so a devShell's wins),
  `PI_SKIP_VERSION_CHECK=1` (self-update cannot work in `/nix/store`) and
  `DO_NOT_TRACK=1` (upstream telemetry off; export `DO_NOT_TRACK=0` to turn it
  on).
- **Patch:** `skip-uv-python-install.patch` drops the explicit
  `uv python install 3.11` from the kernel bootstrap. `uv venv --python 3.11`
  installs the same managed Python on demand, so a normal system behaves as
  upstream; with `python-downloads = "never"` (the NixOS module) the explicit
  step would abort the bootstrap. A version bump that moves this code fails the
  patch phase, which is the cue to rebase the patch.
- `doCheck = false`: the workspace suite needs tmux, uv with network access and
  spawns daemons.

## Runtime expectations

The package assumes a normal Linux or macOS userland: on first use the kernel
bootstrap has uv create `~/.prime/...` venvs, download a Python and install
wheels. That does not work on stock NixOS. Enable
`chrisportela.prime-agent` (see `modules/nixos/prime-agent/README.md`) on NixOS
hosts, VMs and containers.
