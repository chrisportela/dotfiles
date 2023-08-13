{ lib, config, pkgs, ... }:
{
  imports = [ ];

  options = { };

  config = {
    networking.firewall.allowedTCPPorts = config.services.openssh.ports;

    services.openssh = {
      enable = true;

      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group-exchange-sha256"
          "ecdh-sha2-nistp256"
        ];
      };

      hostKeys = [
        {
          type = "rsa";
          bits = 4096;
          path = "/etc/ssh/ssh_host_rsa_key";
        }
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
        {
          type = "ecdsa";
          bits = 256;
          path = "/etc/ssh/ssh_host_ecdsa_key";
        }
      ];

      ports = [
        2222
      ];
    };
  };
}
