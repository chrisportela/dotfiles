({ config, pkgs, ... }: {
  imports = [ ./lib/nixos/base-darwin.nix ];

  # nixpkgs.config.allowUnfree = true;

  nix = {
    distributedBuilds = true;
    configureBuildUsers = true;
    settings = {
      sandbox = "relaxed";
      trusted-users = [ "cmp" ];
      experimental-features = [ "nix-command" "flakes" ];
      extra-platforms = [ "aarch64-darwin" ];
      keep-outputs = true;
      keep-derivations = true;
    };
    buildMachines = [
      {
        systems = [ "x86_64-linux" "aarch64-linux" ];
        sshUser = "cmp";
        maxJobs = 20;
        hostName = "nix-builder";
        speedFactor = 10;
        supportedFeatures = [ ];
      }
    ];
  };

  services.nix-daemon.enable = true;
  users.knownGroups = [ "nixbld" ];

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

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 4;
})
