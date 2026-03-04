# Overlays used by packages and devShells. Called as: (import ./overlays/default.nix) { inherit self inputs; }
{ self, inputs }: {
  rust = (import inputs.rust-overlay);

  rustToolchain =
    (final: prev: { rustToolchain = prev.rust-bin.stable.latest.default; });

  deploy-rs = (final: prev: {
    deploy-rs = inputs.deploy-rs.defaultPackage.${final.stdenv.system};
  });

  terraform = (final: prev: {
    terraformFull = self.packages.${final.stdenv.system}.terraform;
  });

  setup-envrc = (final: prev: {
    setup-envrc = self.packages.${final.stdenv.system}.setup-envrc;
  });

  claude-code = (final: prev: {
    claude-code = self.packages.${final.stdenv.system}.claude-code;
  });

  opencode-cursor = (final: prev: {
    opencode-cursor = self.packages.${final.stdenv.system}.opencode-cursor;
  });
}
