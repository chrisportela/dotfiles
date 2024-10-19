{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.chrisportela.ftp;
in
{
  options.chrisportela.ftp = {
    enable = mkEnableOption "Sony camera FTP server";

    port = mkOption {
      type = types.port;
      default = 21;
      description = "Port on which the FTP server will listen";
    };

    user = mkOption {
      type = types.str;
      default = "ftpuser";
      description = "Username for FTP access";
    };

    group = mkOption {
      type = types.str;
      default = "ftpuser";
      description = "Group name for FTP access";
    };

    directory = mkOption {
      type = types.str;
      example = "/home/ftpuser/photo-dump";
      description = "Directory where photos will be stored";
    };

    domain = mkOption {
      type = types.str;
      example = "ftp.example.com";
      description = "Domain name for the FTP server";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group for FTP access
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      # home = cfg.directory;
      createHome = true;
    };
    users.groups.${cfg.group} = { };

    # Set up vsftpd FTP server
    services.vsftpd = {
      enable = true;
      writeEnable = true;
      localUsers = true;
      extraConfig = ''
        listen_port=${toString cfg.port}
        local_root=${cfg.directory}
        pasv_min_port=50000
        pasv_max_port=51000
        ssl_enable=YES
        allow_anon_ssl=NO
        force_local_data_ssl=YES
        force_local_logins_ssl=YES
        ssl_tlsv1=YES
        ssl_sslv2=NO
        ssl_sslv3=NO
        require_ssl_reuse=NO
        ssl_ciphers=HIGH
        rsa_cert_file=/var/lib/acme/${cfg.domain}/fullchain.pem
        rsa_private_key_file=/var/lib/acme/${cfg.domain}/key.pem
      '';
    };

    # Set up ACME for TLS certificates
    security.acme.certs.${cfg.domain} = {
      domain = cfg.domain;
      group = "vsftpd";
    };

    # Open firewall ports for FTP and passive mode
    networking.firewall = {
      allowedTCPPorts = [ cfg.port 50000 51000 ];
    };

    # Ensure the photo dump directory exists and has correct permissions
    system.activationScripts.createFtpDirectory = ''
      mkdir -p ${cfg.directory}
      chown ${cfg.user}:${cfg.group} ${cfg.directory}
      chmod 755 ${cfg.directory}
    '';
  };
}
