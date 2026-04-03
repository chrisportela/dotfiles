# cursor-agent

Cursor AI agent CLI for agentic coding from the terminal.

## Updating

Run from the repo root:

```bash
./pkgs/cursor-agent/update.sh
```

The script fetches the latest release from `cursor.com/install`, updates all platform
URLs and hashes in `package.nix`, then prints the new version.

## How it works

Pre-built binary downloaded per-platform from `downloads.cursor.com`. On Linux,
`autoPatchelfHook` patches the ELF binary to use Nix store paths for shared libraries.

The overlay in `overlays/default.nix` ensures we use our version unless nixpkgs
ships a newer one.

## Dependencies

None at runtime (statically linked binary). Build-time: `autoPatchelfHook` + `stdenv.cc.cc.lib` on Linux.
