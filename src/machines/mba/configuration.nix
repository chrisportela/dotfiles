({ config, pkgs, ... }: {
  nix.package = pkgs.nixFlakes;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
    builders-use-substitutes = true
  '';
  nix.distributedBuilds = true;
  nix.buildMachines = [
    {
      systems = [ "x86_64-linux" "aarch64-linux" ];
      sshUser = "builder";
      maxJobs = 20;
      hostName = "nix.gorgon-basilisk.ts.net";
      speedFactor = 100;
      supportedFeatures = [ "kvm" "big-parallel" "nixos-test" "benchmark" ];
    }
  ];
  nix.configureBuildUsers = true;
  nix.settings.trusted-users = [ "cmp" ];

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [ curl ];
  environment.variables = {
    EDITOR = "vim";
  };

  programs = {
    tmux = {
      enable = true;
      enableMouse = true;
      enableSensible = true;
    };

    zsh = {
      enable = true;
      enableBashCompletion = true;
      #enableCompletion = true;
      enableFzfCompletion = true;
      enableFzfGit = true;
      enableFzfHistory = true;
    };
  };
  services.nix-daemon.enable = true;
  users.knownGroups = [ "nixbld" ];

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
})
