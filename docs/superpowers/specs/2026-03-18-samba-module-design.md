# Samba Module Design

## Overview

A NixOS module at `modules/nixos/samba/` that provides Samba file sharing with pre-baked share types and good cross-platform defaults for macOS, Windows, and Linux clients on LAN or Tailscale.

## Module Options

All options under `chrisportela.samba`:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable Samba file sharing |
| `users` | list of str | `[]` | Users to create as Samba users |
| `passwordFile` | path | required | Agenix-decrypted file with `user:password` per line |
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
| `public` | `false` | `true` | `true` | Create mask 0664, directory mask 0775 |
| `private` | `false` | `false` | `false` | Restricted to share's `users` list |

## Global Samba Configuration

The `[global]` section is configured with cross-platform defaults:

- **Server role**: `standalone`
- **Protocol range**: SMB2 minimum, SMB3 maximum (no SMBv1)
- **macOS compatibility**: `vfs objects = fruit catia streams_xattr`, `fruit:metadata = stream`, `fruit:model = MacSamba`
- **Character set**: UTF-8
- **Guest mapping**: `map to guest = Bad User`
- **Printing**: disabled
- **Logging**: syslog, level 1
- **Overrides**: `extraGlobalConfig` merges additional parameters

## Firewall & Network Integration

- **Firewall**: `openFirewall` option (default `false`) opens TCP 445/139 and UDP 137/138
- **Tailscale**: No extra config needed. The existing `network.nix` module already trusts `tailscale0` as a trusted interface, so Samba traffic flows freely over Tailscale regardless of `openFirewall`
- **LAN**: `openFirewall = true` needed for LAN clients not on Tailscale

## mDNS / Avahi Integration

When any share has `timeMachine = true`:

- Module asserts that `chrisportela.network.mDNS` is enabled (does not enable it automatically)
- Registers Avahi services:
  - `_smb._tcp` for general Samba discovery
  - `_adisk._tcp` with Time Machine share information for macOS auto-discovery

## User Management

### System Users

For each user in `chrisportela.samba.users`, the module ensures a system user exists via `users.users.<name>` with `isNormalUser = true` using `mkDefault` to avoid conflicts with existing user definitions.

### Samba Passwords

An activation script reads `passwordFile` (agenix-decrypted) and provisions Samba passwords:

1. Iterates lines in the password file (format: `user:password`)
2. For each entry, pipes the password to `smbpasswd -a -s <user>`
3. Runs on every system activation, so password changes propagate on rebuild

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
- **backup / private**: `d <path> 0770 <first-user> users -`

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
