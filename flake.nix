{
  description = "Chris' scripts, dev shells, home-manager config, and nixOS configs";

  nixConfig = {
    extra-substituters = [ "https://chrisportela-dotfiles.cachix.org" ];
    extra-trusted-public-keys = [
      "chrisportela-dotfiles.cachix.org-1:e3UVWzLbmS6YLEUaY1BQt124GENPRF74YMgwV/6+Li4="
    ];
  };

  inputs = {
    nixos.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:nixos/nixpkgs/release-25.05";
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/master";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-25.05-darwin";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-unstable = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.05";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    nix-rosetta-builder = {
      url = "github:cpick/nix-rosetta-builder";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    agenix.url = "github:ryantm/agenix";
    deploy-rs.url = "github:serokell/deploy-rs";
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    rust-overlay.url = "github:oxalica/rust-overlay";
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # For installer target
    nixos-generators.url = "github:nix-community/nixos-generators";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      darwin,
      home-manager,
      home-manager-unstable,
      treefmt-nix,
      flake-utils,
      ...
    }:
    let
      importPkgs = (
        system:
        let
          overlays = with self.overlays; [
            rust
            rustToolchain
            deploy-rs
            terraform
          ];
          unfreePredicate = (
            pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "terraform"
              "vault-bin"
            ]
          );
        in
        rec {
          pkgsUnstable = import nixpkgs-unstable {
            inherit system overlays;
            config.allowUnfreePredicate = unfreePredicate;
          };
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfreePredicate = unfreePredicate;
            overlays = overlays ++ [
              (final: prev: {
                pkgsUnstable = pkgsUnstable;
              })
            ];
          };
        }
      );
    in
    (
      flake-utils.lib.eachDefaultSystem (
        system:
        let
          inherit (importPkgs system) pkgs pkgsUnstable;
          treefmt-eval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        in
        rec {
          apps = {
            cachix-helper = {
              type = "app";
              program = "${self.packages.${system}.cachix-helper}/bin/cachix-helper";
            };
          };
          packages = {
            terraform = pkgs.terraform.withPlugins (p: [
              p.cloudflare
              p.aws
              p.google
              p.google-beta
            ]);

            cachix-helper = pkgs.callPackage ./pkgs/cachix-helper.nix { };

            pi = inputs.nixos-generators.nixosGenerate {
              system = "aarch64-linux";
              format = "sd-aarch64";
              modules = [ ./lib/nixos/hardware/rpi4.nix ];
            };

            default = legacyPackages.homeConfigurations.cmp.activationPackage;
          };

          legacyPackages = {
            installer-iso = self.nixosConfigurations.installer.config.formats.iso;
            homeConfigurations = {
              cmp = home-manager-unstable.lib.homeManagerConfiguration {
                pkgs = pkgsUnstable;

                modules = [
                  ./home/modules/nixpkgs.nix
                  ./home/default.nix
                  {
                    allowedUnfree = [
                      "vault-bin"
                      "terraform"
                    ];
                    home.username = "cmp";
                  }
                ];
              };
              nixos = home-manager-unstable.lib.homeManagerConfiguration {
                pkgs = pkgsUnstable;

                modules = [
                  ./home/modules/nixpkgs.nix
                  ./home/default.nix
                  {
                    allowedUnfree = [
                      "vault-bin"
                      "terraform"
                    ];
                    home.username = "nixos";
                  }
                ];
              };
            };
          };

          devShells = (
            let
              pkgs = import nixpkgs {
                inherit system;
                overlays = with self.overlays; [
                  rust
                  rustToolchain
                  deploy-rs
                  terraform
                  (final: prev: {
                    pkgsUnstable = inputs.nixpkgs-unstable.legacyPackages.${system};
                    android-nixpkgs = inputs.android-nixpkgs;
                  })
                ];
                config.allowUnfreePredicate = (
                  pkg:
                  builtins.elem (nixpkgs.lib.getName pkg) [
                    "terraform"
                    "android-studio-stable"
                    "Xcode.app"
                  ]
                );
              };
            in
            rec {
              default = dotfiles;

              dotfiles = pkgs.callPackage ./shells/dotfiles.nix { };

              dev = pkgs.callPackage ./shells/dev.nix { };

              devops = pkgs.callPackage ./shells/devops.nix { };

              # TODO: Broken android and incorrect XCode setup
              react-native = pkgs.callPackage ./shells/react-native.nix { };
            }
          );
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
          inherit (importPkgs system) pkgs pkgsUnstable;
          simpleHomeConfig = (
            {
              pkgs,
              home-manager ? inputs.home-manager,
              username ? "cmp",
              options ? { },
            }:
            home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                ./home/modules/nixpkgs.nix
                ./home/default.nix
                {
                  allowedUnfree = [
                    "vault-bin"
                    "terraform"
                  ];
                  home.username = username;
                }
                options
              ];
            }
          );
        in
        {
          homeConfigurations = {
            "cmp@flamme" = simpleHomeConfig {
              pkgs = pkgsUnstable;
              home-manager = inputs.home-manager-unstable;
              options.chrisportela = {
                desktop = true;
                enableExtraPackages = true;
              };
            };
            "cmp@ada" = simpleHomeConfig {
              pkgs = pkgsUnstable;
              home-manager = inputs.home-manager-unstable;
              options.chrisportela = {
                desktop = true;
                enableExtraPackages = true;
              };
            };

            "deck@steamdeck" = simpleHomeConfig {
              inherit pkgs;
              home-manager = inputs.home-manager;
              username = "deck";
              options.chrisportela = {
                desktop = false;
                enableExtraPackages = false;
              };
            };
          };

          overlays = {
            rust = (import inputs.rust-overlay);

            # Provides a `rustToolchain` attribute for Nixpkgs that we can use to
            # create a Rust environment
            rustToolchain = (final: prev: { rustToolchain = prev.rust-bin.stable.latest.default; });

            deploy-rs = (final: prev: { deploy-rs = inputs.deploy-rs.defaultPackage.${final.stdenv.system}; });

            terraform = (final: prev: { terraformFull = self.packages.${final.stdenv.system}.terraform; });
          };

          nixosModules = (import ./lib/nixos/modules/default.nix);

          nixosConfigurations = {
            installer = (import ./lib/nixos/configurations/installer.nix) {
              inherit inputs self;
              nixos = inputs.nixos-unstable;
              nixpkgs = inputs.nixpkgs;
            };
            # builder = (import ./lib/nixos/configurations/builder.nix) {
            #   nixpkgs = inputs.nixpkgs;
            #   nixosModules = self.nixosModules;
            # };
            ada = (import ./lib/nixos/configurations/ada.nix) {
              inherit inputs;
              nixos = inputs.nixos-unstable;
              nixosModules = self.nixosModules;
            };
            flamme = (import ./lib/nixos/configurations/flamme.nix) {
              inherit inputs;
              nixos = inputs.nixos-unstable;
              nixosModules = self.nixosModules;
            };
          };

          darwinModules = {
            common = ./lib/darwin/common.nix;
            nixpkgs = ./lib/darwin/nixpkgs.nix;
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
                  nodeOverlay
                ];
                nixpkgs = inputs.nixpkgs-darwin;
              };
              modules = with self.darwinModules; [
                common
                ./lib/darwin/configurations/mba.nix
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
                nixpkgs = inputs.nixpkgs-darwin.extend (
                  final: prev:
                  let
                    unstable = inputs.nixpkgs-unstable."aarch64-darwin".legacyPackages;
                  in
                  {
                    nodejs = unstable.nodejs;
                  }
                );
              };
              modules = with self.darwinModules; [
                common
                ./lib/darwin/configurations/mba.nix
                { ids.gids.nixbld = 350; }
                # { nix.linux-builder.enable = true; }
                inputs.nix-rosetta-builder.darwinModules.default
                {
                  nix-rosetta-builder = {
                    enable = true;
                    onDemand = true;
                    # onDemandLingerMinutes = 180;
                  };
                }
                {
                  nixpkgs.overlays = [
                    (final: prev: {
                      nodejs = inputs.nixpkgs-unstable.legacyPackages.aarch64-darwin.nodejs_20;
                    })
                  ];
                  nix = {
                    registry.nixpkgs.flake = inputs.nixpkgs-darwin;
                    registry.nixos.flake = inputs.nixos;
                    registry.nixos-unstable.flake = inputs.nixos-unstable;
                    registry.nixpkgs-unstable.flake = inputs.nixpkgs-unstable;

                    nixPath = [
                      "nixpkgs=${inputs.nixpkgs-darwin}"
                      "nixos=${inputs.nixos}"
                      "nixpkgs-unstable=${inputs.nixpkgs-unstable}"
                      "nixos-unstable=${inputs.nixos-unstable}"
                      "/nix/var/nix/profiles/per-user/root/channels"
                    ];
                  };
                }
              ];
            };
          };
        }
      ))
    );
}
