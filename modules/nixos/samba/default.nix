{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.samba;

  # Resolve effective values per share, falling back to type defaults
  typeDefaults = {
    media = {
      readOnly = true;
      guest = true;
      browseable = true;
    };
    backup = {
      readOnly = false;
      guest = false;
      browseable = true;
    };
    public = {
      readOnly = false;
      guest = true;
      browseable = true;
    };
    private = {
      readOnly = false;
      guest = false;
      browseable = false;
    };
  };

  resolveShare = name: share:
    let
      defaults = typeDefaults.${share.type};
      readOnly = if share.readOnly != null then share.readOnly else defaults.readOnly;
      guest = if share.guest != null then share.guest else defaults.guest;
      browseable = defaults.browseable;
    in
    {
      path = share.path;
      "read only" = if readOnly then "yes" else "no";
      "guest ok" = if guest then "yes" else "no";
      browseable = if browseable then "yes" else "no";
    }
    // lib.optionalAttrs (share.users != [ ]) {
      "valid users" = lib.concatStringsSep " " share.users;
    }
    // lib.optionalAttrs guest {
      "force user" = "nobody";
    }
    // lib.optionalAttrs (share.type == "media") {
      "follow symlinks" = "yes";
      "wide links" = "yes";
      "allow insecure wide links" = "yes";
    }
    // lib.optionalAttrs (share.type == "public") {
      "create mask" = "0664";
      "directory mask" = "0775";
    }
    // lib.optionalAttrs (share.type == "backup" && share.timeMachine) {
      "vfs objects" = "fruit catia streams_xattr";
      "fruit:time machine" = "yes";
    }
    // share.extraConfig;

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

    services.samba = {
      enable = true;
      openFirewall = cfg.openFirewall;

      settings =
        {
          global =
            {
              "server role" = "standalone";
              "server min protocol" = "SMB2";
              "server max protocol" = "SMB3";
              "vfs objects" = "fruit catia streams_xattr";
              "fruit:metadata" = "stream";
              "fruit:model" = "MacSamba";
              "map to guest" = "Bad User";
              "load printers" = "no";
              printing = "bsd";
              "printcap name" = "/dev/null";
              "disable spoolss" = "yes";
              "unix charset" = "UTF-8";
              "dos charset" = "CP850";
              logging = "syslog";
              "log level" = "1";
            }
            // cfg.extraGlobalConfig;
        }
        // lib.mapAttrs resolveShare cfg.shares;
    };
  };
}
