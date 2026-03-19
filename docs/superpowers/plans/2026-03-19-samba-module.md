# Samba Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a NixOS module that provides Samba file sharing with pre-baked share types (media, backup, public, private) and good cross-platform defaults.

**Architecture:** Single NixOS module at `modules/nixos/samba/` using a `types.submodule` for share definitions with a `type` enum that sets per-type defaults. The module wraps `services.samba`, `systemd.tmpfiles`, `services.avahi`, and `system.activationScripts` with assertions for safety.

**Tech Stack:** NixOS module system, Samba, Avahi, agenix, systemd tmpfiles

**Spec:** `docs/superpowers/specs/2026-03-18-samba-module-design.md`

---

### Task 1: Create module skeleton with options

**Files:**
- Create: `modules/nixos/samba/default.nix`
- Modify: `modules/nixos/all.nix`

- [ ] **Step 1: Create the module file with all options defined**

Create `modules/nixos/samba/default.nix` with the full options tree but an empty `config` block. This establishes the interface before implementing behavior.

```nix
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.chrisportela.samba;

  shareSubmodule = lib.types.submodule {
    options = {
      type = lib.mkOption {
        type = lib.types.enum [ "media" "backup" "public" "private" ];
        description = "Share type. Sets default values for readOnly, guest, browseable, and extra smb.conf parameters.";
      };

      path = lib.mkOption {
        type = lib.types.str;
        description = "Directory to share.";
      };

      readOnly = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Override read-only setting. Defaults: media=true, others=false.";
      };

      guest = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Allow guest access. Defaults: media/public=true, backup/private=false.";
      };

      users = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Restrict to specific users. Empty means all samba users. Required for private type.";
      };

      timeMachine = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Advertise as Time Machine target. Only valid for backup type.";
      };

      createDir = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create directory via tmpfiles. Set false for existing dirs you want to manage yourself.";
      };

      extraConfig = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Raw smb.conf parameters to merge into this share section.";
      };
    };
  };
in
{
  options.chrisportela.samba = {
    enable = lib.mkEnableOption "Samba file sharing";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users to create as Samba users. Passwords managed via agenix.";
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Agenix-decrypted file with user:password per line.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open Samba ports (TCP 445, 139; UDP 137, 138) in the firewall.";
    };

    extraGlobalConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Additional [global] smb.conf parameters.";
    };

    shares = lib.mkOption {
      type = lib.types.attrsOf shareSubmodule;
      default = { };
      description = "Named share definitions.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Implemented in subsequent tasks
  };
}
```

- [ ] **Step 2: Add samba to all.nix imports**

In `modules/nixos/all.nix`, add `./samba` to the imports list:

```nix
imports = [
  ./agent-vms
  ./nixpkgs.nix
  ./common.nix
  ./network.nix
  ./openssh.nix
  ./gaming.nix
  ./ftp.nix
  ./cafecitocloud
  ./local-llm
  ./nginx-cloudflare.nix
  ./samba
];
```

- [ ] **Step 3: Verify it evaluates**

Run: `nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run 2>&1 | head -20`

This should evaluate without errors. No config is applied yet since `enable` defaults to `false`.

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/samba/default.nix modules/nixos/all.nix
git commit -m "feat(samba): add module skeleton with options"
```

---

### Task 2: Implement assertions

**Files:**
- Modify: `modules/nixos/samba/default.nix`

- [ ] **Step 1: Add assertions to the config block**

Replace the empty `config` block content with assertions. These catch invalid configurations at evaluation time:

```nix
config = lib.mkIf cfg.enable {
  assertions =
    [
      {
        assertion = cfg.passwordFile != null;
        message = "chrisportela.samba.passwordFile must be set when samba is enabled.";
      }
    ]
    ++ lib.mapAttrsToList (name: share: {
      assertion = share.type != "private" || share.users != [ ];
      message = "chrisportela.samba.shares.${name}: private shares must specify a non-empty users list.";
    }) cfg.shares
    ++ lib.mapAttrsToList (name: share: {
      assertion = !share.timeMachine || share.type == "backup";
      message = "chrisportela.samba.shares.${name}: timeMachine is only valid on backup type shares.";
    }) cfg.shares
    ++ lib.optional (lib.any (s: s.timeMachine) (lib.attrValues cfg.shares)) {
      assertion = config.chrisportela.network.mDNS;
      message = "chrisportela.network.mDNS must be enabled when any share has timeMachine = true.";
    };
};
```

- [ ] **Step 2: Verify evaluation still succeeds**

Run: `nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run 2>&1 | head -20`

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/samba/default.nix
git commit -m "feat(samba): add configuration assertions"
```

---

### Task 3: Implement global Samba config and share generation

**Files:**
- Modify: `modules/nixos/samba/default.nix`

- [ ] **Step 1: Add helper functions for share type defaults**

Add these helper functions inside the `let` block, after the `shareSubmodule` definition:

```nix
  # Resolve effective values per share, falling back to type defaults
  typeDefaults = {
    media  = { readOnly = true;  guest = true;  browseable = true;  };
    backup = { readOnly = false; guest = false; browseable = true;  };
    public = { readOnly = false; guest = true;  browseable = true;  };
    private = { readOnly = false; guest = false; browseable = false; };
  };

  resolveShare = name: share:
    let
      defaults = typeDefaults.${share.type};
      readOnly = if share.readOnly != null then share.readOnly else defaults.readOnly;
      guest = if share.guest != null then share.guest else defaults.guest;
      browseable = defaults.browseable;
    in
    {
      path = toString share.path;
      "read only" = if readOnly then "yes" else "no";
      "guest ok" = if guest then "yes" else "no";
      browseable = if browseable then "yes" else "no";
    }
    // lib.optionalAttrs (share.users != [ ]) {
      "valid users" = lib.concatStringsSep " " share.users;
    }
    // lib.optionalAttrs guest {
      "force user" = "nobody";
    }
    // lib.optionalAttrs (share.type == "media") {
      "follow symlinks" = "yes";
      "wide links" = "yes";
      "allow insecure wide links" = "yes";
    }
    // lib.optionalAttrs (share.type == "public") {
      "create mask" = "0664";
      "directory mask" = "0775";
    }
    // lib.optionalAttrs (share.type == "backup" && share.timeMachine) {
      "vfs objects" = "fruit catia streams_xattr";
      "fruit:time machine" = "yes";
    }
    // share.extraConfig;
```

- [ ] **Step 2: Add services.samba configuration to the config block**

Add after the assertions in the `config` block:

```nix
    services.samba = {
      enable = true;
      openFirewall = cfg.openFirewall;

      settings = {
        global = {
          "server role" = "standalone";
          "server min protocol" = "SMB2";
          "server max protocol" = "SMB3";
          "vfs objects" = "fruit catia streams_xattr";
          "fruit:metadata" = "stream";
          "fruit:model" = "MacSamba";
          "map to guest" = "Bad User";
          "load printers" = "no";
          printing = "bsd";
          "printcap name" = "/dev/null";
          "disable spoolss" = "yes";
          "unix charset" = "UTF-8";
          "dos charset" = "CP850";
          logging = "syslog";
          "log level" = "1";
        } // cfg.extraGlobalConfig;
      } // lib.mapAttrs resolveShare cfg.shares;
    };
```

- [ ] **Step 3: Verify evaluation**

Run: `nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run 2>&1 | head -20`

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/samba/default.nix
git commit -m "feat(samba): implement global config and share generation"
```

---

### Task 4: Implement user management and password provisioning

**Files:**
- Modify: `modules/nixos/samba/default.nix`

- [ ] **Step 1: Add system user creation to the config block**

Add after the `services.samba` block:

```nix
    # Ensure system users exist for samba users
    users.users = lib.genAttrs cfg.users (user: {
      isNormalUser = lib.mkDefault true;
    });
```

- [ ] **Step 2: Add smbpasswd activation script**

Add after the users block:

```nix
    # Provision samba passwords from agenix-decrypted file
    system.activationScripts.sambaPasswords = {
      deps = [ "users" ];
      text = ''
        while IFS=: read -r user pass; do
          # Skip empty lines and comments
          [ -z "$user" ] && continue
          [[ "$user" == \#* ]] && continue
          printf '%s\n%s\n' "$pass" "$pass" | ${pkgs.samba}/bin/smbpasswd -a -s "$user" 2>/dev/null
        done < ${cfg.passwordFile}
      '';
    };
```

- [ ] **Step 3: Verify evaluation**

Run: `nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run 2>&1 | head -20`

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/samba/default.nix
git commit -m "feat(samba): implement user management and password provisioning"
```

---

### Task 5: Implement tmpfiles directory management

**Files:**
- Modify: `modules/nixos/samba/default.nix`

- [ ] **Step 1: Add tmpfiles rules to the config block**

Add after the activation script:

```nix
    # Create share directories via tmpfiles
    systemd.tmpfiles.rules =
      let
        shareRules = lib.filterAttrs (_: s: s.createDir) cfg.shares;

        mkRule = name: share:
          let
            isUserScoped = share.type == "backup" || share.type == "private";
            owner =
              if share.users != [ ]
              then builtins.head share.users
              else "root";
            mode = if isUserScoped then "0770" else "0775";
          in
          "d ${toString share.path} ${mode} ${owner} users -";
      in
      lib.mapAttrsToList mkRule shareRules;
```

- [ ] **Step 2: Verify evaluation**

Run: `nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run 2>&1 | head -20`

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/samba/default.nix
git commit -m "feat(samba): implement tmpfiles directory management"
```

---

### Task 6: Implement firewall and Avahi/Time Machine integration

**Files:**
- Modify: `modules/nixos/samba/default.nix`

- [ ] **Step 1: Add Avahi Time Machine advertisement**

Add after the tmpfiles block. This only activates when any share has `timeMachine = true`:

```nix
    # Avahi service advertisement for Time Machine
    services.avahi.extraServiceFiles = lib.mkIf (lib.any (s: s.timeMachine) (lib.attrValues cfg.shares)) {
      smb = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h</name>
          <service>
            <type>_smb._tcp</type>
            <port>445</port>
          </service>
          <service>
            <type>_adisk._tcp</type>
            <txt-record>sys=waMa=0,adVF=0x100</txt-record>
            ${lib.concatStringsSep "\n          " (lib.imap0 (i: name:
              "<txt-record>dk${toString i}=adVN=${name},adVF=0x82</txt-record>"
            ) (lib.attrNames (lib.filterAttrs (_: s: s.timeMachine) cfg.shares)))}
          </service>
        </service-group>
      '';
    };
```

- [ ] **Step 2: Verify evaluation**

Run: `nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run 2>&1 | head -20`

- [ ] **Step 3: Commit**

```bash
git add modules/nixos/samba/default.nix
git commit -m "feat(samba): implement Avahi Time Machine advertisement"
```

---

### Task 7: Add README and enable on ada

**Files:**
- Create: `modules/nixos/samba/README.md`
- Modify: `hosts/nixos/ada/default.nix`

- [ ] **Step 1: Create README.md**

Create `modules/nixos/samba/README.md`:

```markdown
# Samba File Sharing Module

Network file sharing with pre-baked share types for cross-platform access (macOS, Windows, Linux) over LAN and Tailscale.

## Options

All options under `chrisportela.samba`:

- `enable` — Enable Samba file sharing
- `users` — List of Samba user names (passwords via agenix)
- `passwordFile` — Path to agenix-decrypted file with `user:password` per line
- `openFirewall` — Open Samba ports in firewall (default: false, not needed for Tailscale)
- `extraGlobalConfig` — Additional smb.conf global parameters
- `shares.<name>` — Share definitions (see Share Types below)

### Share Options

- `type` — One of: `media`, `backup`, `public`, `private`
- `path` — Directory to share
- `readOnly` — Override read-only (default: per-type)
- `guest` — Allow guest access (default: per-type)
- `users` — Restrict to specific users (required for `private`)
- `timeMachine` — Advertise as Time Machine target (`backup` type only, requires `network.mDNS`)
- `createDir` — Create directory via tmpfiles (default: true)
- `extraConfig` — Raw smb.conf parameters

### Share Types

| Type    | readOnly | guest | browseable | Notes                                     |
|---------|----------|-------|------------|-------------------------------------------|
| media   | yes      | yes   | yes        | Follow symlinks, streaming-optimized       |
| backup  | no       | no    | yes        | Optional Time Machine via `timeMachine`    |
| public  | no       | yes   | yes        | Create mask 0664, dir mask 0775            |
| private | no       | no    | no         | Must specify `users`                       |

## Dependencies

- `chrisportela.network.mDNS` — Required when any share uses `timeMachine = true`
- Agenix — For password management

## Example

```nix
chrisportela.samba = {
  enable = true;
  openFirewall = true;
  users = [ "cmp" ];
  passwordFile = config.age.secrets.samba-passwords.path;

  shares = {
    movies = { type = "media"; path = "/data/movies"; };
    backups = { type = "backup"; path = "/data/backups"; timeMachine = true; };
    public = { type = "public"; path = "/srv/share"; };
    docs = { type = "private"; path = "/data/docs"; users = [ "cmp" ]; };
  };
};
```
```

- [ ] **Step 2: Add samba config to ada host**

In `hosts/nixos/ada/default.nix`, add inside the `chrisportela` block (after `agent-vms`):

```nix
          samba = {
            enable = false; # Enable after creating agenix secret (Task 8)
            openFirewall = true;
            users = [ "cmp" ];
            # passwordFile = config.age.secrets.samba-passwords.path;
          };
```

Note: `enable` is `false` and `passwordFile` is commented out. Both must be fixed in Task 8 after creating the agenix secret.

- [ ] **Step 3: Verify full build**

Run: `nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run 2>&1 | head -20`

- [ ] **Step 4: Commit**

```bash
git add modules/nixos/samba/README.md hosts/nixos/ada/default.nix
git commit -m "feat(samba): add README and ada host configuration"
```

---

### Task 8: Create agenix secret and do final integration

**Files:**
- Modify: `hosts/nixos/ada/default.nix`
- Modify: `secrets/secrets.nix` (if this is the agenix key registry)

This task requires the user's involvement since it involves creating an encrypted secret.

- [ ] **Step 1: Identify agenix secret structure**

Check `secrets/` directory for existing patterns and `secrets.nix` for the key registry.

- [ ] **Step 2: Create samba password secret**

The user needs to run:
```bash
echo "cmp:YOUR_PASSWORD_HERE" > /tmp/samba-passwords
agenix -e secrets/samba-passwords.age < /tmp/samba-passwords
rm /tmp/samba-passwords
```

- [ ] **Step 3: Register secret in secrets.nix and reference in ada config**

In `secrets/secrets.nix`, add:
```nix
"samba-passwords.age".publicKeys = sshKeys.secrets ++ [ ];
```

In `hosts/nixos/ada/default.nix`, add the agenix secret declaration and update the samba block:
```nix
age.secrets.samba-passwords.file = ../../secrets/samba-passwords.age;
```
Then uncomment `passwordFile` and set `enable = true`.

- [ ] **Step 4: Verify full build**

Run: `nix build .#nixosConfigurations.ada.config.system.build.toplevel --dry-run 2>&1 | head -20`

- [ ] **Step 5: Commit**

```bash
git add secrets/ hosts/nixos/ada/default.nix
git commit -m "feat(samba): add agenix secret and enable on ada"
```
