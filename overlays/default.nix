# Overlays used by packages and devShells. Called as: (import ./overlays/default.nix) { inherit self inputs; }
{ self, inputs }:
{
  rust = (import inputs.rust-overlay);

  rustToolchain = (final: prev: { rustToolchain = prev.rust-bin.stable.latest.default; });

  deploy-rs = (
    final: prev: {
      deploy-rs = inputs.deploy-rs.defaultPackage.${final.stdenv.system};
    }
  );

  terraform = (
    final: prev: {
      terraformFull = self.packages.${final.stdenv.system}.terraform;
    }
  );

  setup-envrc = (
    final: prev: {
      setup-envrc = self.packages.${final.stdenv.system}.setup-envrc;
    }
  );

  claude-code = (
    final: prev:
    let
      ours = self.packages.${final.stdenv.system}.claude-code;
    in
    {
      claude-code =
        if prev ? claude-code && prev.lib.versionAtLeast prev.claude-code.version ours.version then
          prev.claude-code
        else
          ours;
    }
  );

  openclaw = (
    final: prev:
    let
      ours = self.packages.${final.stdenv.system}.openclaw;
      base =
        if prev ? openclaw && prev.lib.versionAtLeast prev.openclaw.version ours.version then
          prev.openclaw
        else
          ours;
    in
    {
      openclaw = base.overrideAttrs (p: {
        meta = p.meta // {
          knownVulnerabilities = [ ];
        };
      });
    }
  );

  opencode-cursor = (
    final: prev: {
      opencode-cursor = self.packages.${final.stdenv.system}.opencode-cursor;
    }
  );

  cliclick = (
    final: prev:
    prev.lib.optionalAttrs prev.stdenv.isDarwin {
      cliclick = self.packages.${prev.stdenv.system}.cliclick;
    }
  );

  peekaboo = (
    final: prev: {
      peekaboo = self.packages.${final.stdenv.system}.peekaboo;
    }
  );
}
