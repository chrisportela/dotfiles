{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.programs.difftastic;
in
{
  meta.maintainers = [ ];

  options = {
    programs.difftastic = {
      enable = mkEnableOption "" // {
        description = ''
          Enable the {command}`difftastic` syntax highlighter.
          See <https://github.com/Wilfred/difftastic>.
        '';
      };

      package = mkOption {
        type = types.package;
        default = pkgs.difftastic;
        defaultText = literalExpression "pkgs.difftastic";
        description = ''
          Difftastic package
        '';
      };

      background = mkOption {
        type = types.enum [
          "light"
          "dark"
        ];
        default = "light";
        example = "dark";
        description = ''
          Determines whether difftastic should use the lighter or darker colors
          for syntax highlighting.
        '';
      };

      color = mkOption {
        type = types.enum [
          "always"
          "auto"
          "never"
        ];
        default = "auto";
        example = "always";
        description = ''
          Determines when difftastic should color its output.
        '';
      };

      display = mkOption {
        type = types.enum [
          "side-by-side"
          "side-by-side-show-both"
          "inline"
        ];
        default = "side-by-side";
        example = "inline";
        description = ''
          Determines how the output displays - in one column or two columns.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ cfg.package ];

    programs.git.iniContent =
      let
        difft = "${pkgs.difftastic}/bin/difft";
        difftCommand = concatStringsSep " " [
          difft
          "--color ${cfg.color}"
          "--background ${cfg.background}"
          "--display ${cfg.display}"
        ];
      in
      {
        diff.tool = "difftastic";
        difftool = {
          prompt = false;
          difftastic.cmd = ''${difft} "$LOCAL" "$REMOTE"'';
        };
        pager.difftool = true;
        alias = {
          dft = "difftool";
          dlog = "!f() { GIT_EXTERNAL_DIFF='${difft}' git log -p --ext-diff $@; }; f";
        };
      };
  };
}
