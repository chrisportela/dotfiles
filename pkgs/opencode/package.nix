{
  callPackage,
  fetchFromGitHub,
  stdenv,
}:

let
  version = "1.18.18";
  srcHash = "sha256-rDVcv8j9KghTDwooPYriTloOMgTyVutud7xKLG2mTmk=";
  nodeModulesHash =
    if stdenv.isDarwin then
      "sha256-AkJwfLULLZVwwz+XU1QcFUZoIS7oVPCn+n/MXEaxrqE="
    else
      "sha256-TNwKfqxD83UpZuCKN8FdEWN+CcQUP9CkCQSLGNqR/sA=";

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
