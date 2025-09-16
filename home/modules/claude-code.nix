{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.chrisportela;
in
{
  options.chrisportela = {
    claude = lib.mkEnableOption "Claude Code";
  };

  config = {

    allowedUnfree = [ "claude-code" ];

    home.packages = with pkgs; [
      claude-code
    ];

  };
}
