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
      echo "==> Done updating $pkg"
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
  '';
}
