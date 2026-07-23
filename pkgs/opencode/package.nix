{
  callPackage,
  fetchFromGitHub,
}:

let
  version = "1.18.4";
  srcHash = "sha256-tGMO5JktINO8kXAHFQftn+JCrzwvpmNipTa8V0aIfNI=";
  nodeModulesHash = "sha256-qt11SKmOjq0KU542QFbs+u7YyJicn4drCcwCdg325yk=";

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${version}";
    hash = srcHash;
  };

  # Build node_modules from opencode's own nix/node_modules.nix. Drop --frozen-lockfile
  # so nixpkgs bun (1.3.13) can re-resolve the lockfile that was generated with bun@1.3.14.
  node_modules =
    (callPackage "${src}/nix/node_modules.nix" {
      hash = nodeModulesHash;
    }).overrideAttrs
      (o: {
        inherit version; # avoid the "+dirty" rev suffix — opencode.nix inherits version from node_modules
        __intentionallyOverridingVersion = true; # src is correct; only the rev-suffix in version changes
        buildPhase = builtins.replaceStrings [ "--frozen-lockfile" ] [ "" ] o.buildPhase;
      });
in
(callPackage "${src}/nix/opencode.nix" { inherit node_modules; }).overrideAttrs (prev: {
  passthru = (prev.passthru or { }) // {
    updateScript = ./update.sh;
  };
})
