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

  wt = (
    final: prev: {
      wt = self.packages.${final.stdenv.system}.wt;
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

  cursor-agent = (
    final: prev:
    let
      ours = self.packages.${final.stdenv.system}.cursor-agent;
    in
    {
      cursor-agent =
        if prev ? cursor-agent && prev.lib.versionAtLeast prev.cursor-agent.version ours.version then
          prev.cursor-agent
        else
          ours;
    }
  );

  llmfit = (
    final: prev:
    let
      ours = self.packages.${final.stdenv.system}.llmfit;
    in
    {
      llmfit =
        if prev ? llmfit && prev.lib.versionAtLeast prev.llmfit.version ours.version then
          prev.llmfit
        else
          ours;
    }
  );

  opencode = (
    final: prev:
    let
      ours = self.packages.${final.stdenv.system}.opencode;
    in
    {
      opencode =
        if prev ? opencode && prev.lib.versionAtLeast prev.opencode.version ours.version then
          prev.opencode
        else
          ours;
    }
  );

  openclaw = (
    final: prev: {
      openclaw = self.packages.${final.stdenv.system}.openclaw;
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

  plane-mcp-server = (
    final: prev: {
      plane-mcp-server = self.packages.${final.stdenv.system}.plane-mcp-server;
    }
  );

  context7 = (
    final: prev: {
      context7 = self.packages.${final.stdenv.system}.context7;
    }
  );

  # Skips the OpenLDAP check phase for the i686 build only, which is pulled
  # in by 32-bit multilib (lutris/steam). test017-syncreplication-refresh
  # is a timing-sensitive flake; bumping SLEEP1/SLEEP2 didn't help. Scoped
  # to pkgsi686Linux so the x86_64 build stays on the binary cache.
  # Tracked upstream in https://github.com/NixOS/nixpkgs/issues/514113 —
  # acknowledged as low-urgency; disabling checks is the recommended workaround.
  openldap = (
    final: prev: {
      pkgsi686Linux = prev.pkgsi686Linux.extend (
        _: prevI686: {
          openldap = prevI686.openldap.overrideAttrs (_: {
            doCheck = false;
          });
        }
      );
    }
  );
}
