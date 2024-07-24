# Provides opinionated secure defaults for SSH Config
{ config, lib, ... }:
let
  cfg = config.services.openssh;
in
{
  options.services.openssh = { };
  config = {
    services.openssh = {
      enable = lib.mkDefault true;

      settings = {
        PermitRootLogin = lib.mkDefault "no";
        PasswordAuthentication = lib.mkDefault false;
        KexAlgorithms = [
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
          "diffie-hellman-group-exchange-sha256"
          "ecdh-sha2-nistp256"
        ];
      };

      hostKeys = [
        { type = "rsa"; bits = 4096; path = "/etc/ssh/ssh_host_rsa_key"; }
        { type = "ed25519"; path = "/etc/ssh/ssh_host_ed25519_key"; }
        { type = "ecdsa"; bits = 256; path = "/etc/ssh/ssh_host_ecdsa_key"; }
      ];

      ports = lib.mkDefault [ 2222 ];
    };
  };
}
