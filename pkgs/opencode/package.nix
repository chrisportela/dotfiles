{
  upstreamOpencode,
}:

let
  version = "1.15.0";
in
upstreamOpencode.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${version}";
      hash = "sha256-qVkOgLXUU/vaWDZIkBeR3Fhkcz7cPshpyQIkuxwKUEM=";
    };

    node_modules = prev.node_modules.overrideAttrs {
      inherit (finalAttrs) version src;
      outputHash = "sha256-mozaLyyHm7fO6XYTrEMb1in0LNtA4BXZAowJ+8UMh7Q=";
    };

    postPatch = (prev.postPatch or "") + ''
      # HACK: remove when nixos-unstable's upstream opencode catches up to >=1.14.19.
      # The pinned upstream (1.4.11) builds node_modules without --filter ./,
      # so root workspace devDependencies like prettier are missing. Bun's
      # single-file compiler then fails on the dynamic import in generate.ts.
      substituteInPlace packages/opencode/script/build.ts \
        --replace-fail 'external: ["node-gyp"]' \
          'external: ["node-gyp", "prettier", "prettier/plugins/babel", "prettier/plugins/estree"]'
    '';

    passthru = prev.passthru // {
      updateScript = ./update.sh;
    };
  }
)
