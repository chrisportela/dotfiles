{
  callPackage,
  fetchFromGitHub,
  lib,
  stdenv,
}:

let
  version = "1.18.29";
  srcHash = "sha256-lCXlxTOhcX70jxJAbpolyGlIxQK2nst+6bFhq3Xzdmc=";

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${version}";
    hash = srcHash;
  };

  # node_modules FOD hashes come verbatim from upstream's nix/hashes.json
  # (vendored by update.sh); our build reproduces upstream's output exactly.
  nodeModulesHash = (lib.importJSON ./hashes.json).nodeModules.${stdenv.hostPlatform.system};

  # Vendored copies of opencode's nix/ expressions — importing them from
  # ${src} would be IFD, which nix flake check and Hydra eval forbid.
  node_modules = callPackage ./node_modules.nix {
    inherit src version;
    hash = nodeModulesHash;
  };
in
(callPackage ./opencode.nix { inherit node_modules; }).overrideAttrs (prev: {
  passthru = (prev.passthru or { }) // {
    updateScript = ./update.sh;
  };
})
