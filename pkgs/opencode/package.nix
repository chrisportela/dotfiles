{
  callPackage,
  fetchFromGitHub,
}:

let
  version = "1.17.19";
  srcHash = "sha256-zpGO6DpWDC3unpiTKZY7/s4fDbZwmtR+xzWF98MwJoQ=";
  nodeModulesHash = "sha256-pk5JjO3RHjdOX1T9qX4UWOv7dST/i3DmHGhxTb5QJDA=";

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
