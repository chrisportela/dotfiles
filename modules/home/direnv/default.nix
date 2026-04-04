{
  config,
  lib,
  ...
}:
let
  pluginsCfg = config.chrisportela.direnv.plugins;

  # Substitute the credentials file path into the plane.sh template
  planeScript = builtins.replaceStrings
    [ "@credentialsFile@" ]
    [ pluginsCfg.plane.credentialsFile ]
    (builtins.readFile ./lib/plane.sh);
in
{
  options.chrisportela.direnv.plugins = {
    postgres = {
      enable = lib.mkEnableOption "layout_postgres direnv library function";
    };

    plane = {
      enable = lib.mkEnableOption "use_plane direnv library function";

      credentialsFile = lib.mkOption {
        type = lib.types.str;
        default = "~/.config/plane/env";
        description = "Path to file containing PLANE_API_KEY, PLANE_BASE_URL, PLANE_WORKSPACE_SLUG defaults.";
      };
    };
  };

  config = {
    assertions = [
      {
        assertion = pluginsCfg.postgres.enable -> config.programs.direnv.enable;
        message = "chrisportela.direnv.plugins.postgres requires programs.direnv.enable = true";
      }
      {
        assertion = pluginsCfg.plane.enable -> config.programs.direnv.enable;
        message = "chrisportela.direnv.plugins.plane requires programs.direnv.enable = true";
      }
    ];

    xdg.configFile = lib.mkMerge [
      (lib.mkIf pluginsCfg.postgres.enable {
        "direnv/lib/postgres.sh".source = ./lib/postgres.sh;
      })
      (lib.mkIf pluginsCfg.plane.enable {
        "direnv/lib/plane.sh".text = planeScript;
      })
    ];
  };
}
