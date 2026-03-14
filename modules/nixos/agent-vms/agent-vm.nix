# agent-vm.nix
# Produces the `agent-vm` CLI tool as a derivation.
{
  pkgs,
  lib,
  inputs,
  bridge,
  defaults,
  user,
}:
let
  # Bake in flake input revisions (direct attributes on locked inputs)
  microvmRev = inputs.microvm.rev;
  nixpkgsRev = inputs.nixpkgs.rev;

  # Parse gateway from subnet ("192.168.83.1/24" -> "192.168.83.1")
  gatewayAddress = builtins.head (lib.splitString "/" bridge.subnet);

  # Parse subnet prefix robustly ("192.168.83.1" -> "192.168.83")
  gatewayOctets = lib.splitString "." gatewayAddress;
  subnetPrefix = lib.concatStringsSep "." (lib.take 3 gatewayOctets);

  # Read vm-base.nix content to embed in generated flakes
  vmBaseContent = builtins.readFile ./vm-base.nix;
in
pkgs.writeShellScriptBin "agent-vm" ''
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

Create flags:
  --workspace <path>              Host directory to share
  --packages <pkg1,pkg2,...>      Additional nixpkgs to include
  --credentials <source:mount>    Credential share (repeatable)
  --vcpu <n>                      Override default vCPUs
  --mem <n>                       Override default RAM
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

  cmd_create() {
    local name="$1"; shift
    local workspace=""
    local packages=""
    local vcpu="$DEFAULT_VCPU"
    local mem="$DEFAULT_MEM"
    local credentials=()

    while [ $# -gt 0 ]; do
      case "$1" in
        --workspace) workspace="$2"; shift 2 ;;
        --packages) packages="$2"; shift 2 ;;
        --vcpu) vcpu="$2"; shift 2 ;;
        --mem) mem="$2"; shift 2 ;;
        --credentials) credentials+=("$2"); shift 2 ;;
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

    # Build workspace share Nix expression
    local workspace_nix="null"
    if [ -n "$workspace" ]; then
      workspace_nix="\"$workspace\""
    fi

    # Build credentials Nix expression
    local creds_nix="[ ]"
    if [ ''${#credentials[@]} -gt 0 ]; then
      creds_nix="["
      for cred in "''${credentials[@]}"; do
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

    # Copy vm-base.nix into the VM directory
    sudo tee "$vm_dir/vm-base.nix" > /dev/null <<'VMBASE'
${vmBaseContent}
VMBASE

    # Generate flake.nix
    sudo tee "$vm_dir/flake.nix" > /dev/null <<FLAKE
{
  inputs = {
    nixpkgs.url = "$NIXPKGS_URL";
    microvm = {
      url = "$MICROVM_URL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, microvm, ... }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in
  {
    nixosConfigurations.$name = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        microvm.nixosModules.microvm
        ((import ./vm-base.nix) {
          hostName = "$name";
          ipAddress = "$ip";
          mac = "$mac";
          gatewayAddress = "$GATEWAY";
          vcpu = $vcpu;
          mem = $mem;
          hypervisor = "$DEFAULT_HYPERVISOR";
          workspace = $workspace_nix;
          credentials = $creds_nix;
          packages = $pkgs_nix;
          userName = "$USER_NAME";
          uid = $USER_UID;
          gid = $USER_GID;
          authorizedKeys = $keys_nix;
          sshHostKeyPath = "$vm_dir/ssh-host-keys";
        })
      ];
    };

    # Required by microvm.nix for imperative VMs
    packages.''${system}.default = self.nixosConfigurations.$name.config.microvm.declaredRunner;
  };
}
FLAKE

    echo "VM '$name' created."
    echo "  IP: $ip"
    echo "  Dir: $vm_dir"
    echo "  Start with: agent-vm start $name"
  }

  cmd_start() {
    local name="$1"
    echo "Starting VM '$name'..."
    sudo systemctl start "microvm@$name"
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
    exec ${pkgs.openssh}/bin/ssh \
      -o StrictHostKeyChecking=accept-new \
      -o UserKnownHostsFile="$vm_dir/known_hosts" \
      "$USER_NAME@$ip" "$@"
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
''
