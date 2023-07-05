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
        inherit system;
        pkgs = (importPkgs system);
      });

    in
    rec {
      inherit allSystems importPkgs forAllSystems home-manager;

      overlays = { };

      packages = forAllSystems
        ({ pkgs, system }: rec {
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
        }) // {
        x86_64-linux =
          let
            system = "x86_64-linux";
            pkgs = (importPkgs system);
            modulesPath = (toString nixpkgs) + "/nixos/modules";
            nixosGenerate = inputs.nixos-generators.nixosGenerate;
            nixpkgs_overlay = nixosModules.nixpkgs_overlay;
            mkContainer = { name ? "base", config }: (import ./src/lib/proxmox.nix).mkContainer { inherit system nixosGenerate nixpkgs_overlay modulesPath name config; };
          in
          rec {
            installer = (pkgs.callPackage ./src/installer.nix {
              inherit system nixosGenerate nixpkgs_overlay;
            });

            proxmox-vm = nixosGenerate {
              inherit system;
              modules = [
                nixosModules.nixpkgs_overlay
                #(import "${nixpkgs}/nixos/modules/virtualisation/proxmox-image.nix")
                ({ pkgs, modulesPath, ... }: {
                  imports = [
                    (modulesPath + "/virtualisation/proxmox-image.nix")
                  ];

                  options.proxmox.virtio0 = "local-zfs:vm-9999-disk-0";

                  config = {
                    services.cloud-init.network.enable = true;

                    services = {
                      openssh = {
                        enable = true;
                        settings = {
                          PermitRootLogin = "no";
                          PasswordAuthentication = false;
                          KexAlgorithms = [
                            "curve25519-sha256"
                            "curve25519-sha256@libssh.org"
                            "diffie-hellman-group-exchange-sha256"
                            "ecdh-sha2-nistp256"
                          ];
                        };
                        hostKeys = [
                          {
                            type = "rsa";
                            bits = 4096;
                            path = "/etc/ssh/ssh_host_rsa_key";
                          }
                          {
                            type = "ed25519";
                            path = "/etc/ssh/ssh_host_ed25519_key";
                          }
                          {
                            type = "ecdsa";
                            bits = 256;
                            path = "/etc/ssh/ssh_host_ecdsa_key";
                          }
                        ];
                      };

                      tailscale = {
                        enable = true;
                        package = pkgs.tailscale;
                      };
                    };

                    programs = {
                      neovim = {
                        enable = true;
                        vimAlias = true;
                        viAlias = true;
                        defaultEditor = true;
                      };

                      tmux = { enable = true; };

                      zsh = {
                        enable = true;
                        enableBashCompletion = true;
                        #enableCompletion = true;
                      };
                    };

                    users = {
                      defaultUserShell = pkgs.zsh;

                      users = {
                        cmp = {
                          isNormalUser = true;
                          extraGroups = [ "wheel" ];
                          packages = [ ];
                          openssh.authorizedKeys.keys = [
                            "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBLKmP5UUboT3SkiyHzY81/7UGG0SrVcSWxywkD8lpxYznrFz2uWT6zGfiQNj8FrLSwrh/AthIZJfe0LvbKEtTq8= home@secretive.cp-mba.local"
                            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII5kFjpHHMhPxXAp54egnvuGVidd0g83jrw9AzD3AB5N cp@cp-win1"
                          ];
                        };
                      };
                    };

                    security.sudo.wheelNeedsPassword = false;
                  };
                })
              ];
              format = "proxmox";
            };

            baseContainer = mkContainer {
              name = "base";
              config = { ... }: { };
            };

            servicesContainer = mkContainer {
              name = "services";
              config = { pkgs, lib, ... }: {
                #Postgresql
                services.postgresql = {
                  enable = true;
                  package = pkgs.postgresql_15;

                  enableTCPIP = false;
                  settings = {
                    listen_addresses = lib.mkForce "";
                    max_connections = 20;
                    ssl = "off";
                  };

                  initialScript = ./lib/servicesPsqlInit.psql;

                  ensureUsers = [
                    {
                      name = "vault";
                      ensurePermissions = {
                        "DATABASE vault" = "ALL PRIVILEGES";
                      };
                    }
                    {
                      name = "nextcloud";
                      ensurePermissions = {
                        "DATABASE nextcloud" = "ALL PRIVILEGES";
                      };
                    }
                    {
                      name = "admin";
                      ensurePermissions = {
                        "ALL TABLES IN SCHEMA public" = "ALL PRIVILEGES";
                      };
                    }
                  ];

                  ensureDatabases = [
                    "vault"
                    "nextcloud"
                  ];
                };

                #Redis?
                #Consul?

                # Bitwarden (vault warden)
                services.vaultwarden = {
                  enable = true;
                };

                #Vault
                services.vault = {
                  enable = true;
                  storageBackend = "postgresql";
                  storageConfig = ''
                    storage "postgresql" {
                      connection_url = "postgres:///vault?host=/var/run/postgresql"
                      max_idle_connections = "1";
                      max_parallel = "10";
                      ha_enabled = "false";
                      table = "vault_kv_store";
                    }
                  '';
                };

                # Nextcloud
                services.nextcloud = {
                  enable = true;
                  package = pkgs.nextcloud27;
                  hostName = "localhost";
                  config.adminpassFile = "${pkgs.writeText "adminpass" "test123"}"; # DON'T DO THIS IN PRODUCTION - the password file will be world-readable in the Nix Store!
                };


                users.users = {
                  # Included by mkContainer
                  # admin = {};

                  # nextcloud = {}; # Created by nextcloud service config

                  # vault = {}; # Created by vault service config
                };
              };
            };

          };
      };

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

      devShells = forAllSystems ({ pkgs, system }: {
        default = pkgs.mkShell {
          # The Nix packages provided in the environment
          packages = (with pkgs; [
            cachix
            nixVersions.nix_2_14
            nixpkgs-fmt
            shfmt
            shellcheck
            packages.${system}.hush
          ]) ++ pkgs.lib.optionals pkgs.stdenv.isDarwin (with pkgs; [ ]);
        };
      });

      checks = forAllSystems
        ({ pkgs, system }: {
          homeConfigurations = packages.${system}.installer;

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
    };
}
