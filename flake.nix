{
  description = "My Home Manager flake";

  nixConfig = {
    extra-substituters = [ "https://chrisportela.cachix.org" ];
    extra-trusted-public-keys = [ "chrisportela.cachix.org-1:pynxY+k9+yz8noyGAYjfqkZMO5zkVauwcBwEoD3tkZk=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-23.05-darwin";
    nixos-23_05.url = "github:nixos/nixpkgs/nixos-23.05";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    vscode-server = {
      url = "github:msteen/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hush = {
      url = "github:hush-shell/hush";
      flake = false;
    };
    deploy-rs.url = "github:serokell/deploy-rs";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, nixpkgs, darwin, home-manager, ... }:
    let
      # Systems supported
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux

        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      importPkgs = (system: import nixpkgs {
        inherit system; overlays = [ cross_pkgs_overlay deploy_rs_overlay hush_overlay ];
      });

      # Helper to provide system-specific attributes
      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system: f {
        inherit system;
        pkgs = (importPkgs system);
      });

      homeConfig = ({ home, username ? "cmp", pkgs }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            { home.username = username; }
            nixosModules.pinned_nixpkgs
            nixosModules.deploy_rs
            home
          ];
        });

      cross_pkgs_overlay = (final: prev:
        let
          system = final.stdenv.system;
          osName = builtins.head (builtins.match ".+-([[:lower:]]+)" system);
        in
        {
          pkgs-23_05 = import inputs.nixos-23_05 { inherit system; };
          pkgs-aarch64 = import nixpkgs { system = "aarch64-${osName}"; };
          pkgs-x86_64 = import nixpkgs { system = "x86_64-${osName}"; };
          pkgs-darwin = import inputs.nixpkgs-darwin { inherit system; };
        });

      deploy_rs_overlay = (final: prev: { deploy-rs = inputs.deploy-rs.defaultPackage.${final.stdenv.system}; });
      hush_overlay = (final: prev: { hush = self.packages.${final.stdenv.system}.hush; });

      nixosModules = {
        pinned_nixpkgs = ({ config, pkgs, ... }: { nix.registry.nixpkgs.flake = nixpkgs; });
        deploy_rs = { ... }: { nixpkgs.overlays = [ deploy_rs_overlay ]; };
        hush = ({ pkgs, config, ... }: { nixpkgs.overlays = [ hush_overlay ]; });
      };
    in
    {
      inherit allSystems importPkgs forAllSystems home-manager nixosModules;

      packages = forAllSystems
        ({ pkgs, system }: {
          hush = pkgs.rustPlatform.buildRustPackage {
            pname = "hush";
            version = "0.1.5a";

            src = inputs.hush;

            cargoSha256 = "sha256-0WYC4ScLNYE1jKEfWeYaBeY1Zl+gQa1Wl7xJK0CI8+I=";

            doCheck = false;

            meta = with pkgs.lib; {
              description = "Hush shell";
              homepage = "https://github.com/hush-shell/hush";
              license = licenses.mit;
              maintainers = [ ];
            };
          };
        }) // {
        x86_64-linux =
          let
            inherit (importPkgs system) callPackage;
            inherit (inputs.nixos-generators) nixosGenerate;
            inherit (nixosModules) pinned_nixpkgs;
            system = "x86_64-linux";
            mkContainer = { name ? "base", config }: (import ./src/lib/nixos/proxmox.nix).mkContainer { inherit system name config inputs pinned_nixpkgs; };
          in
          {
            installer = (callPackage ./src/lib/nixos/installer.nix { inherit system nixosGenerate pinned_nixpkgs; });
            infraServicesContainer = (import ./src/lib/nixos/containers/infra-services.nix) { inherit mkContainer; name = "infra-services"; };
            servicesContainer = (import ./src/lib/nixos/containers/services.nix) { inherit mkContainer; name = "services"; };
          };
      };

      overlays = {
        cross_nixpkgs = cross_pkgs_overlay;
        deploy-rs = deploy_rs_overlay;
        hush = hush_overlay;
      };

      homeConfigurations = {
        "cmp@cp-mba" = homeConfig { pkgs = importPkgs "aarch64-darwin"; home = ./src/home.nix; };
        "deck@steamdeck" = homeConfig { username = "deck"; pkgs = importPkgs "x86_64-linux"; home = ./src/home.nix; };
      } // forAllSystems ({ pkgs, system }: { "cmp" = homeConfig { inherit pkgs; home = ./src/home.nix; }; });

      darwinConfigurations = {
        "cp-mba" = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          # pkgs = pkgs-darwin;
          pkgs = (import inputs.nixpkgs-darwin) {
            overlays = [ self.overlays.cross_nixpkgs ];
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
          modules = [
            self.nixosModules.pinned_nixpkgs
            ./src/mba.nix
          ];
        };
      };

      nixosConfigurations = {
        #   "nix" = nixpkgs.lib.nixosSystem {
        #     system = "x86_64-linux";
        #     modules = [
        #       self.nixosModules.nixpkgs_overlay
        #       inputs.vscode-server.nixosModule
        #       ./src/configuration.nix
        #     ];
        #   };
      };

      devShells = forAllSystems ({ pkgs, system }: {
        default = self.devShells.${system}.dotfiles;
        dotfiles = pkgs.mkShell {
          # The Nix packages provided in the environment
          packages = (with pkgs; [
            cachix
            nixVersions.nix_2_14
            nixpkgs-fmt
            shfmt
            shellcheck
          ]) ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ ]);
        };
      });

      checks = forAllSystems ({ pkgs, system }: {
        shell-functions = let script = ./src/lib/home/shell_functions.sh; in pkgs.stdenvNoCC.mkDerivation {
          name = "shell-functions-check";
          dontBuild = true;
          src = script;
          nativeBuildInputs = with pkgs; [ alejandra shellcheck shfmt ];
          unpackPhase = ":";
          checkPhase = ''
            shfmt -d -s -i 2 -ci ${script}
            alejandra -c .
            shellcheck -x ${script}
          '';
          installPhase = ''
            mkdir "$out"
          '';
        };
      });
    };
}

