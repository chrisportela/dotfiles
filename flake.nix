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
        overlays = [ ];
      });

      # Helper to provide system-specific attributes
      forEachSystem = systems: f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = (import nixpkgs { inherit system; });
      });

      forAllSystems = forEachSystem allSystems;
      forAllLinuxSystems = forEachSystem linuxSystems;
      forAllDarwinSystems = forEachSystem darwinSystems;

      homeConfig = ({ pkgs
                    , home ? ./home/default.nix
                    , username ? "cmp"
                    , allowUnfree ? [ ]
                    , options ? { }
                    }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ({ pkgs, lib, ... }: {
              home.username = username;
              nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowUnfree;
            })
            home
            options
          ];
        });
    in
    {
      lib = {
        inherit allSystems importPkgs forAllSystems forAllDarwinSystems forAllLinuxSystems;
      };

      packages = forAllSystems ({ pkgs, system }: rec {
        hush = pkgs.callPackage ./pkgs/hush-shell.nix {
          src = inputs.hush;
        };

        default = self.legacyPackages.${system}.homeConfigurations.cmp.activationPackage;
      });

      legacyPackages = ((nixpkgs.lib.foldl (a: b: nixpkgs.lib.recursiveUpdate a b) { }) [
        (forAllSystems ({ pkgs, system }: {
          homeConfigurations = {
            "cmp" = homeConfig {
              inherit pkgs;

              allowUnfree = [ "vault" ];
            };
            "cmp@ada" = homeConfig {
              inherit pkgs;

              allowUnfree = [
                "vault"
                "vscode"
                "discord"
                "obsidian"
                "cider"
              ];

              options = { pkgs, lib, ... }: {
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
        }))
        (forAllLinuxSystems ({ pkgs, system }: {
          installer-iso = self.nixosConfigurations.installer.config.formats.iso;
        }))
      ]);

      overlays = {
        deploy-rs = (final: prev: {
          deploy-rs = inputs.deploy-rs.defaultPackage.${final.stdenv.system};
        });
        hush = (final: prev: {
          hush = self.packages.${final.stdenv.system}.hush;
        });
      };

      homeConfigurations = {
        "deck@steamdeck" = homeConfig {
          username = "deck";
          pkgs = importPkgs "x86_64-linux";
        };
      };

      nixosModules = (import ./lib/nixos/modules/default.nix);

      nixosConfigurations = {
        installer = (import ./lib/nixos/configurations/installer.nix) { inherit inputs; };
        builder = (import ./lib/nixos/configurations/builder.nix) {
          nixpkgs = inputs.nixpkgs;
          nixosModules = self.nixosModules;
        };
        ada = (import ./lib/nixos/configurations/ada.nix) {
          inherit inputs;
          nixosModules = self.nixosModules;
        };
      };

      darwinModules = (import ./lib/darwin/default.nix);

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
            ./lib/darwin/configurations/mba.nix
          ];
        };
      };

      devShells = forAllSystems ({ pkgs, system }: {
        dotfiles = pkgs.mkShell {
          packages = (with pkgs; [
            cachix
            nixd
            nixpkgs-fmt
            shellcheck
            shfmt
          ]);
        };

        default = self.devShells.${system}.dotfiles;
      });

      checks = forAllSystems ({ pkgs, system }: {
        shell-functions =
          let
            script = ./home/shell_functions.sh;
          in
          pkgs.stdenvNoCC.mkDerivation {
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

