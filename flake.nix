{
  description = "My Home Manager flake";

  nixConfig = {
    extra-substituters = [ "https://chrisportela.cachix.org" ];
    extra-trusted-public-keys = [ "chrisportela.cachix.org-1:pynxY+k9+yz8noyGAYjfqkZMO5zkVauwcBwEoD3tkZk=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-23.11-darwin";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hush = {
      url = "github:hush-shell/hush";
      flake = false;
    };
    deploy-rs.url = "github:serokell/deploy-rs";
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { self, nixpkgs, darwin, home-manager, ... }:
    let
      linuxSystems = [
        "x86_64-linux" # 64-bit Intel/AMD Linux
        "aarch64-linux" # 64-bit ARM Linux
      ];
      darwinSystems = [
        "x86_64-darwin" # 64-bit Intel macOS
        "aarch64-darwin" # 64-bit ARM macOS
      ];
      # Systems supported
      allSystems = linuxSystems ++ darwinSystems;

      importPkgs = (system: import nixpkgs {
        inherit system;
        overlays = [ deploy_rs_overlay hush_overlay ];
      });

      # Helper to provide system-specific attributes
      forEachSystem = systems: f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = (importPkgs system);
      });

      forAllSystems = forEachSystem allSystems;
      forAllLinuxSystems = forEachSystem linuxSystems;
      forAllDarwinSystems = forEachSystem darwinSystems;

      homeConfig = ({ home ? ./home/default.nix, username ? "cmp", pkgs, options ? { } }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            { home.username = username; }
            # self.nixosModules.pinned_nixpkgs
            # self.nixosModules.deploy_rs
            home
            options
          ];
        });

      deploy_rs_overlay = (final: prev: { deploy-rs = inputs.deploy-rs.defaultPackage.${final.stdenv.system}; });
      hush_overlay = (final: prev: { hush = self.packages.${final.stdenv.system}.hush; });
    in
    {
      lib = {
        inherit allSystems importPkgs forAllSystems forAllDarwinSystems forAllLinuxSystems;
      };

      defaultPackage = forAllSystems ({ pkgs, system }: self.legacyPackages.${system}.default);

      packages = forAllSystems ({ pkgs, system }: rec {
        hush = pkgs.callPackage ./pkgs/hush-shell.nix { inherit inputs; };
      });

      legacyPackages = ((nixpkgs.lib.foldl (a: b: nixpkgs.lib.recursiveUpdate a b) { }) [
        (forAllSystems ({ pkgs, system }:
          let
            hm_cmp = (homeConfig { inherit pkgs; });
          in
          {
            homeConfigurations = {
              "cmp" = hm_cmp;
              "cmp@ada" = homeConfig {
                inherit pkgs;
                options = { pkgs, lib, ... }: {
                  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
                    "vscode"
                    "discord"
                    "obsidian"
                    "cider"
                  ];
                  nixpkgs.config.permittedInsecurePackages = [
                    "electron-25.9.0"
                  ];
                  programs = {
                    vscode.enable = true;
                    chromium.enable = true;
                  };
                  home.packages = with pkgs; [
                    trayscale
                    discord
                    obsidian
                    cider
                    signal-desktop
                    onlyoffice-bin_latest
                    sqlitebrowser
                    jrnl
                  ];
                  home.shellAliases = {
                    "cb" = "${pkgs.nodePackages.clipboard-cli}/bin/clipboard";
                  };
                };
              };
            };

            default = hm_cmp.activationPackage;
          }))
        (forAllLinuxSystems ({ pkgs, system }: {
          installer = (pkgs.callPackage ./lib/installer.nix {
            inherit system;
            nixosGenerate = inputs.nixos-generators.nixosGenerate;
            pinned_nixpkgs = self.nixosModules.pinned_nixpkgs;
          });
        }))
      ]);

      overlays = {
        deploy-rs = deploy_rs_overlay;
        hush = hush_overlay;
      };

      nixosModules = (import ./lib/nixos/default.nix);
      darwinModules = (import ./lib/darwin/default.nix);

      homeConfigurations = {
        "deck@steamdeck" = homeConfig { username = "deck"; pkgs = importPkgs "x86_64-linux"; };
      };

      nixosConfigurations = {
        builder = (import ./hosts/builder.nix) {
          inherit inputs;
          nixosModules = self.nixosModules;
          overlays = with self.overlays; [ deploy-rs hush ];
        };
        ada = (import ./hosts/ada.nix) {
          inherit inputs;
          nixosModules = self.nixosModules;
          overlays = with self.overlays; [ deploy-rs hush ];
        };
      };

      darwinConfigurations = {
        lux = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = {
            inherit inputs;
            overlays = with self.overlays; [ deploy-rs hush ];
            nixpkgs = inputs.nixpkgs;
          };
          modules = with self.darwinModules; [
            common
            ./hosts/mba.nix
          ];
        };
      };

      devShells = forAllSystems ({ pkgs, system }: {
        dotfiles = pkgs.mkShell {
          packages = (with pkgs; [
            cachix
            nixVersions.nix_2_16
            nixpkgs-fmt
            shfmt
            shellcheck
          ]);
        };

        default = self.devShells.${system}.dotfiles;
      });

      checks = forAllSystems ({ pkgs, system }: {
        shell-functions = let script = ./home/shell_functions.sh; in pkgs.stdenvNoCC.mkDerivation {
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

