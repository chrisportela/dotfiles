# agent-vm.nix
# Produces the `agent-vm` CLI tool as a derivation.
{
  pkgs,
  lib,
  inputs,
  bridge,
  defaults,
  user,
  templates,
}:
let
  # Bake in flake input revisions (direct attributes on locked inputs)
  microvmRev = inputs.microvm.rev;
  nixpkgsRev = inputs.nixpkgs-unstable.rev;
  homeManagerRev = inputs.home-manager.rev;

  # Parse gateway from subnet ("192.168.83.1/24" -> "192.168.83.1")
  gatewayAddress = builtins.head (lib.splitString "/" bridge.subnet);

  # Parse subnet prefix robustly ("192.168.83.1" -> "192.168.83")
  gatewayOctets = lib.splitString "." gatewayAddress;
  subnetPrefix = lib.concatStringsSep "." (lib.take 3 gatewayOctets);

  # Read files to embed in generated flakes
  vmBaseContent = builtins.readFile ./vm-base.nix;
  vmNetworkContent = builtins.readFile ./vm-network.nix;
  # Strip updateScript passthru (references ./update.sh which won't exist in VM dir)
  claudeCodePkgContent = builtins.replaceStrings
    [ ''
base.overrideAttrs (prev: {
  passthru = prev.passthru // {
    updateScript = ./update.sh;
  };
})'' ]
    [ "base" ]
    (builtins.readFile ../../../pkgs/claude-code/package.nix);
  claudeCodeLockfile = ../../../pkgs/claude-code/package-lock.json;

  # Serialize templates to JSON, filtering out null values
  cleanTemplate = t: lib.filterAttrs (_: v: v != null) {
    inherit (t) workspace vcpu mem varSize claude dotfiles direnv copyWorkspace networkMode allowSSH;
    packages = if t.packages != [ ] then t.packages else null;
    credentials = if t.credentials != [ ] then
      map (c: { inherit (c) source mountPoint; }) t.credentials
    else null;
    allowedDomains = if t.allowedDomains != [ ] then t.allowedDomains else null;
    interceptDomains = if t.interceptDomains != [ ] then t.interceptDomains else null;
    proxyBlockRegexes = if t.proxyBlockRegexes != [ ] then t.proxyBlockRegexes else null;
  };
  templatesJson = builtins.toJSON (lib.mapAttrs (_: cleanTemplate) templates);
  templateNames = lib.concatStringsSep " " (builtins.attrNames templates);

  script = pkgs.writeShellScriptBin "agent-vm" ''
  set -euo pipefail

  MICROVMS_DIR="/var/lib/microvms"
  DECLARATIVE_IPS_FILE="$MICROVMS_DIR/.declarative-ips"
  GATEWAY="${gatewayAddress}"
  SUBNET_PREFIX="${subnetPrefix}"
  DEFAULT_VCPU="${toString defaults.vcpu}"
  DEFAULT_MEM="${toString defaults.mem}"
  DEFAULT_HYPERVISOR="${defaults.hypervisor}"
  USER_NAME="${user.name}"
  USER_UID="${toString user.uid}"
  USER_GID="${toString user.gid}"
  USER_KEYS='${builtins.toJSON user.authorizedKeys}'

  # Pinned flake inputs (baked in at build time)
  MICROVM_URL="github:microvm-nix/microvm.nix/${microvmRev}"
  NIXPKGS_URL="github:nixos/nixpkgs/${nixpkgsRev}"
  HOME_MANAGER_URL="github:nix-community/home-manager/${homeManagerRev}"
  DEFAULT_CLAUDE="${lib.boolToString defaults.claude}"
  DEFAULT_CLAUDE_CONFIG_DIR="${defaults.claudeConfigDir}"
  DEFAULT_DOTFILES="${lib.boolToString defaults.dotfiles}"
  DEFAULT_DOTFILES_DIR="${defaults.dotfilesDir}"
  DEFAULT_DIRENV="${lib.boolToString defaults.direnv}"
  TEMPLATES_JSON='${templatesJson}'

  usage() {
    cat <<'USAGE'
Usage: agent-vm <command> [args]

Commands:
  create <name> [flags]   Create a new ad-hoc VM
  start <name>            Start a VM
  stop <name>             Stop a VM
  destroy <name>          Stop and remove a VM
  list                    List VMs with status and IP
  ssh <name> [ssh-args]   SSH into a VM
  edit <name>             Edit the VM's flake.nix with \$EDITOR
  templates               List available templates

Create flags:
  -t, --template <name>           Use a named template as base
  --workspace <path>              Host directory to share
  --packages <pkg1,pkg2,...>      Additional nixpkgs to include
  --credentials <source:mount>    Credential share (repeatable)
  --vcpu <n>                      Override default vCPUs
  --mem <n>                       Override default RAM
  --claude                        Enable Claude Code (credentials + config)
  --no-claude                     Disable Claude Code
  --direnv                        Enable direnv + nix-direnv
  --no-direnv                     Disable direnv
  --dotfiles                      Mount dotfiles directory read-only
  --no-dotfiles                   Disable dotfiles mount
  --var-size <n>                  Override /var volume size in MB
  --copy-workspace                Copy workspace instead of sharing directly
  --hm-module <path>              Additional home-manager module (repeatable)
  --network-mode <mode>           Network mode: default or restricted
  --allowed-domains <d1,d2,...>   Domains allowed through proxy
  --intercept-domains <d1,d2,...> Domains with TLS interception
  --block-regex <regex>           URL regex to block (repeatable)
  --allow-ssh                     Allow outbound SSH in restricted mode

SSH flags:
  --tmux [session]                Start or attach to a tmux session
USAGE
  }

  get_used_ips() {
    local ips=""
    # Read declarative IPs
    if [ -f "$DECLARATIVE_IPS_FILE" ]; then
      ips="$(${pkgs.gnugrep}/bin/grep -v '^\s*$' "$DECLARATIVE_IPS_FILE" || true)"
    fi
    # Read ad-hoc VM IPs from metadata files
    for dir in "$MICROVMS_DIR"/*/; do
      [ -d "$dir" ] || continue
      if [ -f "''${dir}.ip" ]; then
        ips="$ips"$'\n'"$(cat "''${dir}.ip")"
      fi
    done
    echo "$ips" | ${pkgs.gnugrep}/bin/grep -v '^\s*$' | sort -u || true
  }

  next_ip() {
    local used_ips
    used_ips="$(get_used_ips)"
    for i in $(seq 2 254); do
      local candidate="$SUBNET_PREFIX.$i"
      if ! echo "$used_ips" | ${pkgs.gnugrep}/bin/grep -qxF "$candidate"; then
        echo "$candidate"
        return
      fi
    done
    echo "Error: no free IPs in subnet" >&2
    exit 1
  }

  ip_to_mac() {
    local last_octet
    last_octet="$(echo "$1" | cut -d. -f4)"
    printf "02:00:00:00:00:%02x" "$last_octet"
  }

  apply_template() {
    local tpl_name="$1"
    local tpl
    tpl="$(echo "$TEMPLATES_JSON" | ${pkgs.jq}/bin/jq -e --arg n "$tpl_name" '.[$n]' 2>/dev/null)" || {
      echo "Error: unknown template '$tpl_name'" >&2
      echo "Available templates: $(echo "$TEMPLATES_JSON" | ${pkgs.jq}/bin/jq -r 'keys | join(", ")')" >&2
      exit 1
    }
    # Apply template values (only non-null fields override defaults)
    local val
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.workspace // empty')" && [ -n "$val" ] && workspace="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.vcpu // empty')" && [ -n "$val" ] && vcpu="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.mem // empty')" && [ -n "$val" ] && mem="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.varSize // empty')" && [ -n "$val" ] && var_size="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.claude // empty')" && [ -n "$val" ] && claude="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.dotfiles // empty')" && [ -n "$val" ] && use_dotfiles="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.direnv // empty')" && [ -n "$val" ] && use_direnv="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.copyWorkspace // empty')" && [ -n "$val" ] && copy_workspace="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '(.packages // []) | join(",")')" && [ -n "$val" ] && packages="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '(.credentials // []) | map(.source + ":" + .mountPoint) | join(" ")')" && [ -n "$val" ] && credentials="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.networkMode // empty')" && [ -n "$val" ] && network_mode="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '.allowSSH // empty')" && [ -n "$val" ] && allow_ssh="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '(.allowedDomains // []) | join(",")')" && [ -n "$val" ] && allowed_domains="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '(.interceptDomains // []) | join(",")')" && [ -n "$val" ] && intercept_domains="$val"
    val="$(echo "$tpl" | ${pkgs.jq}/bin/jq -r '(.proxyBlockRegexes // []) | join(" ")')" && [ -n "$val" ] && block_regexes="$val"
  }

  cmd_create() {
    local name="$1"; shift
    local workspace=""
    local packages=""
    local vcpu="$DEFAULT_VCPU"
    local mem="$DEFAULT_MEM"
    local var_size="51200"
    local credentials=""
    local copy_workspace="false"
    local claude="$DEFAULT_CLAUDE"
    local use_dotfiles="$DEFAULT_DOTFILES"
    local use_direnv="$DEFAULT_DIRENV"
    local hm_modules=""
    local network_mode="default"
    local allowed_domains=""
    local intercept_domains=""
    local block_regexes=""
    local allow_ssh="false"

    while [ $# -gt 0 ]; do
      case "$1" in
        -t|--template) apply_template "$2"; shift 2 ;;
        --workspace) workspace="$2"; shift 2 ;;
        --packages) packages="$2"; shift 2 ;;
        --vcpu) vcpu="$2"; shift 2 ;;
        --mem) mem="$2"; shift 2 ;;
        --var-size) var_size="$2"; shift 2 ;;
        --credentials) credentials="$credentials $2"; shift 2 ;;
        --copy-workspace) copy_workspace="true"; shift ;;
        --claude) claude="true"; shift ;;
        --no-claude) claude="false"; shift ;;
        --dotfiles) use_dotfiles="true"; shift ;;
        --no-dotfiles) use_dotfiles="false"; shift ;;
        --direnv) use_direnv="true"; shift ;;
        --no-direnv) use_direnv="false"; shift ;;
        --hm-module) hm_modules="$hm_modules $2"; shift 2 ;;
        --network-mode) network_mode="$2"; shift 2 ;;
        --allowed-domains) allowed_domains="$2"; shift 2 ;;
        --intercept-domains) intercept_domains="$2"; shift 2 ;;
        --block-regex) block_regexes="$block_regexes $2"; shift 2 ;;
        --allow-ssh) allow_ssh="true"; shift ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
      esac
    done

    local vm_dir="$MICROVMS_DIR/$name"
    if [ -d "$vm_dir" ]; then
      echo "Error: VM '$name' already exists at $vm_dir" >&2
      exit 1
    fi

    local ip
    ip="$(next_ip)"
    local mac
    mac="$(ip_to_mac "$ip")"

    echo "Creating VM '$name' with IP $ip..."

    sudo mkdir -p "$vm_dir/ssh-host-keys"
    sudo ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f "$vm_dir/ssh-host-keys/ssh_host_ed25519_key" -q
    echo "$ip" | sudo tee "$vm_dir/.ip" > /dev/null

    # Generate proxy CA for restricted mode
    if [ "$network_mode" = "restricted" ]; then
      sudo mkdir -p "$vm_dir/proxy-ca"
      sudo ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$vm_dir/proxy-ca/ca-key.pem" \
        -out "$vm_dir/proxy-ca/ca-cert.pem" \
        -days 3650 -subj "/CN=agent-vm-$name Proxy CA" 2>/dev/null
    fi

    # Build workspace share Nix expression
    local workspace_nix="null"
    if [ -n "$workspace" ]; then
      workspace_nix="\"$workspace\""
    fi

    # Build credentials Nix expression
    local creds_nix="[ ]"
    if [ -n "$credentials" ]; then
      creds_nix="["
      for cred in $credentials; do
        local src="''${cred%%:*}"
        local mnt="''${cred#*:}"
        creds_nix="$creds_nix { source = \"$src\"; mountPoint = \"$mnt\"; }"
      done
      creds_nix="$creds_nix ]"
    fi

    # Build packages Nix expression
    local pkgs_nix="[ ]"
    if [ -n "$packages" ]; then
      pkgs_nix="with pkgs; ["
      IFS=',' read -ra pkg_arr <<< "$packages"
      for p in "''${pkg_arr[@]}"; do
        pkgs_nix="$pkgs_nix $p"
      done
      pkgs_nix="$pkgs_nix ]"
    fi

    # Build authorizedKeys Nix expression
    local keys_nix
    keys_nix="$(echo "$USER_KEYS" | ${pkgs.jq}/bin/jq -r 'map("\"" + . + "\"") | "[ " + join(" ") + " ]"')"

    # Build allowedDomains Nix expression
    local allowed_nix="[ ]"
    if [ -n "$allowed_domains" ]; then
      allowed_nix="["
      IFS=',' read -ra dom_arr <<< "$allowed_domains"
      for d in "''${dom_arr[@]}"; do
        allowed_nix="$allowed_nix \"$d\""
      done
      allowed_nix="$allowed_nix ]"
    fi

    # Build interceptDomains Nix expression
    local intercept_nix="[ ]"
    if [ -n "$intercept_domains" ]; then
      intercept_nix="["
      IFS=',' read -ra dom_arr <<< "$intercept_domains"
      for d in "''${dom_arr[@]}"; do
        intercept_nix="$intercept_nix \"$d\""
      done
      intercept_nix="$intercept_nix ]"
    fi

    # Build proxyBlockRegexes Nix expression
    local regexes_nix="[ ]"
    if [ -n "$block_regexes" ]; then
      regexes_nix="["
      for r in $block_regexes; do
        regexes_nix="$regexes_nix \"$r\""
      done
      regexes_nix="$regexes_nix ]"
    fi

    # Copy vm-base.nix into the VM directory
    sudo tee "$vm_dir/vm-base.nix" > /dev/null <<'VMBASE'
${vmBaseContent}
VMBASE

    # Copy vm-network.nix into the VM directory
    sudo tee "$vm_dir/vm-network.nix" > /dev/null <<'VMNETWORK'
${vmNetworkContent}
VMNETWORK

    # Copy claude credentials if claude is enabled
    if [ "$claude" = "true" ]; then
      sudo mkdir -p "$vm_dir/claude-code"
      sudo tee "$vm_dir/claude-code/package.nix" > /dev/null <<'CLAUDEPKG'
${claudeCodePkgContent}
CLAUDEPKG
      sudo cp ${claudeCodeLockfile} "$vm_dir/claude-code/package-lock.json"
    fi

    # Copy any extra home-manager modules into the VM directory
    local hm_imports_nix="[ ]"
    if [ -n "$hm_modules" ]; then
      hm_imports_nix="["
      for mod in $hm_modules; do
        local modbase
        modbase="$(basename "$mod")"
        sudo cp "$mod" "$vm_dir/$modbase"
        hm_imports_nix="$hm_imports_nix (import ./$modbase)"
      done
      hm_imports_nix="$hm_imports_nix ]"
    fi

    # Warn if --claude and --credentials both target .claude
    if [ "$claude" = "true" ] && [ -n "$credentials" ]; then
      for cred in $credentials; do
        local cred_src="''${cred%%:*}"
        if [ "$cred_src" = "$DEFAULT_CLAUDE_CONFIG_DIR" ]; then
          echo "Warning: --claude already mounts $DEFAULT_CLAUDE_CONFIG_DIR; skipping duplicate --credentials entry" >&2
          credentials="$(echo "$credentials" | ${pkgs.gnused}/bin/sed "s| $cred||")"
        fi
      done
    fi

    # Build claude config dir Nix expression
    local claude_config_nix="null"
    if [ "$claude" = "true" ]; then
      claude_config_nix="\"$DEFAULT_CLAUDE_CONFIG_DIR\""
    fi

    # Build dotfiles dir Nix expression
    local dotfiles_dir_nix="null"
    if [ "$use_dotfiles" = "true" ]; then
      dotfiles_dir_nix="\"$DEFAULT_DOTFILES_DIR\""
    fi

    # Generate flake.nix
    sudo tee "$vm_dir/flake.nix" > /dev/null <<FLAKE
{
  inputs = {
    nixpkgs.url = "$NIXPKGS_URL";
    microvm = {
      url = "$MICROVM_URL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "$HOME_MANAGER_URL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm, home-manager, ... }:
  let
    system = "x86_64-linux";
  in
  {
    nixosConfigurations.$name = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        { nixpkgs.overlays = [
            (final: prev: {
              claude-code = final.callPackage ./claude-code/package.nix { };
            })
          ];
        }
        microvm.nixosModules.microvm
        ((import ./vm-base.nix) {
          hostName = "$name";
          ipAddress = "$ip";
          mac = "$mac";
          gatewayAddress = "$GATEWAY";
          vcpu = $vcpu;
          mem = $mem;
          varSize = $var_size;
          hypervisor = "$DEFAULT_HYPERVISOR";
          workspace = $workspace_nix;
          copyWorkspace = $copy_workspace;
          credentials = $creds_nix;
          packages = $pkgs_nix;
          userName = "$USER_NAME";
          uid = $USER_UID;
          gid = $USER_GID;
          authorizedKeys = $keys_nix;
          sshHostKeyPath = "$vm_dir/ssh-host-keys";
          homeManagerModule = home-manager.nixosModules.home-manager;
          claude = $claude;
          claudeConfigDir = $claude_config_nix;
          dotfiles = $use_dotfiles;
          dotfilesDir = $dotfiles_dir_nix;
          direnv = $use_direnv;
          networkMode = "$network_mode";
          allowedDomains = $allowed_nix;
          interceptDomains = $intercept_nix;
          proxyBlockRegexes = $regexes_nix;
          allowSSH = $allow_ssh;
          extraHomeModules = $hm_imports_nix;
        })
      ];
    };

    # Required by microvm.nix for imperative VMs
    packages.\''${system}.default = self.nixosConfigurations.$name.config.microvm.declaredRunner;
  };
}
FLAKE

    # microvm.nix services run as microvm:kvm — they need write access
    sudo chown -R microvm:kvm "$vm_dir"

    # Init git repo so Nix recognises the directory as a flake
    sudo -u microvm ${pkgs.git}/bin/git -C "$vm_dir" init -q
    sudo -u microvm ${pkgs.git}/bin/git -C "$vm_dir" add -A
    sudo -u microvm ${pkgs.git}/bin/git -C "$vm_dir" \
      -c user.name="agent-vm" -c user.email="agent-vm@localhost" \
      commit -q -m "init"

    echo "VM '$name' created."
    echo "  IP: $ip"
    echo "  Dir: $vm_dir"
    echo "  Start with: agent-vm start $name"
  }

  cmd_start() {
    local name="$1"
    local vm_dir="$MICROVMS_DIR/$name"
    if [ ! -d "$vm_dir" ]; then
      echo "Error: VM '$name' not found at $vm_dir" >&2
      exit 1
    fi

    # Build the VM flake and create the 'current' symlink
    # microvm.nix services expect /var/lib/microvms/<name>/current/bin/microvm-run
    # Build as microvm user since the flake repo is owned by microvm:kvm
    echo "Building VM '$name'..."
    local build_result
    build_result="$(cd "$vm_dir" && sudo -u microvm HOME="$vm_dir" ${pkgs.nix}/bin/nix build "$vm_dir#packages.x86_64-linux.default" --print-out-paths --no-link)"
    sudo ln -sfT "$build_result" "$vm_dir/current"

    echo "Starting VM '$name'..."
    # systemctl start blocks until VM signals readiness via vsock
    sudo systemctl start "microvm@$name"

    # Wait for SSH port to accept connections
    local ip
    ip="$(cat "$vm_dir/.ip")"
    echo "Waiting for SSH port..."
    local attempts=0
    while ! ${pkgs.netcat-openbsd}/bin/nc -z -w 2 "$ip" 22 2>/dev/null; do
      attempts=$((attempts + 1))
      if [ "$attempts" -ge 15 ]; then
        echo "Warning: SSH port not open after 30s." >&2
        break
      fi
      sleep 2
    done

    echo "VM '$name' started. SSH with: agent-vm ssh $name"
  }

  cmd_stop() {
    local name="$1"
    echo "Stopping VM '$name'..."
    sudo systemctl stop "microvm@$name"
    echo "VM '$name' stopped."
  }

  cmd_destroy() {
    local name="$1"
    local vm_dir="$MICROVMS_DIR/$name"
    if [ ! -d "$vm_dir" ]; then
      echo "Error: VM '$name' not found at $vm_dir" >&2
      exit 1
    fi
    # Stop if running
    if systemctl is-active --quiet "microvm@$name" 2>/dev/null; then
      echo "Stopping VM '$name'..."
      sudo systemctl stop "microvm@$name"
    fi
    echo "Removing $vm_dir..."
    sudo rm -rf "$vm_dir"
    echo "VM '$name' destroyed."
  }

  cmd_list() {
    echo "NAME            IP               STATUS"
    echo "----            --               ------"
    for dir in "$MICROVMS_DIR"/*/; do
      [ -d "$dir" ] || continue
      local name
      name="$(basename "$dir")"
      local ip="unknown"
      if [ -f "''${dir}.ip" ]; then
        ip="$(cat "''${dir}.ip")"
      fi
      local status="stopped"
      if systemctl is-active --quiet "microvm@$name" 2>/dev/null; then
        status="running"
      fi
      printf "%-15s %-16s %s\n" "$name" "$ip" "$status"
    done
  }

  cmd_ssh() {
    local name="$1"; shift
    local vm_dir="$MICROVMS_DIR/$name"
    if [ ! -f "$vm_dir/.ip" ]; then
      echo "Error: VM '$name' not found or missing IP" >&2
      exit 1
    fi
    local ip
    ip="$(cat "$vm_dir/.ip")"

    # Parse --tmux flag
    local tmux_session=""
    local use_tmux="false"
    local ssh_extra_args=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --tmux)
          use_tmux="true"
          shift
          if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
            tmux_session="$1"; shift
          else
            tmux_session="main"
          fi
          ;;
        *) ssh_extra_args+=("$1"); shift ;;
      esac
    done

    if [ "$use_tmux" = "true" ]; then
      exec ${pkgs.openssh}/bin/ssh \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$vm_dir/known_hosts" \
        -t "$USER_NAME@$ip" "tmux new-session -A -s $tmux_session" "''${ssh_extra_args[@]}"
    else
      exec ${pkgs.openssh}/bin/ssh \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$vm_dir/known_hosts" \
        "$USER_NAME@$ip" "''${ssh_extra_args[@]}"
    fi
  }

  if [ $# -lt 1 ]; then
    usage
    exit 1
  fi

  cmd="$1"; shift

  case "$cmd" in
    create)
      [ $# -lt 1 ] && { echo "Error: name required" >&2; usage; exit 1; }
      cmd_create "$@"
      ;;
    start)
      [ $# -lt 1 ] && { echo "Error: name required" >&2; usage; exit 1; }
      cmd_start "$1"
      ;;
    stop)
      [ $# -lt 1 ] && { echo "Error: name required" >&2; usage; exit 1; }
      cmd_stop "$1"
      ;;
    destroy)
      [ $# -lt 1 ] && { echo "Error: name required" >&2; usage; exit 1; }
      cmd_destroy "$1"
      ;;
    list)
      cmd_list
      ;;
    edit)
      [ $# -lt 1 ] && { echo "Error: name required" >&2; usage; exit 1; }
      vm_dir="$MICROVMS_DIR/$1"
      if [ ! -f "$vm_dir/flake.nix" ]; then
        echo "Error: VM '$1' not found or missing flake.nix" >&2
        exit 1
      fi
      exec "''${EDITOR:-vi}" "$vm_dir/flake.nix"
      ;;
    templates)
      echo "Available templates:"
      echo "$TEMPLATES_JSON" | ${pkgs.jq}/bin/jq -r 'to_entries[] | "  \(.key): \(.value | to_entries | map("  \(.key)=\(.value)") | join(", "))"'
      if [ "$(echo "$TEMPLATES_JSON" | ${pkgs.jq}/bin/jq 'length')" = "0" ]; then
        echo "  (none configured)"
      fi
      ;;
    ssh)
      [ $# -lt 1 ] && { echo "Error: name required" >&2; usage; exit 1; }
      cmd_ssh "$@"
      ;;
    *)
      echo "Unknown command: $cmd" >&2
      usage
      exit 1
      ;;
  esac
'';

  bashCompletion = pkgs.writeText "agent-vm.bash" ''
    _agent_vm() {
      local cur prev cmd
      COMPREPLY=()
      cur="''${COMP_WORDS[COMP_CWORD]}"
      prev="''${COMP_WORDS[COMP_CWORD-1]}"

      local commands="create start stop destroy list ssh edit templates"
      local create_flags="-t --template --workspace --packages --credentials --vcpu --mem --var-size --claude --no-claude --direnv --no-direnv --dotfiles --no-dotfiles --copy-workspace --hm-module --network-mode --allowed-domains --intercept-domains --block-regex --allow-ssh"
      local ssh_flags="--tmux"

      if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
        return
      fi

      cmd="''${COMP_WORDS[1]}"

      # Complete VM names for commands that take one
      if [ "$COMP_CWORD" -eq 2 ]; then
        case "$cmd" in
          start|stop|destroy|ssh|edit)
            local vms=""
            for dir in /var/lib/microvms/*/; do
              [ -d "$dir" ] || continue
              vms="$vms $(basename "$dir")"
            done
            COMPREPLY=( $(compgen -W "$vms" -- "$cur") )
            return
            ;;
        esac
      fi

      case "$cmd" in
        create)
          case "$prev" in
            -t|--template)
              COMPREPLY=( $(compgen -W "${templateNames}" -- "$cur") )
              return
              ;;
            --workspace)
              COMPREPLY=( $(compgen -d -- "$cur") )
              return
              ;;
            --hm-module)
              COMPREPLY=( $(compgen -f -- "$cur") )
              return
              ;;
            --network-mode)
              COMPREPLY=( $(compgen -W "default restricted" -- "$cur") )
              return
              ;;
            --vcpu|--mem|--var-size|--packages|--credentials)
              return
              ;;
          esac
          if [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W "$create_flags" -- "$cur") )
          fi
          ;;
        ssh)
          if [[ "$cur" == -* ]]; then
            COMPREPLY=( $(compgen -W "$ssh_flags" -- "$cur") )
          fi
          ;;
      esac
    }
    complete -F _agent_vm agent-vm
  '';

  zshCompletion = pkgs.writeText "_agent-vm" ''
    #compdef agent-vm

    _agent_vm_vms() {
      local -a vms
      local dir
      for dir in /var/lib/microvms/*/; do
        [[ -d "$dir" ]] && vms+=("''${dir:t}")
      done
      (( ''${#vms} )) && compadd -a vms
    }

    _agent_vm_templates() {
      local -a templates=( ${templateNames} )
      (( ''${#templates} )) && compadd -a templates
    }

    _agent_vm() {
      local -a commands=(
        'create:Create a new ad-hoc VM'
        'start:Start a VM'
        'stop:Stop a VM'
        'destroy:Stop and remove a VM'
        'list:List VMs with status and IP'
        'ssh:SSH into a VM'
        'edit:Edit VM flake.nix'
        'templates:List available templates'
      )

      if (( CURRENT == 2 )); then
        _describe 'command' commands
        return
      fi

      case "''${words[2]}" in
        start|stop|destroy|edit)
          if (( CURRENT == 3 )); then
            _agent_vm_vms
          fi
          ;;
        ssh)
          if (( CURRENT == 3 )); then
            _agent_vm_vms
          else
            _arguments \
              '--tmux[Start or attach to tmux session]::session name:'
          fi
          ;;
        create)
          _arguments \
            '(-t --template)'{-t,--template}'[Use a named template]:template:_agent_vm_templates' \
            '--workspace[Host directory to share]:directory:_directories' \
            '--packages[Additional packages]:packages:' \
            '--credentials[Credential share]:credentials:' \
            '--vcpu[Override vCPUs]:vcpus:' \
            '--mem[Override RAM in MB]:mem:' \
            '--var-size[Override /var size in MB]:size:' \
            '--claude[Enable Claude Code]' \
            '--no-claude[Disable Claude Code]' \
            '--direnv[Enable direnv]' \
            '--no-direnv[Disable direnv]' \
            '--dotfiles[Mount dotfiles]' \
            '--no-dotfiles[Disable dotfiles]' \
            '--copy-workspace[Copy workspace]' \
            '*--hm-module[Home-manager module]:module:_files' \
            '--network-mode[Network mode]:mode:(default restricted)' \
            '--allowed-domains[Allowed domains]:domains:' \
            '--intercept-domains[Intercept domains]:domains:' \
            '*--block-regex[Block URL regex]:regex:' \
            '--allow-ssh[Allow outbound SSH]'
          ;;
      esac
    }

    _agent_vm "$@"
  '';
in
pkgs.symlinkJoin {
  name = "agent-vm";
  paths = [
    script
    (pkgs.runCommand "agent-vm-completions" { } ''
      install -Dm644 ${bashCompletion} $out/share/bash-completion/completions/agent-vm
      install -Dm644 ${zshCompletion} $out/share/zsh/site-functions/_agent-vm
    '')
  ];
}
