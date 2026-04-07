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
    virby = {
      url = "github:quinneden/virby-nix-darwin/be170bd7ef21ce9773e7daa646d43f5405a1bdb2";
      # url = "github:quinneden/virby-nix-darwin";
      # inputs.nixpkgs.follows = "nixpkgs";
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
          "cursor-agent"
          "xcode"
        ];

        overlays = [
          (final: prev: {
            ntfy-sh = nixpkgs.legacyPackages.${final.stdenv.system}.ntfy-sh;
          })
          (final: prev: {
            agenix = inputs.agenix.packages.${final.stdenv.system}.default;
          })
        ];
      };
      simpleHomeConfig = (import ./lib/simple-home-config.nix) inputs;
      supportedSystems = with flake-utils.lib.system; [
        x86_64-linux
        aarch64-linux
        aarch64-darwin
      ];
    in
    (
      flake-utils.lib.eachSystem supportedSystems (
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

          packages = builtins.foldl' (acc: attrs: acc // attrs) { } [
            {
              terraform = pkgs.callPackage ./pkgs/terraform/default.nix { };
              cachix-helper = pkgs.callPackage ./pkgs/cachix-helper.nix { };
              rmlint = pkgs.callPackage ./pkgs/rmlint.nix { };
              openclaw = pkgs.pkgsUnstable.callPackage ./pkgs/openclaw/default.nix {
                upstreamOpenclaw = nixpkgs-unstable.legacyPackages.${system}.openclaw;
              };
              opencode-cursor = pkgs.pkgsUnstable.callPackage ./pkgs/opencode-cursor/package.nix { };
              claude-code = pkgs.pkgsUnstable.callPackage ./pkgs/claude-code/package.nix { };
              cursor-agent = pkgs.pkgsUnstable.callPackage ./pkgs/cursor-agent/package.nix { };
              opencode = pkgs.pkgsUnstable.callPackage ./pkgs/opencode/package.nix {
                upstreamOpencode = nixpkgs-unstable.legacyPackages.${system}.opencode;
              };
              plane-mcp-server = pkgs.pkgsUnstable.callPackage ./pkgs/plane-mcp-server/default.nix { };
              setup-envrc = pkgs.callPackage ./pkgs/setup-envrc.nix { };
              update = pkgs.callPackage ./pkgs/update.nix { };
              wt = pkgs.callPackage ./pkgs/wt/default.nix { };
              pi = self.nixosConfigurations.rpi4.config.system.build.sdImage;
              default = legacyPackages.homeConfigurations.cmp.activationPackage;
            }
            (nixpkgs.lib.optionalAttrs (system == flake-utils.lib.system.aarch64-darwin) {
              cliclick = pkgs.callPackage ./pkgs/cliclick/default.nix { };
              peekaboo = pkgs.callPackage ./pkgs/peekaboo/default.nix { };
              peekaboo-git = pkgs.pkgsUnstable.callPackage ./pkgs/peekaboo/git.nix { };
              swift6 = pkgs.callPackage ./pkgs/swift6/default.nix { };
            })
          ];

          legacyPackages = {
            installer-iso = self.nixosConfigurations.installer.config.system.build.isoImage;
            homeConfigurations = builtins.foldl' (acc: attrs: acc // attrs) { } [
              {
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

              }
              (pkgs.lib.optionalAttrs (system == flake-utils.lib.system.x86_64-linux) {
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
                "cmp@ada" = simpleHomeConfig {
                  pkgs = pkgsUnstable;
                  home-manager = inputs.home-manager;
                  options.chrisportela = {
                    desktop.enable = true;
                    experiment.enable = true;
                    coding-agents.enable = true;
                    direnv.plugins = {
                      postgres.enable = true;
                      plane.enable = true;
                    };
                  };
                };
                "cmp@flamme" = simpleHomeConfig {
                  pkgs = pkgsUnstable;
                  home-manager = inputs.home-manager;
                  options.chrisportela = {
                    desktop.enable = true;
                    experiment.enable = true;
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
              })
              (pkgs.lib.optionalAttrs (system == flake-utils.lib.system.aarch64-darwin) {
                "cmp@roxy" = simpleHomeConfig {
                  pkgs = pkgsUnstable;
                  home-manager = inputs.home-manager;
                  options.chrisportela = {
                    coding-agents.enable = true;
                  };
                };
              })
            ];
          };

          devShells = rec {
            default = dotfiles;
            dotfiles = pkgs.callPackage ./shells/dotfiles.nix { };
            dev = pkgs.callPackage ./shells/dev.nix { };
            devops = pkgs.callPackage ./shells/devops.nix { };
          }
          // (nixpkgs.lib.optionalAttrs (system != flake-utils.lib.system.aarch64-linux) {
            react-native =
              let
                androidPkgs =
                  (importPkgs {
                    inherit
                      self
                      nixpkgs
                      nixpkgs-unstable
                      inputs
                      ;
                    config.android_sdk.accept_license = true;
                    allowUnfreePredicate = _: true;
                  } system).pkgs;
              in
              androidPkgs.pkgsUnstable.callPackage ./shells/react-native.nix {
                inherit (inputs) android-nixpkgs;
              };
          });

          devShell = devShells.default;
          formatter = treefmt-eval.config.build.wrapper;
          checks = {
            formatting = treefmt-eval.config.build.check self;
          };
        }
      )
      // {

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

        nixosConfigurations =
          let
            mkHost = (import ./lib/nixos-host.nix) {
              nixos = inputs.nixpkgs-unstable;
              nixosModules = [
                inputs.agenix.nixosModules.default
                inputs.disko.nixosModules.disko
                inputs.vscode-server.nixosModules.default
                self.nixosModules.default
              ];
              specialArgs = { inherit inputs; };
            };
          in
          {
            installer = (import ./hosts/nixos/installer.nix) {
              inherit inputs self;
              nixos = inputs.nixpkgs-unstable;
              nixpkgs = inputs.nixpkgs;
            };
            rpi4 = (import ./hosts/nixos/rpi4-image.nix) {
              inherit inputs self nixpkgs;
            };
            ada = mkHost {
              hostName = "ada";
              stateVersion = "25.05";
              overlays = [
                (final: prev: { rmlint = self.packages.x86_64-linux.rmlint; })
              ];
              hardwareConfig = ./hosts/nixos/ada/hardware.nix;
              config = ./hosts/nixos/ada;
            };
            flamme = mkHost {
              hostName = "flamme";
              stateVersion = "24.05";
              hardwareConfig = ./hosts/nixos/flamme/hardware.nix;
              config = ./hosts/nixos/flamme;
            };
          };

        darwinModules = {
          common = ./modules/darwin/common.nix;
          nixpkgs = ./modules/darwin/nixpkgs.nix;
          default = ./modules/darwin/default.nix;
        };

        darwinConfigurations =
          let
            inherit (importedPkgs "aarch64-darwin") pkgs pkgsUnstable;
          in
          {
            lux = darwin.lib.darwinSystem {
              system = "aarch64-darwin";
              specialArgs = {
                inherit inputs;
                overlays = with self.overlays; [
                  deploy-rs
                  rust
                  rustToolchain
                ];
                nixpkgs = pkgsUnstable;
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
                  (final: prev: {
                    ntfy-sh = pkgs.ntfy-sh;
                  })
                ];
                nixpkgs = pkgsUnstable;
              };
              modules = with self.darwinModules; [
                default
                ./hosts/darwin/mba.nix
                ./hosts/darwin/roxy.nix
                inputs.nix-rosetta-builder.darwinModules.default
                inputs.virby.darwinModules.default
                {
                  nix-rosetta-builder = {
                    enable = true;
                    onDemand = true;
                  };

                  services.virby = {
                    enable = true;
                    # supportDeterminateNix = false;
                    onDemand = {
                      enable = true;
                      # ttl = 180; # minutes
                    };
                    rosetta = true;
                    # debug = true;
                    # allowUserSsh = true;
                  };
                }
              ];
            };
          };
      }
    );
}
