{
  description = "Chris' scripts, dev shells, home-manager config, and nixOS configs";

  nixConfig = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://chrisportela-dotfiles.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "chrisportela-dotfiles.cachix.org-1:e3UVWzLbmS6YLEUaY1BQt124GENPRF74YMgwV/6+Li4="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      darwin,
      home-manager,
      treefmt-nix,
      flake-utils,
      microvm,
      ...
    }:
    let
      overlaysSet = (import ./overlays/default.nix) { inherit self inputs; };
      importPkgs = (import ./lib/import-pkgs.nix);
      importedPkgs = (import ./lib/import-pkgs.nix) {
        inherit
          self
          nixpkgs
          nixpkgs-unstable
          inputs
          ;

        allowUnfree = [
          "terraform"
          "vault-bin"
          "claude-code"
        ];
      };
    in
    (
      flake-utils.lib.eachDefaultSystem (
        system:
        let
          inherit (importedPkgs system) pkgs pkgsUnstable;
          treefmt-eval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        in
        rec {
          apps = {
            cachix-helper = {
              type = "app";
              program = "${self.packages.${system}.cachix-helper}/bin/cachix-helper";
            };
            update = {
              type = "app";
              program = "${self.packages.${system}.update}/bin/update";
            };
          };
          packages = {
            terraform = pkgs.callPackage ./pkgs/terraform/default.nix { };

            cachix-helper = pkgs.callPackage ./pkgs/cachix-helper.nix { };

            rmlint = pkgs.callPackage ./pkgs/rmlint.nix { };

            openclaw = pkgs.pkgsUnstable.callPackage ./pkgs/openclaw.nix {
              inherit (pkgs.pkgsUnstable) openclaw;
            };

            opencode-cursor = pkgs.pkgsUnstable.callPackage ./pkgs/opencode-cursor.nix { };

            claude-code = pkgs.pkgsUnstable.callPackage ./pkgs/claude-code/package.nix { };

            cliclick = pkgs.callPackage ./pkgs/cliclick/default.nix { };

            setup-envrc = pkgs.callPackage ./pkgs/setup-envrc.nix { };

            update = pkgs.callPackage ./pkgs/update.nix { };

            pi = self.nixosConfigurations.rpi4.config.system.build.sdImage;

            default = legacyPackages.homeConfigurations.cmp.activationPackage;
          };

          legacyPackages = {
            installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;
            homeConfigurations = {
              cmp = home-manager.lib.homeManagerConfiguration {
                pkgs = pkgsUnstable;

                modules = [
                  ./modules/home/nixpkgs.nix
                  ./modules/home/default.nix
                  {
                    allowedUnfree = [
                      "vault-bin"
                      "terraform"
                    ];
                    home.username = "cmp";
                  }
                ];
              };
              nixos = home-manager.lib.homeManagerConfiguration {
                pkgs = pkgsUnstable;

                modules = [
                  ./modules/home/nixpkgs.nix
                  ./modules/home/default.nix
                  {
                    allowedUnfree = [
                      "vault-bin"
                      "terraform"
                    ];
                    home.username = "nixos";
                    chrisportela.coding-agents.enable = true;
                  }
                ];
              };
            };
          };

          devShells = (
            let
              inherit (importedPkgs system) pkgs;
            in
            rec {
              default = dotfiles;

              dotfiles = pkgs.callPackage ./shells/dotfiles.nix { };

              dev = pkgs.callPackage ./shells/dev.nix { };

              devops = pkgs.callPackage ./shells/devops.nix { };

              react-native =
                let
                  pkgs =
                    (importPkgs {
                      inherit
                        self
                        nixpkgs
                        nixpkgs-unstable
                        inputs
                        ;

                      config = {
                        android_sdk.accept_license = true;
                      };

                      allowUnfreePredicate = pkg: true;
                    } system).pkgs;
                in
                pkgs.pkgsUnstable.callPackage ./shells/react-native.nix {
                  inherit (inputs) android-nixpkgs;
                };
            }
          );
          devShell = self.devShells.${system}.default;

          # for `nix fmt`
          formatter = treefmt-eval.config.build.wrapper;

          checks = {
            formatting = treefmt-eval.config.build.check self;
          };
        }
      )
      // (flake-utils.lib.eachDefaultSystemPassThrough (
        system:
        let
          inherit (importedPkgs system) pkgs pkgsUnstable;
          simpleHomeConfig = (import ./lib/simple-home-config.nix) inputs;
        in
        {
          homeConfigurations = {
            "cmp@flamme" = simpleHomeConfig {
              pkgs = pkgsUnstable;
              home-manager = inputs.home-manager;
              options.chrisportela = {
                desktop.enable = true;
                experiment.enable = true;
                coding-agents.enable = true;
              };
            };
            "cmp@ada" = simpleHomeConfig {
              pkgs = pkgsUnstable;
              home-manager = inputs.home-manager;
              options.chrisportela = {
                desktop.enable = true;
                experiment.enable = true;
                coding-agents.enable = true;
              };
            };
            "cmp@roxy" =
              let
                darwinPkgs = importedPkgs "aarch64-darwin";
              in
              simpleHomeConfig {
                pkgs = darwinPkgs.pkgsUnstable;
                home-manager = inputs.home-manager;
                options.chrisportela = {
                  coding-agents.enable = true;
                };
              };

            "deck@steamdeck" = simpleHomeConfig {
              inherit pkgs;
              home-manager = inputs.home-manager;
              username = "deck";
              options.chrisportela = {
                desktop.enable = false;
                experiment.enable = false;
                coding-agents.enable = false;
              };
            };
          };

          # Project templates: nix flake new <path> -t <flake>#<template>
          templates = {
            nextjs = {
              description = "Next.js + pnpm with TypeScript, Prisma 7, Better Auth, Vitest, Playwright";
              path = ./templates/nextjs;
            };
            react-native = {
              description = "React Native (bare) + pnpm with TypeScript, React Navigation, Jest";
              path = ./templates/react-native;
            };
          };

          overlays = overlaysSet;

          nixosModules = (import ./modules/nixos/default.nix);

          nixosConfigurations = {
            installer = (import ./hosts/nixos/installer.nix) {
              inherit inputs self;
              nixos = inputs.nixpkgs-unstable;
              nixpkgs = inputs.nixpkgs;
            };
            rpi4 = (import ./hosts/nixos/rpi4-image.nix) {
              inherit inputs self nixpkgs;
            };
            ada = (import ./hosts/nixos/ada/default.nix) {
              inherit inputs;
              nixos = inputs.nixpkgs-unstable;
              nixosModules = self.nixosModules;
              overlays = [
                (final: prev: { rmlint = self.packages.x86_64-linux.rmlint; })

              ];
            };
            flamme = (import ./hosts/nixos/flamme/default.nix) {
              inherit inputs;
              nixos = inputs.nixpkgs-unstable;
              nixosModules = self.nixosModules;
            };
          };

          darwinModules = {
            common = ./modules/darwin/common.nix;
            nixpkgs = ./modules/darwin/nixpkgs.nix;
            default = ./modules/darwin/default.nix;
          };

          darwinConfigurations = {
            lux = darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              specialArgs = {
                inherit inputs;
                overlays = with self.overlays; [
                  deploy-rs
                  rust
                  rustToolchain
                ];
                nixpkgs = inputs.nixpkgs-unstable;
              };
              modules = with self.darwinModules; [
                default
                ./hosts/darwin/mba.nix
                # { nix.linux-builder.enable = true; }
                inputs.nix-rosetta-builder.darwinModules.default
                {
                  nix-rosetta-builder = {
                    enable = true;
                    onDemand = true;
                    # onDemandLingerMinutes = 180;
                  };
                }
              ];
            };
            roxy = darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              specialArgs = {
                inherit inputs;
                overlays = with self.overlays; [
                  deploy-rs
                  rust
                  rustToolchain
                ];
                nixpkgs = inputs.nixpkgs-unstable.extend (
                  final: prev: {
                    nodejs = prev.nodejs.overrideAttrs (old: {
                      doCheck = false;
                    });
                  }
                );
              };
              modules = with self.darwinModules; [
                default
                ./hosts/darwin/mba.nix
                ./hosts/darwin/roxy.nix
                inputs.nix-rosetta-builder.darwinModules.default
                {
                  nix-rosetta-builder = {
                    enable = true;
                    onDemand = true;
                  };
                }
              ];
            };
          };
        }
      ))
    );
}
