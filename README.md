# Chris' dotfiles

Collection of scripts, utilities, home-manager, and NixOS configurations.

## Usage

- Requires a recent version of `Nix` (At least ~2.4, but probably 2.18+)
  - `curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install`
  - `sh <(curl -L https://nixos.org/nix/install) --daemon`
- **[macOS Users]** install `nix-darwin` [by reading these docs](https://github.com/LnL7/nix-darwin?tab=readme-ov-file#flakes).

> [!info] Requires Flakes and nix commands enabled
>
> 1. Ensure you have the nix config folder in your home dir: `mkdir -p $HOME/.config/nix/`
>
> 2. Add the line enabling these features to the config file: `echo "experimental-features = flakes nix-command" >> $HOME/.config/nix/nix.conf"`

While you *can use it directly*, I recommend cloning so you can make changes.

1. Clone this repo and `cd` into the folder
2. Test build using default home-manager config: `nix build .`
3. Setup configuration: `nix run . -- -b backup`
   1. You might need the `-b backup` to let it move existing configs around so it can "take over" with a symlink.

Part of the configuration has shell functions `switch-home`, `switch-nix`, and `switch-darwin` which expect the repo at `$HOME/src/dotfiles` and will apply whatever configuration is there.
