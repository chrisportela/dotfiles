#!/usr/bin/env bash
# shellcheck disable=SC2016  # ${...} inside single-quoted --apply strings is Nix interpolation, not shell
# Emit the stage-1 build matrices for .forgejo/workflows/ci.yml as step
# outputs (linux / aarch64 / darwin). Each matrix entry is {name, attr}:
# `name` is the display label, `attr` is the flake attribute passed to
# `nix build .#<attr>`.
#
# The lists are derived from the flake itself (hydraJobs for x86_64-linux,
# the per-system packages/devShells/homeConfigurations sets for the other
# systems) so the CI job list can never drift from the flake.
#
# The `heavy` list below is the extension point for expensive derivations
# that host toplevels pull in but that aren't flake packages themselves
# (today: ada's 32-bit openldap overlay rebuild and its non-CUDA
# onnxruntime override). If CUDA is ever enabled, add its big leaf
# packages here so they build as their own CI jobs before the ada
# toplevel job runs.
#
# Required env (auto-provided under Forgejo Actions):
#   GITHUB_OUTPUT   writable file for step output key=value pairs

set -euo pipefail

write_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "$1" >> "$GITHUB_OUTPUT"
  fi
  echo "output: $1"
}

# ── x86_64-linux: everything hydraJobs exposes (minus hosts → stage 2) ──────

linux=$(nix eval --json --no-warn-dirty .#hydraJobs --apply '
  jobs:
  let
    sys = "x86_64-linux";
    mk = group: map (n: {
      name = "${group}/${n}";
      attr = "hydraJobs.${group}.\"${n}\".${sys}";
    }) (builtins.attrNames jobs.${group});
  in
  (mk "packages") ++ (mk "devShells") ++ (mk "homeActivations")
')

heavy=$(jq -nc '[
  { name: "heavy/openldap-i686",
    attr: "nixosConfigurations.ada.pkgs.pkgsi686Linux.openldap" },
  { name: "heavy/onnxruntime",
    attr: "nixosConfigurations.ada.pkgs.onnxruntime" }
]')

linux=$(jq -nc --argjson a "$linux" --argjson b "$heavy" '$a + $b')

# ── aarch64-linux: built via binfmt on the x86_64 runners ───────────────────
# `pi` (the rpi4 SD image) is excluded here — it has its own main-only job.
# `default` is an alias of the cmp home activation, which is listed anyway.

aarch64=$(nix eval --json --no-warn-dirty .#packages.aarch64-linux --apply '
  pkgs:
  map (n: { name = "packages/${n}"; attr = "packages.aarch64-linux.\"${n}\""; })
    (builtins.filter (n: !(builtins.elem n [ "pi" "default" ]))
      (builtins.attrNames pkgs))
')

aarch64_shells=$(nix eval --json --no-warn-dirty .#devShells.aarch64-linux --apply '
  shells:
  map (n: { name = "devShells/${n}"; attr = "devShells.aarch64-linux.\"${n}\""; })
    (builtins.filter (n: n != "default") (builtins.attrNames shells))
')

aarch64_homes=$(jq -nc '[
  { name: "home/cmp",
    attr: "legacyPackages.aarch64-linux.homeConfigurations.cmp.activationPackage" }
]')

aarch64=$(jq -nc --argjson a "$aarch64" --argjson b "$aarch64_shells" --argjson c "$aarch64_homes" '$a + $b + $c')

# ── aarch64-darwin: built natively on the lux runner ────────────────────────
# react-native is excluded from the build matrix (Android SDK shell; it is
# eval'd in the hosts-darwin job instead, matching the GitHub workflow).

darwin=$(nix eval --json --no-warn-dirty .#packages.aarch64-darwin --apply '
  pkgs:
  map (n: { name = "packages/${n}"; attr = "packages.aarch64-darwin.\"${n}\""; })
    (builtins.filter (n: !(builtins.elem n [ "pi" "default" ]))
      (builtins.attrNames pkgs))
')

darwin_shells=$(nix eval --json --no-warn-dirty .#devShells.aarch64-darwin --apply '
  shells:
  map (n: { name = "devShells/${n}"; attr = "devShells.aarch64-darwin.\"${n}\""; })
    (builtins.filter (n: !(builtins.elem n [ "default" "react-native" ]))
      (builtins.attrNames shells))
')

darwin_homes=$(jq -nc '[
  { name: "home/cmp",
    attr: "legacyPackages.aarch64-darwin.homeConfigurations.cmp.activationPackage" },
  { name: "home/cmp@lux",
    attr: "legacyPackages.aarch64-darwin.homeConfigurations.\"cmp@lux\".activationPackage" },
  { name: "home/cmp@roxy",
    attr: "legacyPackages.aarch64-darwin.homeConfigurations.\"cmp@roxy\".activationPackage" }
]')

darwin=$(jq -nc --argjson a "$darwin" --argjson b "$darwin_shells" --argjson c "$darwin_homes" '$a + $b + $c')

# ── Emit ────────────────────────────────────────────────────────────────────

echo "==> linux jobs:   $(echo "$linux" | jq length)"
echo "==> aarch64 jobs: $(echo "$aarch64" | jq length)"
echo "==> darwin jobs:  $(echo "$darwin" | jq length)"

write_output "linux=$(echo "$linux" | jq -c .)"
write_output "aarch64=$(echo "$aarch64" | jq -c .)"
write_output "darwin=$(echo "$darwin" | jq -c .)"
