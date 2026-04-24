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
          "mlkem768x25519-sha256" # Post-quantum hybrid (OpenSSH 9.9+)
          "sntrup761x25519-sha512" # Post-quantum hybrid (OpenSSH 9.0+)
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
        ];
        Ciphers = [
          "chacha20-poly1305@openssh.com"
          "aes256-gcm@openssh.com"
          "aes128-gcm@openssh.com"
        ];
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
        ];
      };

      hostKeys = [
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];

      ports = lib.mkDefault [ 2222 ];
    };
  };
}
