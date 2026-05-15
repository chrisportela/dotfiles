# Declarative Hydra project spec for cmp/dotfiles.
#
# Hydra evaluates this file (via nix-build) and reads the resulting JSON
# to create / update the project's jobsets. The owning project is
# configured (one-time, via the Hydra UI) with:
#
#   declarative.spec  = "hydra/spec.nix"
#   declarative.type  = "git"
#   declarative.value = "git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git main"
#
# After bootstrap, all jobset changes happen by editing this file and
# pushing to main — Hydra picks up changes on its next evaluation of
# the project's hidden `.jobsets` jobset.
#
# Build manually: `nix-build hydra/spec.nix` → produces a `spec.json`.
let
  pkgs = import <nixpkgs> { };

  flakeUri = "git+ssh://forgejo@git.cafecito.cloud:2222/cmp/dotfiles.git";

  defaults = {
    enabled = 1;
    hidden = false;
    checkinterval = 300; # seconds between evaluations
    schedulingshares = 100;
    enableemail = false;
    emailoverride = "";
    keepnr = 5;
    type = "flake";
  };

  jobsets = {
    main = defaults // {
      description = "cmp dotfiles: hosts + packages + devshells + home activations (main)";
      flake = "${flakeUri}?ref=main";
    };
  };
in
pkgs.writeText "spec.json" (builtins.toJSON jobsets)
