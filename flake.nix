{
  description = "My Home Manager flake";

  nixConfig = {
    extra-substituters = [ "https://chrisportela.cachix.org" ];
    extra-trusted-public-keys = [ "chrisportela.cachix.org-1:pynxY+k9+yz8noyGAYjfqkZMO5zkVauwcBwEoD3tkZk=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-22_05.url = "github:nixos/nixpkgs/nixos-22.05-aarch64";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-22.05-darwin";
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

  outputs = { nixpkgs, darwin, home-manager, ... } @inputs:
    let
      # Overlays enable you to customize the Nixpkgs attribute set
      overlays = [
        (self: super:
          let
            system = self.stdenv.system;
          in
          {
            pkgs_2205 = inputs.nixpkgs-22_05.legacyPackages.${system};
            pkgs_aarch64 = import nixpkgs {
              system = "aarch64-${builtins.head (builtins.match ".+-([[:lower:]]+)" system)}";
            };
            pkgs_x86_64 = nixpkgs.legacyPackages.${"x86_64-${builtins.head (builtins.match ".+-([[:lower:]]+)" system)}"};
            pkgs_darwin = inputs.nixpkgs-darwin { inherit system; };
          })
      ];

      # Systems supported
      allSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];

      importPkgs = (system: import nixpkgs { inherit overlays system; });

      # Helper to provide system-specific attributes
      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system: f {
        pkgs = (importPkgs system);
      });

    in
    rec {
      inherit allSystems importPkgs forAllSystems home-manager;

      overlays = { };

      packages = forAllSystems
        ({ pkgs }: rec {
          hush = pkgs.rustPlatform.buildRustPackage rec {
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
          home-mba = homeConfigurations."cmp@cp-mba".activationPackage;
          home-rs2 = homeConfigurations."cmp@rs2".activationPackage;
          home-deck = homeConfigurations."deck@steamdeck".activationPackage;
          home-nixserver = homeConfigurations."cmp@nix".activationPackage;
          all = pkgs.symlinkJoin {
            name = "all";
            paths = [ home-mba home-rs2 home-deck home-nixserver ];
          };
          default = all;
        });

      generators = {
        vm-install-iso = inputs.nixos-generators.nixosGenerate {
          system = "aarch64-linux";
          modules = [
            nixosModules.nixpkgs_overlay
            inputs.vscode-server.nixosModule
            ./src/machines/vm/configuration.nix
          ];
          format = "install-iso";
        };
      };

      checks = forAllSystems ({ pkgs }: {
        shell-functions = pkgs.stdenvNoCC.mkDerivation {
          name = "shell-functions-check";
          dontBuild = true;
          src = ./src/common/shell_functions.sh;
          nativeBuildInputs = with pkgs; [ alejandra shellcheck shfmt ];
          checkPhase = ''
            shfmt -d -s -i 2 -ci ${./src/common/shell_functions.sh}
            alejandra -c .
            shellcheck -x ${./src/common/shell_functions.sh}
          '';
          installPhase = ''
            mkdir "$out"
          '';
        };
      });

      homeConfigurations = {
        "cmp@cp-mba" = home-manager.lib.homeManagerConfiguration {
          pkgs = importPkgs "aarch64-darwin";

          modules = [
            nixosModules.nixpkgs_overlay
            nixosModules.deploy_rs_overlay
            ./src/machines/mba/home.nix
          ];
        };
        "cmp@rs2" = home-manager.lib.homeManagerConfiguration {
          pkgs = importPkgs "x86_64-linux";

          modules = [
            nixosModules.nixpkgs_overlay
            nixosModules.deploy_rs_overlay
            ./src/machines/server/home.nix
          ];
        };
        "cmp@nix" = home-manager.lib.homeManagerConfiguration {
          pkgs = importPkgs "x86_64-linux";

          modules = [
            nixosModules.nixpkgs_overlay
            nixosModules.deploy_rs_overlay
            ./src/machines/server/home.nix
          ];
        };
        "deck@steamdeck" = home-manager.lib.homeManagerConfiguration {
          pkgs = importPkgs "x86_64-linux";

          modules = [
            nixosModules.nixpkgs_overlay
            nixosModules.deploy_rs_overlay
            ./src/machines/steamdeck/home.nix
          ];
        };
      };

      nixosModules = {
        nixpkgs_overlay = ({ config, pkgs, ... }: { nix.registry.nixpkgs.flake = nixpkgs; });
        deploy_rs_overlay = { ... }: {
          nixpkgs.overlays = [
            (self: super: {
              deploy-rs = inputs.deploy-rs.defaultPackage.${self.stdenv.system};
            })
          ];
        };
        hush = ({ pkgs, config, ... }: {
          nixpkgs.overlays = [
            (self: super: {
              hush = packages.${self.stdenv.system}.hush;
            })
          ];
        });
      };

      darwinConfigurations = {
        "cp-mba" = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          modules = [
            nixosModules.nixpkgs_overlay
            ./src/machines/mba/configuration.nix
          ];
        };
      };

      nixosConfigurations = {
        "nix" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            nixosModules.nixpkgs_overlay
            inputs.vscode-server.nixosModule
            ./src/machines/server/configuration.nix
          ];
        };
      };

      devShells = forAllSystems ({ pkgs }: {
        default = pkgs.mkShell {
          # The Nix packages provided in the environment
          packages = (with pkgs; [
            cachix
            nixVersions.nix_2_14
            nixpkgs-fmt
            shfmt
            shellcheck
            packages.${pkgs.stdenv.system}.hush
          ]) ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ ]);
        };
      });
    };
}
