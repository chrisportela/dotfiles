{
  upstreamOpencode,
}:

let
  version = "1.17.7";
in
upstreamOpencode.overrideAttrs (
  finalAttrs: prev: {
    inherit version;

    src = prev.src.override {
      tag = "v${version}";
      hash = "sha256-rTeJuwqc11r6Xiksfg5IoTezK2ZtG3GlenQCxTW04P4=";
    };

    node_modules = prev.node_modules.overrideAttrs {
      inherit (finalAttrs) version src;
      outputHash = "sha256-DntnRo2N32nhjv8YxedIbRMtEkSsXAOrpFmK6six/g4=";
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
