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
      nix eval --raw ".#packages.$SYSTEM.$pkg.passthru.updateScript"
    }

    run_update() {
      local pkg="$1"
      local store_path
      store_path="$(get_update_script "$pkg")"
      local tmp
      tmp="$(mktemp)"
      cp "$store_path" "$tmp"
      chmod +x "$tmp"
      echo "==> Updating $pkg"
      UPDATE_NIX_ATTR_PATH="$pkg" \
      UPDATE_NIX_PNAME="$pkg" \
        "$tmp"
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
