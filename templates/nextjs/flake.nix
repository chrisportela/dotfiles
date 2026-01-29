{
  description = "Next.js project with pnpm";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };
        prisma-engines = pkgs.prisma-engines_7;
        pnpm = pkgs.pnpm_10;
        nodejs = pkgs.nodejs_24;

        # Production build using pkgs.fetchPnpmDeps + pnpmConfigHook (NoCC stdenv).
        # Requires pnpm-lock.yaml (run `pnpm install` and commit). First build with hash = "" to get the hash.
        production = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
          pname = "nextjs-app";
          version = "0.1.0";
          src = pkgs.lib.cleanSourceWith {
            src = self;
            filter = path: type:
              let baseName = baseNameOf path;
              in baseName != "node_modules"
              && baseName != ".next"
              && baseName != ".git"
              && baseName != "result"
              && baseName != ".direnv"
              && ! pkgs.lib.hasPrefix ".env" baseName
              && ! pkgs.lib.hasPrefix "result" baseName;
          };

          nativeBuildInputs = with pkgs; [
            nodejs_24
            pnpm
            pnpmConfigHook
            prisma-engines
          ];

          pnpmDeps = pkgs.fetchPnpmDeps {
            inherit (finalAttrs) pname version src;
            pnpm = pnpm;
            fetcherVersion = 1;
            hash = "sha256-c6vsJ0DtVca810RwZtfx7UZqh3anHP4Inw9vnwKajZA=";
          };

          PRISMA_SCHEMA_ENGINE_BINARY = "${prisma-engines}/bin/schema-engine";
          PRISMA_QUERY_ENGINE_BINARY = "${prisma-engines}/bin/query-engine";
          PRISMA_QUERY_ENGINE_LIBRARY = "${prisma-engines}/lib/libquery_engine.node";
          PRISMA_INTROSPECTION_ENGINE_BINARY = "${prisma-engines}/bin/introspection-engine";
          PRISMA_FMT_BINARY = "${prisma-engines}/bin/prisma-fmt";
          # Prisma generate may need a dummy URL at build time
          DATABASE_URL = "postgresql://localhost/dummy?schema=public";

          buildPhase = ''
            runHook preBuild
            pnpm run db:generate
            pnpm run build
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp -r .next $out/
            cp -r node_modules $out/
            cp -r package.json $out/
            cp -r prisma $out/ 2>/dev/null || true
            cp -r public $out/ 2>/dev/null || true
            cp -r app $out/ 2>/dev/null || true
            cp -r components $out/ 2>/dev/null || true
            cp -r lib $out/ 2>/dev/null || true
            cp next.config.mjs $out/ 2>/dev/null || true
            cp next.config.js $out/ 2>/dev/null || true
            cp next.config.ts $out/ 2>/dev/null || true

            mkdir -p $out/bin
            cat > $out/bin/start << 'STARTSCRIPT'
            #!@runtimeShell@
            set -e
            export NODE_ENV=production
            appdir="$(dirname "$0")/.."
            cd "$appdir"
            exec @node@/bin/node node_modules/next/dist/bin/next start
            STARTSCRIPT
            substituteInPlace $out/bin/start \
              --replace "@runtimeShell@" "${pkgs.runtimeShell}" \
              --replace "@node@" "${nodejs}"
            chmod +x $out/bin/start
            runHook postInstall
          '';
        });
      in
      {
        packages = {
          default = production;
          production = production;
        };

        devShells.default = pkgs.mkShellNoCC {
          buildInputs = with pkgs; [
            # Node.js and pnpm
            nodejs_24
            pnpm
            nodePackages.typescript
            nodePackages.typescript-language-server

            # Database
            postgresql_18

            # Prisma (use Nix-provided binaries for consistent deployment)
            nodePackages.prisma
            prisma-engines

            # Development tools
            git
            curl
            jq
            nixd
            nixfmt-rfc-style
            shellcheck
            shfmt

            # deploy-rs

            # Optional: You can also use the dotfiles dev shell for shared tooling
            # Uncomment the line below if you want to include dotfiles dev shell packages
            # (dotfiles.devShells.${system}.dev or dotfiles.devShells.${system}.default)
          ];

          shellHook = ''
            # Helps Prisma find the correct binaries.
            export PRISMA_SCHEMA_ENGINE_BINARY="${prisma-engines}/bin/schema-engine"
            export PRISMA_QUERY_ENGINE_BINARY="${prisma-engines}/bin/query-engine"
            export PRISMA_QUERY_ENGINE_LIBRARY="${prisma-engines}/lib/libquery_engine.node"
            export PRISMA_INTROSPECTION_ENGINE_BINARY="${prisma-engines}/bin/introspection-engine"
            export PRISMA_FMT_BINARY="${prisma-engines}/bin/prisma-fmt"

            echo "🚀 Next.js + pnpm development environment"
            echo "Node version: $(node --version)"
            echo "pnpm version: $(pnpm --version)"
            echo "Prisma version: $(prisma --version 2>/dev/null | head -n1 || echo 'available')"
            echo "PostgreSQL version: $(postgres --version 2>/dev/null | head -n1 || echo 'available')"
            echo ""
            echo "Quick start:"
            echo "  • Run 'pnpm install' to install dependencies"
            echo "  • Run 'postgres' in a new terminal to start PostgreSQL (from .envrc)"
            echo "  • Run 'pnpm db:migrate' to setup database"
            echo "  • Run 'pnpm dev' to start the development server"
            echo ""
            echo "Testing:"
            echo "  • Run 'pnpm test' for unit tests (Vitest)"
            echo "  • Run 'pnpm test:e2e' for E2E tests (Playwright)"
            echo ""
            echo "Note: Prisma binaries are provided by Nix for consistent deployment"
          '';
        };
      }
    );
}
