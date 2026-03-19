{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.samba;

  shareSubmodule = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [ "media" "backup" "public" "private" ];
        description = "Share type. Sets default values for readOnly, guest, browseable, and extra smb.conf parameters.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        description = "Directory to share.";
      };

      readOnly = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Override read-only setting. Defaults: media=true, others=false.";
      };

      guest = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Allow guest access. Defaults: media/public=true, backup/private=false.";
      };

      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Restrict to specific users. Empty means all samba users. Required for private type.";
      };

      timeMachine = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Advertise as Time Machine target. Only valid for backup type.";
      };

      createDir = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create directory via tmpfiles. Set false for existing dirs you want to manage yourself.";
      };

      extraConfig = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Raw smb.conf parameters to merge into this share section.";
      };
    };
  };
in
{
  options.chrisportela.samba = {
    enable = lib.mkEnableOption "Samba file sharing";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users to create as Samba users. Passwords managed via agenix.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Agenix-decrypted file with user:password per line.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open Samba ports (TCP 445, 139; UDP 137, 138) in the firewall.";
    };

    extraGlobalConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional [global] smb.conf parameters.";
    };

    shares = lib.mkOption {
      type = lib.types.attrsOf shareSubmodule;
      default = { };
      description = "Named share definitions.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      [
        {
          assertion = cfg.passwordFile != null;
          message = "chrisportela.samba.passwordFile must be set when samba is enabled.";
        }
      ]
      ++ lib.mapAttrsToList (name: share: {
        assertion = share.type != "private" || share.users != [ ];
        message = "chrisportela.samba.shares.${name}: private shares must specify a non-empty users list.";
      }) cfg.shares
      ++ lib.mapAttrsToList (name: share: {
        assertion = !share.timeMachine || share.type == "backup";
        message = "chrisportela.samba.shares.${name}: timeMachine is only valid on backup type shares.";
      }) cfg.shares
      ++ lib.optional (lib.any (s: s.timeMachine) (lib.attrValues cfg.shares)) {
        assertion = config.chrisportela.network.mDNS;
        message = "chrisportela.network.mDNS must be enabled when any share has timeMachine = true.";
      };
  };
}
