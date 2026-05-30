{
  upstreamOpencode,
}:

let
  version = "1.15.12";
in
upstreamOpencode.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${version}";
      hash = "sha256-ecSZVJ1uyubWcIhp29FS0MA2MCgURN2jo6CFRJ1mm2I=";
    };

    node_modules = prev.node_modules.overrideAttrs {
      inherit (finalAttrs) version src;
      outputHash = "sha256-x5qbmA4/EhEbqyGHAy8VRXw9Do8QYHTRLeZXuyvd4QY=";
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
