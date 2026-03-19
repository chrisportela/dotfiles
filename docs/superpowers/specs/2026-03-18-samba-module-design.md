# Samba Module Design

## Overview

A NixOS module at `modules/nixos/samba/` that provides Samba file sharing with pre-baked share types and good cross-platform defaults for macOS, Windows, and Linux clients on LAN or Tailscale.

## Module Options

All options under `chrisportela.samba`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Samba file sharing |
| `users` | list of str | `[]` | Users to create as Samba users |
| `passwordFile` | path | required when enabled | Agenix-decrypted file with `user:password` per line |
| `openFirewall` | bool | `false` | Open Samba ports (TCP 445, 139; UDP 137, 138) in firewall |
| `extraGlobalConfig` | attrsOf str | `{}` | Additional `[global]` smb.conf parameters |
| `shares` | attrsOf shareModule | `{}` | Named share definitions |

### Share Options (`shares.<name>`)

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `type` | enum | required | One of: `media`, `backup`, `public`, `private` |
| `path` | path | required | Directory to share |
| `readOnly` | bool | per-type | Override read-only setting |
| `guest` | bool | per-type | Allow guest/anonymous access |
| `users` | list of str | `[]` (all samba users) | Restrict access to specific users |
| `timeMachine` | bool | `false` | Advertise as Time Machine target (backup type only) |
| `createDir` | bool | `true` | Create directory via tmpfiles (set false for existing dirs) |
| `extraConfig` | attrsOf str | `{}` | Raw smb.conf parameters to merge into this share |

### Share Type Defaults

| Type | readOnly | guest | browseable | Extra behavior |
|------|----------|-------|------------|----------------|
| `media` | `true` | `true` | `true` | Follow symlinks, wide links, optimized read buffers |
| `backup` | `false` | `false` | `true` | Optional Time Machine via fruit VFS + Avahi advertisement |
| `public` | `false` | `true` | `true` | Create mask 0664, directory mask 0775, `force user = nobody` |
| `private` | `false` | `false` | `false` | Restricted to share's `users` list (must be non-empty) |

### Assertions

- `passwordFile` must be set when `enable = true`
- `private` type shares must have a non-empty `users` list
- `timeMachine = true` is only valid on `backup` type shares
- When any share has `timeMachine = true`, `chrisportela.network.mDNS` must be enabled

## Global Samba Configuration

Sets `services.samba.enable = true` and configures the `[global]` section with cross-platform defaults:

- **Server role**: `standalone`
- **Protocol range**: SMB2 minimum, SMB3 maximum (no SMBv1)
- **macOS compatibility**: `vfs objects = fruit catia streams_xattr`, `fruit:metadata = stream`, `fruit:model = MacSamba`
- **Character set**: UTF-8
- **Guest mapping**: `map to guest = Bad User`
- **Printing**: disabled
- **Logging**: syslog, level 1
- **Overrides**: `extraGlobalConfig` merges additional parameters

## smb.conf Share Mapping

Each share's options map to smb.conf parameters:

- `readOnly` → `read only = yes/no`
- `guest` → `guest ok = yes/no`; when `true`, also sets `force user = nobody` for safe anonymous writes
- `users` (non-empty) → `valid users = user1 user2 ...`
- `extraConfig` → merged as raw key-value pairs

## Firewall & Network Integration

- **Firewall**: `openFirewall` option (default `false`) opens TCP 445/139 and UDP 137/138
- **Tailscale**: No extra config needed. The existing `network.nix` module already trusts `tailscale0` as a trusted interface, so Samba traffic flows freely over Tailscale regardless of `openFirewall`
- **LAN**: `openFirewall = true` needed for LAN clients not on Tailscale

## mDNS / Avahi Integration

When any share has `timeMachine = true`:

- Module asserts that `chrisportela.network.mDNS` is enabled (does not enable it automatically)
- Registers Avahi services via `services.avahi.extraServiceFiles`:
  - `_smb._tcp` service on port 445 for general Samba discovery
  - `_adisk._tcp` service with TXT records per Time Machine share following Apple's Bonjour spec (e.g., `dk0=adVN=<share-name>,adVF=0x82`)

## User Management

### System Users

For each user in `chrisportela.samba.users`, the module ensures a system user exists via `users.users.<name>` with `isNormalUser = mkDefault true`. The entire user block uses `mkDefault` so existing user definitions (like the `cmp` user in ada's host config) take full precedence.

### Samba Passwords

An activation script reads `passwordFile` (agenix-decrypted) and provisions Samba passwords:

1. Uses `system.activationScripts.sambaPasswords.deps = [ "users" ]` to ensure it runs after system user creation
2. Iterates lines in the password file (format: `user:password`)
3. For each entry, pipes the password to `${pkgs.samba}/bin/smbpasswd -a -s <user>` (full path, no PATH dependency)
4. Runs on every system activation, so password changes propagate on rebuild

### Agenix Integration

```nix
# In host config:
age.secrets.samba-passwords.file = ./secrets/samba-passwords.age;

chrisportela.samba = {
  enable = true;
  users = [ "cmp" ];
  passwordFile = config.age.secrets.samba-passwords.path;
};
```

## Directory Management

Share directories are managed via `systemd.tmpfiles.rules` (when `createDir = true`):

- **media / public**: `d <path> 0775 root users -`
- **backup / private**: `d <path> 0770 <owner> users -` where `<owner>` is the first entry in the share's `users` list, or `root` if `users` is empty

The `d` rule creates the directory if missing and adjusts ownership/permissions on existing ones. Set `createDir = false` to skip tmpfiles entirely for shares with pre-existing directories where you want to preserve current ownership.

## Example Configuration

```nix
chrisportela.samba = {
  enable = true;
  openFirewall = true;
  users = [ "cmp" ];
  passwordFile = config.age.secrets.samba-passwords.path;

  shares = {
    movies = {
      type = "media";
      path = "/data/movies";
    };

    tv = {
      type = "media";
      path = "/data/tv";
    };

    backups = {
      type = "backup";
      path = "/data/backups";
      timeMachine = true;
    };

    public = {
      type = "public";
      path = "/srv/share";
    };

    documents = {
      type = "private";
      path = "/data/documents";
      users = [ "cmp" ];
    };
  };
};
```

## Module File Structure

```
modules/nixos/samba/
  default.nix    # Module implementation
  README.md      # Purpose, options, dependencies, examples
```

The module is imported via `modules/nixos/all.nix` and enabled per-host.
