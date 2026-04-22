{
  writeShellApplication,
  nix,
  jq,
  git,
}:

writeShellApplication {
  name = "update";

  runtimeInputs = [
    nix
    jq
    git
  ];

  text = ''
    SYSTEM="$(nix eval --raw --impure --expr 'builtins.currentSystem')"
    TARGET="''${1:-}"
    BUILD_LOG_DIR="$(mktemp -d -t pkg-update-logs.XXXXXX)"
    FAILED_PKGS=()

    get_packages() {
      nix eval --json ".#packages.$SYSTEM" --apply 'pkgs: builtins.attrNames pkgs' | jq -r '.[]'
    }

    has_update_script() {
      local pkg="$1"
      nix eval --json ".#packages.$SYSTEM.$pkg.passthru.updateScript" &>/dev/null
    }

    get_update_script() {
      local pkg="$1"
      nix eval --json ".#packages.$SYSTEM.$pkg.passthru.updateScript"
    }

    run_update() {
      local pkg="$1"
      local script_json
      script_json="$(get_update_script "$pkg")"

      # updateScript can be a string (store path) or a list of strings (command + args)
      local script_type
      script_type="$(echo "$script_json" | jq -r 'type')"

      local cmd_args=()
      if [ "$script_type" = "array" ]; then
        mapfile -t cmd_args < <(echo "$script_json" | jq -r '.[]')
      else
        cmd_args=("$(echo "$script_json" | jq -r '.')")
      fi

      local tmp
      tmp="$(mktemp)"
      cp "''${cmd_args[0]}" "$tmp"
      chmod +x "$tmp"
      cmd_args[0]="$tmp"

      echo "==> Updating $pkg"
      UPDATE_NIX_ATTR_PATH="$pkg" \
      UPDATE_NIX_PNAME="$pkg" \
        "''${cmd_args[@]}"
      rm -f "$tmp"

      # Stage changes so flake eval can see updated files
      git add -A

      echo "==> Verifying $pkg builds..."
      local log_file="$BUILD_LOG_DIR/$pkg-build.log"
      if nix build --no-link ".#packages.$SYSTEM.$pkg" 2>&1 | tee "$log_file"; then
        echo "==> $pkg updated and verified successfully"
        rm -f "$log_file"
      else
        echo "==> ERROR: $pkg build failed! Logs saved to: $log_file" >&2
        FAILED_PKGS+=("$pkg")
      fi
    }

    if [ -n "$TARGET" ]; then
      if has_update_script "$TARGET"; then
        run_update "$TARGET"
      else
        echo "Error: Package '$TARGET' does not have a passthru.updateScript" >&2
        exit 1
      fi
    else
      echo "Discovering packages with updateScript..."
      for pkg in $(get_packages); do
        if has_update_script "$pkg"; then
          echo "  Found: $pkg"
          run_update "$pkg"
        fi
      done
    fi

    if [ ''${#FAILED_PKGS[@]} -gt 0 ]; then
      echo ""
      echo "=============================="
      echo "BUILD FAILURES: ''${FAILED_PKGS[*]}"
      echo "Build logs: $BUILD_LOG_DIR"
      echo "=============================="
      exit 1
    else
      rm -rf "$BUILD_LOG_DIR"
    fi
  '';
}
