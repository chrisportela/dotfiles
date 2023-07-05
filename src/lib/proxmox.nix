{
  mkContainer = { name, config, modulesPath, nixosGenerate, nixpkgs_overlay, system ? "x86_64-linux" }: nixosGenerate {
    inherit system;

    modules = [
      ({ lib, pkgs, modulesPath, ... }: {
        imports = [
          ./neovim.nix
        ];

        boot.kernelParams = [ "console=/dev/console" ];

        security.sudo.wheelNeedsPassword = false;

        services.getty.autologinUser = lib.mkForce "admin";
        users.users.admin = {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
        };

        system.stateVersion = "23.11";
      })
      config
    ];

    format = "proxmox-lxc";
  };
}
