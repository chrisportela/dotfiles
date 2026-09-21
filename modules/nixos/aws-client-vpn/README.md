# aws-client-vpn (NixOS)

Installs the [`aws-client-vpn`](../../../pkgs/aws-client-vpn/README.md) client
system-wide, for AWS Client VPN endpoints that use SAML federated
authentication. Certificate-based endpoints do not need this — plain
`pkgs.openvpn` handles those.

## Options

- `chrisportela.aws-client-vpn.enable` — install the client and make sure the
  `tun` module is loaded.
- `chrisportela.aws-client-vpn.package` — the package to install
  (default: `pkgs.aws-client-vpn`).
- `chrisportela.aws-client-vpn.awscli` — also install `awscli2`, which
  `aws-client-vpn --endpoint <id>` uses to export a profile from an endpoint
  (default: `true`). Turn it off when the `.ovpn` profile is supplied by hand.

## Usage

```nix
chrisportela.aws-client-vpn.enable = true;
```

Then, as a normal user:

```bash
aws-client-vpn --config ~/.config/aws-client-vpn/default.ovpn
```

The tunnel itself runs under `sudo`; nothing is installed as a service, so a
connection lasts only as long as the foreground command.

## Dependencies

- `pkgs.aws-client-vpn` via the overlay in `overlays/default.nix`
- `sudo` — enabled by default on NixOS; the second phase of the handshake needs
  root to create the tun device and install routes
- `services.resolved` — optional. When it is running, DNS servers pushed by the
  endpoint are applied through OpenVPN's `update-systemd-resolved` helper;
  `modules/nixos/network.nix` enables it.
