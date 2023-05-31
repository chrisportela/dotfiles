# Chris' dotfiles

- Requires flakes and nix-command features enabled
  - `mkdir -p $HOME/.config/nix/ && echo "experimental-features = flakes nix-command" >> $HOME/.config/nix/nix.conf"`
- Requires `Nix` 2.3+
  - `sh <(curl -L https://nixos.org/nix/install) --daemon`
  - `curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install`
- If on macOS install `nix-darwin`

## Quick Setup

1. Configure OS: `[nixos|darwin]-rebuild switch --flake .`
2. Setup home-manager: `nix run . -- switch -b backup --flake .`

Once home-manager is configured you can run `switch-{nix,darwin,home}` to update.
