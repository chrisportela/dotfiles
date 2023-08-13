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
        inherit system;
        overlays = [ cross_pkgs_overlay deploy_rs_overlay hush_overlay ];
      });

      # Helper to provide system-specific attributes
      forAllSystems = f: nixpkgs.lib.genAttrs allSystems (system: f {
        inherit system;
        pkgs = (importPkgs system);
      });

      homeConfig = ({ home ? ./src/home.nix, username ? "cmp", pkgs }:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            { home.username = username; }
            self.nixosModules.pinned_nixpkgs
            self.nixosModules.deploy_rs
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
    in
    {
      inherit allSystems importPkgs forAllSystems;

      packages = forAllSystems
        ({ pkgs, system }: rec {
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

          darwin = self.darwinConfigurations.cp-mba.config.system.build.toplevel;
          builder = self.nixosConfigurations.${system}.builder.config.system.build.toplevel;
          homeConfig = self.homeConfigurations.${system}.cmp.activationPackage;

          default = homeConfig;

        }) // {
        x86_64-linux =
          let
            system = "x86_64-linux";
            inherit (importPkgs system) callPackage;
            inherit (inputs.nixos-generators) nixosGenerate;
            inherit (self.nixosModules) pinned_nixpkgs;
          in
          {
            installer = (callPackage ./src/lib/nixos/installer.nix { inherit system nixosGenerate pinned_nixpkgs; });
          };
      };

      overlays = {
        cross_nixpkgs = cross_pkgs_overlay;
        deploy-rs = deploy_rs_overlay;
        hush = hush_overlay;
      };

      nixosModules = {
        pinned_nixpkgs = { ... }: { nix.registry.nixpkgs.flake = nixpkgs; };
        deploy_rs = { ... }: { nixpkgs.overlays = [ deploy_rs_overlay ]; };
        hush = { ... }: { nixpkgs.overlays = [ hush_overlay ]; };
        firewall = import ./src/lib/nixos/firewall.nix;
        nginx-cloudflare = import ./src/lib/nixos/nginx-cloudflare.nix;
        openssh = import ./src/lib/nixos/openssh.nix;
        router = import ./src/lib/nixos/router.nix;
        webserver = import ./src/lib/nixos/webserver.nix;
        darwin = import ./src/lib/nixos/darwin.nix;
        linux = import ./src/lib/nixos/linux.nix;
      };

      homeConfigurations = {
        "cmp@cp-mba" = homeConfig { pkgs = importPkgs "aarch64-darwin"; };
        "deck@steamdeck" = homeConfig { username = "deck"; pkgs = importPkgs "x86_64-linux"; };
      } // forAllSystems ({ pkgs, system }: { "cmp" = homeConfig { inherit pkgs; }; });

      darwinConfigurations = {
        cp-mba = darwin.lib.darwinSystem {
          system = "aarch64-darwin";
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

      nixosConfigurations =
        let
          nixBuilder = (system: nixpkgs.lib.nixosSystem {
            inherit system;
            modules = with self.nixosModules; [
              pinned_nixpkgs
              linux
              firewall
            ];
          });
        in
        {
          aarch64-linux.builder = nixBuilder "aarch64-linux";
          x86_64-linux.builder = nixBuilder "x86_64-linux";
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

