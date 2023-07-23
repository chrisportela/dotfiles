{ name, mkContainer }: mkContainer {
  inherit name;
  config = { pkgs, lib, ... }: {
    networking.hostName = "lucy";

    services.vault = {
      enable = true;
      address = "0.0.0.0:8200";

      extraConfig = ''
        disable_mlock = true

        api_addr = "http://0.0.0.0:8200"
        cluster_addr = "http://0.0.0.0:8201"
        ui = true
      '';

      storageBackend = "file";
    };

    # TODO: Nginx service

    users.users.admin.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBPiggx+I4oYlNW9nWX6TG91k0pqpHAF/dkB9tCh+Ppf cmp@nix"
    ];
  };
}
