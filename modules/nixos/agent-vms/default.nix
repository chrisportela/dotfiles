{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.chrisportela.agent-vms;

  # Parse "192.168.83.1/24" -> "192.168.83.1"
  gatewayAddress = builtins.head (lib.splitString "/" cfg.bridge.subnet);

  templateSubmodule = lib.types.submodule {
    options = {
      workspace = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host directory to share via virtiofs";
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional nixpkgs attribute names to include";
      };
      credentials = lib.mkOption {
        type = lib.types.listOf credentialSubmodule;
        default = [ ];
        description = "Credential directories (mounted read-only)";
      };
      vcpu = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Override default vCPUs";
      };
      mem = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Override default RAM in MB";
      };
      varSize = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Override /var volume size in MB";
      };
      claude = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enable Claude Code";
      };
      dotfiles = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Mount dotfiles directory read-only";
      };
      direnv = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Enable direnv + nix-direnv";
      };
      copyWorkspace = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Copy workspace instead of sharing directly";
      };
      networkMode = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Network mode: default or restricted";
      };
      allowedDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domains allowed through proxy (spliced)";
      };
      interceptDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domains with TLS interception";
      };
      proxyBlockRegexes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "URL regexes to block on intercepted traffic";
      };
      allowSSH = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Allow outbound SSH in restricted mode";
      };
      parentRepoMode = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Parent repo access mode when workspace is a worktree: history | commit | full | none";
      };
    };
  };

  credentialSubmodule = lib.types.submodule {
    options = {
      source = lib.mkOption {
        type = lib.types.str;
        description = "Host path to credential directory";
      };
      mountPoint = lib.mkOption {
        type = lib.types.str;
        description = "Mount point inside the VM";
      };
    };
  };

  vmSubmodule = lib.types.submodule {
    options = {
      ipAddress = lib.mkOption {
        type = lib.types.str;
        description = "Static IP address on the bridge subnet";
      };
      mac = lib.mkOption {
        type = lib.types.str;
        description = "MAC address for the VM";
      };
      workspace = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host directory to share via virtiofs";
      };
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Start VM on boot";
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Additional packages in VM";
      };
      credentials = lib.mkOption {
        type = lib.types.listOf credentialSubmodule;
        default = [ ];
        description = "Credential directories (mounted read-only)";
      };
      vcpu = lib.mkOption {
        type = lib.types.int;
        default = cfg.defaults.vcpu;
        description = "Number of vCPUs";
      };
      mem = lib.mkOption {
        type = lib.types.int;
        default = cfg.defaults.mem;
        description = "RAM in MB";
      };
      varSize = lib.mkOption {
        type = lib.types.int;
        default = 51200;
        description = "/var volume size in MB";
      };
      extraShares = lib.mkOption {
        type = lib.types.listOf lib.types.attrs;
        default = [ ];
        description = "Additional virtiofs mounts";
      };
      claude = lib.mkOption {
        type = lib.types.bool;
        default = cfg.defaults.claude;
        description = "Enable Claude Code credential sharing for this VM";
      };
      copyWorkspace = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Copy workspace instead of sharing directly";
      };
      dotfiles = lib.mkOption {
        type = lib.types.bool;
        default = cfg.defaults.dotfiles;
        description = "Mount dotfiles directory read-only for this VM";
      };
      direnv = lib.mkOption {
        type = lib.types.bool;
        default = cfg.defaults.direnv;
        description = "Enable direnv + nix-direnv for this VM";
      };
      extraHomeModules = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
        description = "Additional home-manager modules for the VM user";
      };
      networkMode = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "Network mode: default or restricted";
      };
      allowedDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domains allowed through proxy (spliced)";
      };
      interceptDomains = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Domains with TLS interception";
      };
      proxyBlockRegexes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "URL regexes to block on intercepted traffic";
      };
      allowSSH = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow outbound SSH in restricted mode";
      };
      parentRepoPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host path to parent repo root. Set automatically for worktree workspaces via agent-vm create.";
      };
      parentRepoMode = lib.mkOption {
        type = lib.types.str;
        default = "commit";
        description = "Parent repo access mode: history | commit | full | none";
      };
    };
  };

  # Generate microvm.vms entries from declarative VM definitions
  mkVm = name: vmCfg: {
    inherit (vmCfg) autostart;
    config = {
      imports = [
        inputs.microvm.nixosModules.microvm
        ((import ./vm-base.nix) {
          hostName = name;
          inherit (vmCfg)
            ipAddress
            mac
            workspace
            packages
            credentials
            vcpu
            mem
            varSize
            extraShares
            ;
          inherit gatewayAddress;
          hypervisor = cfg.defaults.hypervisor;
          userName = cfg.user.name;
          inherit (cfg.user) uid gid authorizedKeys;
          sshHostKeyPath = "/var/lib/microvms/${name}/ssh-host-keys";
          homeManagerModule = inputs.home-manager.nixosModules.home-manager;
          inherit (vmCfg)
            copyWorkspace
            claude
            dotfiles
            direnv
            extraHomeModules
            networkMode
            allowedDomains
            interceptDomains
            proxyBlockRegexes
            allowSSH
            parentRepoPath
            parentRepoMode
            ;
          claudeConfigDir = cfg.defaults.claudeConfigDir;
          dotfilesDir = cfg.defaults.dotfilesDir;
        })
      ];
    };
  };
in
{
  # imports is top-level — cannot be inside lib.mkIf
  imports = [ inputs.microvm.nixosModules.host ];

  options.chrisportela.agent-vms = {
    enable = lib.mkEnableOption "agent VM host support";

    bridge = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "microbr";
        description = "Bridge device name";
      };
      subnet = lib.mkOption {
        type = lib.types.str;
        default = "192.168.83.1/24";
        description = "Bridge subnet (host gets .1)";
      };
    };

    nat.externalInterface = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Host interface to NAT through (required when enable = true)";
    };

    defaults = {
      vcpu = lib.mkOption {
        type = lib.types.int;
        default = 8;
        description = "Default vCPUs per VM";
      };
      mem = lib.mkOption {
        type = lib.types.int;
        default = 4096;
        description = "Default RAM in MB per VM";
      };
      hypervisor = lib.mkOption {
        type = lib.types.str;
        default = "cloud-hypervisor";
        description = "Default hypervisor";
      };
      claude = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Include Claude Code credential sharing in VMs by default";
      };
      claudeConfigDir = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user.name}/.claude";
        description = "Host path to .claude/ directory (mounted read-only into VMs)";
      };
      dotfiles = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Mount dotfiles directory read-only in VMs by default";
      };
      dotfilesDir = lib.mkOption {
        type = lib.types.str;
        default = "/home/${cfg.user.name}/src/dotfiles";
        description = "Host path to dotfiles directory (mounted read-only into VMs)";
      };
      direnv = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include direnv + nix-direnv in VMs by default";
      };
    };

    user = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "cmp";
        description = "Username inside VMs";
      };
      uid = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "UID inside VMs";
      };
      gid = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "GID inside VMs";
      };
      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH authorized keys for VM user";
      };
    };

    templates = lib.mkOption {
      type = lib.types.attrsOf templateSubmodule;
      default = { };
      description = "Named presets for ad-hoc VM creation (agent-vm create -t <name>)";
    };

    vms = lib.mkOption {
      type = lib.types.attrsOf vmSubmodule;
      default = { };
      description = "Declarative VM definitions";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.nat.externalInterface != "";
        message = "chrisportela.agent-vms.nat.externalInterface must be set when agent-vms is enabled";
      }
    ];

    # Bridge network device
    systemd.network.netdevs."20-${cfg.bridge.name}".netdevConfig = {
      Kind = "bridge";
      Name = cfg.bridge.name;
    };

    systemd.network.networks."20-${cfg.bridge.name}" = {
      matchConfig.Name = cfg.bridge.name;
      addresses = [ { Address = cfg.bridge.subnet; } ];
    };

    # Auto-bridge TAP interfaces created by microvm
    systemd.network.networks."21-microvm-tap" = {
      matchConfig.Name = "vm-*";
      networkConfig.Bridge = cfg.bridge.name;
    };

    # NAT for outbound VM traffic
    networking.nat = {
      enable = true;
      internalInterfaces = [ cfg.bridge.name ];
      externalInterface = cfg.nat.externalInterface;
    };

    # Trust the bridge in the firewall
    networking.firewall.trustedInterfaces = [ cfg.bridge.name ];

    # Generate declarative VMs
    microvm.vms = lib.mapAttrs mkVm cfg.vms;

    # Activation: generate SSH host keys and .ip files for declarative VMs,
    # and write .declarative-ips for ad-hoc IP collision avoidance
    system.activationScripts.agent-vm-setup = {
      text =
        let
          perVm = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: vm: ''
              VM_DIR="/var/lib/microvms/${name}"
              mkdir -p "$VM_DIR/ssh-host-keys"
              if [ ! -f "$VM_DIR/ssh-host-keys/ssh_host_ed25519_key" ]; then
                ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f "$VM_DIR/ssh-host-keys/ssh_host_ed25519_key" -q
              fi
              echo "${vm.ipAddress}" > "$VM_DIR/.ip"
              chown -R microvm:kvm "$VM_DIR"
            '') cfg.vms
          );
          ipsContent = lib.concatStringsSep "\\n" (lib.mapAttrsToList (_: vm: vm.ipAddress) cfg.vms);
        in
        ''
          mkdir -p /var/lib/microvms
          printf '%b\n' "${ipsContent}" > /var/lib/microvms/.declarative-ips
          ${perVm}
        '';
    };

    # Add agent-vm CLI tool
    environment.systemPackages = [
      (import ./agent-vm.nix {
        inherit pkgs lib inputs;
        inherit (cfg)
          bridge
          defaults
          user
          templates
          ;
      })
    ];
  };
}
