# aws-client-vpn

Connects to an AWS Client VPN endpoint that uses **SAML federated
authentication**, on Linux, without the proprietary AWS VPN Client.

```bash
nix run .#aws-client-vpn -- --config ~/vpn.ovpn
```

## Why AWS needs its own OpenVPN

AWS Client VPN is OpenVPN underneath, but the SAML flow is not stock OpenVPN.
Two separate things are going on, and only one of them is a protocol change.

**1. The SAML assertion is sent as the OpenVPN password.** There is no field in
the OpenVPN handshake designed to carry a signed SAML assertion, so AWS puts the
whole base64 blob — commonly 10–100 KB — into the password. Upstream OpenVPN
caps a password at 128 bytes (`USER_PASS_LEN`), and everything that blob passes
through on its way out is sized to match: the option parser (`OPTION_PARM_SIZE`,
256), the TLS control channel (`TLS_CHANNEL_BUF_SIZE`, 2 KB), the generic buffer
ceiling (`BUF_SIZE_MAX`, 1 MB), the error and management buffers. AWS raised all
of them (password to 128 KB, control channel to 256 KB, buffer ceiling to 2 MB).
A stock binary does not merely refuse a long password, it truncates or fails in
the TLS layer partway through the handshake.

**2. The control-channel format changed.** In `key_method_2_write`, the strings
in the payload carry a `uint16` length prefix upstream; AWS made them `uint32`,
and overwrites the leading four-byte zero of the payload with its total length.
That is a wire-format change, so the patched binary and a stock OpenVPN server
**cannot talk to each other in either direction**. This is why the build here
installs its binary as `openvpn-aws` and keeps it off `$PATH`: it is not a
drop-in `openvpn`, and pointing it at a normal VPN will fail in confusing ways.

The patch in `openvpn-aws-2.6.patch` is AWS's own, from the modified OpenVPN
sources they publish for GPL compliance (linked from the Windows/macOS client's
"About" box). It is carried in the community clients — `samm-git/aws-vpn-client`,
`dzervas/aws-client-vpn-flake` — and this is the same change, refreshed for the
2.6 series. It applies cleanly to OpenVPN 2.6.19 (nixpkgs 25.11) and 2.6.21.

Note that **none of this applies to certificate-based (mutual TLS) endpoints**.
Those work with the `openvpn` in nixpkgs and need nothing from this package.

## How the connection is made

The proprietary client drives a two-phase handshake, and so does this:

1. Resolve `<random hex>.<endpoint host>` to a single address. AWS asks clients
   to prefix a random label so sessions spread across the endpoint's hosts; both
   phases have to reach the *same* host, so the address is resolved once and
   pinned for the rest of the run.
2. Connect with username `N/A` and password `ACS::35001`. This is meant to fail.
   The endpoint's `AUTH_FAILED` reply carries an OpenVPN dynamic challenge:

   ```
   AUTH_FAILED,CRV1:<flags>:<session id>:<base64 username>:<login URL>
   ```

3. Open the login URL in a browser and listen on `127.0.0.1:35001`. After the
   identity provider is satisfied it redirects the browser to an HTTP POST at
   that port whose `SAMLResponse` field holds the assertion. The port is not
   configurable on AWS's side — 35001 is what the endpoint expects.
4. Connect again, username `N/A`, password `CRV1::<session id>::<assertion>`.
   This one is run under `sudo`, because it creates the tun device and routes.

The endpoint's own profile lists `auth-federate`, `auth-user-pass` and
`auth-retry interact`, which exist for the proprietary client and confuse a
command-line OpenVPN, so a sanitised copy of the profile is used for both phases
with those lines and `remote`/`remote-random-hostname` removed. Certificate
checks (`remote-cert-tls`, `verify-x509-name`) are left untouched.

## Usage

```
aws-client-vpn [options] [-- <extra openvpn arguments>]

  -c, --config FILE    Profile exported from the endpoint. Defaults to
                       $AWS_VPN_CONFIG, else
                       ~/.config/aws-client-vpn/<endpoint>.ovpn
  -e, --endpoint ID    Endpoint id; used to export the profile with the AWS CLI
                       when the config file does not exist yet
  -p, --profile NAME   AWS CLI profile for that export (default: $AWS_PROFILE)
  -r, --region NAME    AWS region for that export (default: $AWS_REGION)
      --port PORT      Loopback port for the assertion (default: 35001)
      --timeout SECS   How long to wait for the browser login (default: 180)
      --dns MODE       auto | systemd-resolved | none (default: auto)
      --no-browser     Print the login URL instead of opening a browser
  -h, --help
```

Set `AWS_CLIENT_VPN_DEBUG=1` to dump the first phase's OpenVPN log when the
challenge cannot be parsed.

Getting a profile, if you do not already have one:

```bash
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id cvpn-endpoint-0123456789abcdef \
  --output text > ~/.config/aws-client-vpn/default.ovpn
```

or let `--endpoint cvpn-endpoint-0123456789abcdef` do it, which needs the AWS
CLI on `$PATH` and credentials that can call `ec2:ExportClientVpnClientConfiguration`.

### DNS

AWS endpoints push DNS servers. With `--dns auto` (the default) they are handed
to `systemd-resolved` through OpenVPN's `update-systemd-resolved` helper when
resolved is running; otherwise the push is ignored and the run says so. Pass
`--dns none` to silence it, or `--dns systemd-resolved` to require it.

### Shell completion

Completions ship for bash, zsh, fish and nushell, installed to the usual
places, so any of them picks them up when this package is in the environment.
They complete flag names and:

| Flag | Candidates |
| --- | --- |
| `--profile` | profiles from `~/.aws/config` (`[profile NAME]`, plus `[default]`) and every section of `~/.aws/credentials`. `[sso-session …]` and `[services …]` are not profiles and are skipped. `AWS_CONFIG_FILE` and `AWS_SHARED_CREDENTIALS_FILE` are honoured. |
| `--config` | the `*.ovpn` files already in the profile directory, then ordinary path completion |
| `--endpoint` | endpoint ids of those same files, minus `default`. Completing live endpoints would mean an `ec2:DescribeClientVpnEndpoints` call per keystroke, so it is deliberately limited to what has been exported before. |
| `--region` | the regions named in `~/.aws/config`, rather than a hardcoded list that would go stale |
| `--dns` | `auto`, `systemd-resolved`, `none` |

The candidates come from `aws-client-vpn __complete <kind>`, a hidden helper
kept out of `--help`, mirroring `wt __complete`. It never exits non-zero: a
completion that errors is worse than one that offers nothing.

### Secrets on disk

The assertion is a bearer credential. It is written to a `0600` file in a
`0700` directory under `$XDG_RUNTIME_DIR` (a tmpfs) and removed when the process
exits — including on Ctrl-C. It is never passed as an argument or an environment
variable, both of which are world-readable through `/proc`.

## Dependencies

- `openvpn` from nixpkgs, rebuilt with `openvpn-aws-2.6.patch`
- `python3` — resolves the endpoint and runs the loopback listener
- `xdg-utils` — opens the browser; `--no-browser` if it is not wanted
- `coreutils`, `gnugrep`, `gawk` (the latter parses the AWS config for completions)
- `sudo` at runtime, for the second phase only
- `awscli2` at runtime, only for `--endpoint`
- `systemd` and `iproute2` at runtime, only for `--dns systemd-resolved`

## Files

- `default.nix` — the patched `openvpn-aws` build and the wrapper
- `openvpn-aws-2.6.patch` — AWS's OpenVPN patch, for the 2.6 series
- `aws-client-vpn.sh` — the handshake, as a standalone script
- `saml-listener.py` — the `127.0.0.1:35001` listener
- `completions/` — bash, zsh, fish and nushell completions
- `tests/test-connect-flow.sh` — end-to-end test of the handshake against stubs
- `tests/test-completions.sh` — completion tests against a fake AWS setup

## Tests

```bash
./tests/test-connect-flow.sh
./tests/test-completions.sh
```

`test-connect-flow.sh` runs the real script with a stub OpenVPN that answers
with an `AUTH_FAILED` challenge, a stub resolver, and a curl standing in for the
identity provider, then asserts on what the second phase would have sent.

`test-completions.sh` drives the completion scripts against a fake `HOME` with
an AWS config, a credentials file and exported profiles. bash is required; zsh,
fish and nushell are exercised when installed and skipped otherwise:

```bash
nix shell nixpkgs#zsh nixpkgs#fish nixpkgs#nushell \
  --command ./tests/test-completions.sh
```

Neither test needs the network or root.

## Alternatives

- **AWS Client VPN for Linux**, AWS's own build, ships as an Ubuntu `.deb` with
  a bundled `acvc-openvpn` and a systemd service. It has never been packaged in
  nixpkgs.
- **`dzervas/aws-client-vpn-flake`**, archived in October 2025, is the flake this
  package started from.
