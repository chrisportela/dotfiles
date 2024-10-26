{config, lib, ...}: {
  # Pending https://github.com/NixOS/nixpkgs/issues/55674
  options.allowedUnfree = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
  };

  config = {
    nixpkgs.config.allowUnfreePredicate = lib.mkForce (p: builtins.elem (lib.getName p) config.allowedUnfree);

    nix = {
      # nixPath = null;
      # keepOldNixPath = null;
      # channels = null;
    };
  };
}
