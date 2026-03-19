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
