{
  description = "Chris' scripts, dev shells, home-manager config, and nixOS configs";

  nixConfig = {
    extra-substituters = [ "https://chrisportela-dotfiles.cachix.org" ];
    extra-trusted-public-keys = [
      "chrisportela-dotfiles.cachix.org-1:e3UVWzLbmS6YLEUaY1BQt124GENPRF74YMgwV/6+Li4="
    ];
  };

  inputs = {
    nixos.url = "github:nixos/nixpkgs/nixos-24.11";
    nixpkgs.url = "github:nixos/nixpkgs/release-24.11";
    nixos-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/master";
    nixpkgs-darwin.url = "github:nixos/nixpkgs/nixpkgs-24.11-darwin";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager-unstable = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-24.11";
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
      darwin,
      home-manager,
      treefmt-nix,
      ...
    }:
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

      importPkgs = (
        system:
        import nixpkgs {
          inherit system;
        }
      );

      # Helper to provide system-specific attributes
      forEachSystem =
        {
          systems,
          overlays ? [ ],
          allowedUnfree ? [ ],
          nixpkgs ? inputs.nixpkgs,
          nixpkgs-unstable ? inputs.nixpkgs-unstable,
        }:
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          let
            nixpkgsOptions = {
              inherit system;
              overlays = nixpkgs.lib.unique (
                [
                  (self: super: {
                    haskellPackages = super.haskellPackages.override {
                      overrides = hself: hsuper: {
                        system-fileio = hsuper.system-fileio.overrideAttrs (_: {
                          doCheck = false;
                        });
                      };
                    };
                  })
                  self.overlays.terraform
                ]
                ++ overlays
              );

              config.allowUnfreePredicate = (
                pkg: builtins.elem (nixpkgs.lib.getName pkg) nixpkgs.lib.unique ([ "terraform" ] ++ allowedUnfree)
              );
            };
          in
          f {
            inherit system;
            pkgs = (import nixpkgs nixpkgsOptions);
            pkgsUnstable = (import nixpkgs-unstable nixpkgsOptions);
          }
        );

      forAllSystems = forEachSystem { systems = allSystems; };
      forAllLinuxSystems = forEachSystem { systems = linuxSystems; };
      forAllDarwinSystems = forEachSystem { systems = darwinSystems; };

      forAllSystemsShell =
        (
          systems: f:
          nixpkgs.lib.genAttrs systems (
            system:
            let
              nixpkgsOptions = {
                inherit system;
                overlays = with self.overlays; [
                  rust
                  rustToolchain
                  deploy-rs
                  terraform
                ];
                config.allowUnfreePredicate =
                  pkg:
                  builtins.elem (nixpkgs.lib.getName pkg) [
                    "terraform"
                    "android-studio-stable"
                    "Xcode.app"
                  ];
              };
            in
            f {
              inherit system;
              pkgs = (import nixpkgs nixpkgsOptions);
              pkgsUnstable = (import inputs.nixpkgs-unstable nixpkgsOptions);
            }
          )
        )
          allSystems;

      treefmtEval = forAllSystems (
        { system, ... }: treefmt-nix.lib.evalModule (nixpkgs.legacyPackages.${system}) ./treefmt.nix
      );

      homeConfig = (
        {
          pkgs,
          home ? ./home/default.nix,
          username ? "cmp",
          allowedUnfree ? [ ],
          options ? { },
          home-manager ? inputs.home-manager,
        }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ./home/modules/nixpkgs.nix
            {
              inherit allowedUnfree;
              home.username = username;
            }
            home
            options
          ];
        }
      );
    in
    {
      lib = {
        inherit
          allSystems
          importPkgs
          forAllSystems
          forAllDarwinSystems
          forAllLinuxSystems
          ;
      };

      apps = forAllSystems (
        { system, ... }:
        {
          cachix-helper = {
            type = "app";
            program = "${self.packages.${system}.cachix-helper}/bin/cachix-helper";
          };
        }
      );

      packages =
        forAllSystems (
          {
            pkgs,
            pkgsUnstable,
            system,
          }:
          {
            terraform = pkgsUnstable.terraformFull;

            cachix-helper = pkgs.callPackage ./pkgs/cachix-helper.nix { };

            default = self.legacyPackages.${system}.homeConfigurations.cmp.activationPackage;
          }
        )
        // {
          aarch64-linux = {
            pi = inputs.nixos-generators.nixosGenerate {
              system = "aarch64-linux";
              format = "sd-aarch64";
              modules = [ ./lib/nixos/hardware/rpi4.nix ];
            };
          };
        };

      legacyPackages = (
        (nixpkgs.lib.foldl (a: b: nixpkgs.lib.recursiveUpdate a b) { }) [
          (forAllSystems (
            { pkgs, pkgsUnstable, ... }:
            {
              homeConfigurations = {
                "cmp" = homeConfig {
                  pkgs = pkgsUnstable;
                  home-manager = inputs.home-manager-unstable;

                  allowedUnfree = [
                    "vault-bin"
                    "terraform"
                  ];
                };
                "cmp@flamme" = homeConfig {
                  pkgs = pkgsUnstable;
                  home-manager = inputs.home-manager-unstable;
                  options.chrisportela = {
                    desktop = true;
                    enableExtraPackages = true;
                  };
                };
                "cmp@ada" = homeConfig {
                  pkgs = pkgsUnstable;
                  home-manager = inputs.home-manager-unstable;
                  options.chrisportela = {
                    desktop = true;
                    enableExtraPackages = true;
                  };
                };
              };
            }
          ))
          (forAllLinuxSystems (
            { ... }:
            {
              installer-iso = self.nixosConfigurations.installer.config.formats.iso;
            }
          ))
        ]
      );

      overlays = {
        rust = (import inputs.rust-overlay);

        # Provides a `rustToolchain` attribute for Nixpkgs that we can use to
        # create a Rust environment
        rustToolchain = (
          final: prev: {
            rustToolchain = prev.rust-bin.stable.latest.default;
          }
        );

        deploy-rs = (
          final: prev: {
            deploy-rs = inputs.deploy-rs.defaultPackage.${final.stdenv.system};
          }
        );

        terraform = (
          final: prev: {
            terraformFull = final.terraform.withPlugins (p: [
              p.cloudflare
              p.aws
              p.google
              p.google-beta
            ]);
          }
        );
      };

      homeConfigurations = {
        "deck@steamdeck" = homeConfig {
          username = "deck";
          pkgs = importPkgs "x86_64-linux";
          allowedUnfree = [ "vault-bin" ];
          options.chrisportela = {
            desktop = false;
            enableExtraPackages = false;
          };
        };
      };

      nixosModules = (import ./lib/nixos/modules/default.nix);

      nixosConfigurations = {
        installer = (import ./lib/nixos/configurations/installer.nix) {
          inherit inputs self;
          nixos = inputs.nixos-unstable;
          nixpkgs = inputs.nixpkgs;
        };
        builder = (import ./lib/nixos/configurations/builder.nix) {
          nixpkgs = inputs.nixpkgs;
          nixosModules = self.nixosModules;
        };
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
            nixpkgs = inputs.nixpkgs-darwin;
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
          ];
        };
      };

      devShells = forAllSystemsShell (
        {
          pkgs,
          pkgsUnstable,
          system,
          ...
        }:
        {
          default = self.devShells.${system}.dotfiles;

          dotfiles = (import ./shells/dotfiles.nix) { inherit pkgs; };

          dev = (import ./shells/dev.nix) {
            # inherit pkgs;
            pkgs = pkgs.extend (
              final: prev: {
                nodejs = final.nodejs_24;
                nodejs_24 = pkgsUnstable.nodejs_24;
              }
            );
          };

          devops = (import ./shells/devops.nix) {
            pkgs = pkgs.extend (
              final: prev: {
                nodejs = pkgsUnstable.nodejs_20;
              }
            );
          };

          # TODO: Broken android and incorrect XCode setup
          react-native = (import ./shells/react-native.nix) {
            inherit nixpkgs;
            pkgs = pkgsUnstable;
            android-nixpkgs = inputs.android-nixpkgs;
          };
        }
      );

      # for `nix fmt`
      formatter = forAllSystems ({ system, ... }: treefmtEval.${system}.config.build.wrapper);

      checks = forAllSystems (
        { pkgs, system, ... }:
        {
          formatting = treefmtEval.${system}.config.build.check self;
          shell-functions =
            let
              script = ./home/shell_functions.sh;
            in
            pkgs.stdenvNoCC.mkDerivation {
              name = "shell-functions-check";
              dontBuild = true;
              src = script;
              nativeBuildInputs = with pkgs; [
                alejandra
                shellcheck
                shfmt
              ];
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
        }
      );
    };
}
