{ name, mkContainer }: mkContainer {
  inherit name;
  config = { pkgs, lib, config, ... }: {
    networking.hostName = "katara";

    #Postgresql
    services.postgresql = {
      enable = true;
      package = pkgs.postgresql_15;

      enableTCPIP = false;
      settings = {
        listen_addresses = lib.mkForce "";
        max_connections = 20;
        ssl = "off";
      };

      ensureUsers = [
        {
          name = "nextcloud";
          ensurePermissions = {
            "DATABASE nextcloud" = "ALL PRIVILEGES";
          };
        }
        {
          name = "vaultwarden";
          ensurePermissions = {
            "DATABASE vaultwarden" = "ALL PRIVILEGES";
          };
        }
        {
          name = "admin";
          ensurePermissions = {
            "ALL TABLES IN SCHEMA public" = "ALL PRIVILEGES";
          };
        }
      ];

      ensureDatabases = [
        "nextcloud"
        "vaultwarden"
      ];
    };

    # Bitwarden (vault warden)
    services.vaultwarden = {
      enable = true;
      dbBackend = "postgresql";
      config = {
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = "8222";
        DATABASE_URL = "postgresql:///vaultwarden";
      };
    };

    # Nextcloud
    services.nextcloud = {
      enable = true;
      package = pkgs.nextcloud27;
      hostName = "localhost";
      config.adminpassFile = "/var/run/nextcloud/adminpass.secret";
    };

    services.vault-agent.instances.nextcloud = {
      user = "nextcloud";
      group = "nextcloud";
      enable = true;
      settings = {
        vault = {
          address = "http://127.0.0.1:8200";
          retry = {
            num_retries = 5;
          };
        };
        cache = { };
        template = [
          {
            source = "${pkgs.writeText "adminsecret.ctmpl" ''
                            {{ with secret "nextcloud" }}
                            {{ .Data.data.adminpass }}
                            {{ end }}
                          ''}";
            destination = "/var/run/nextcloud/adminpass.secret";
          }
        ];
      };

    };

    security.acme.acceptTerms = true;
    security.acme.defaults.email = "chris+acme@chrisportela.com";
    services.nginx.virtualHosts."bitwarden.liara.i.cafecito.cloud" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.vaultwarden.config.ROCKET_PORT}";
      };
    };
  };
}
