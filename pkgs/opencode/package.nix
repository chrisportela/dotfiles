{
  callPackage,
  fetchFromGitHub,
  stdenv,
}:

let
  version = "1.18.16";
  srcHash = "sha256-AP2W443Zk/X8j6BWfMgAEbR4BQiJgnPpr1OG6JWIprE=";
  nodeModulesHash =
    if stdenv.isDarwin then
      "sha256-IyFm5NbnU63BaOO/F4/v1exz3VbvkY96yjg9iun+O9Q="
    else
      "sha256-uduwrM143NDSc+tXsi4lVVfoMll2a3BDHRUjuO7GB68=";

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
        # buildPhase = builtins.replaceStrings [ "--frozen-lockfile" ] [ "" ] o.buildPhase;
      });
in
(callPackage "${src}/nix/opencode.nix" { inherit node_modules; }).overrideAttrs (prev: {
  passthru = (prev.passthru or { }) // {
    updateScript = ./update.sh;
  };
})
