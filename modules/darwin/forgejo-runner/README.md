# forgejo-runner (darwin)

Runs a [Forgejo Actions](https://forgejo.org/docs/latest/admin/actions/) runner
as a launchd daemon on a macOS host, using the **native** backend (jobs execute
directly on the host — no Docker). This is what gives CI real `aarch64-darwin`
builds: the linux runner fleet (liara/lucy/ada, managed in the infra repo) has
no darwin member, so lux advertises the `darwin` labels and picks up the
`darwin`/`hosts-darwin` jobs from `.forgejo/workflows/ci.yml`.

## Options (`chrisportela.forgejo-runner`)

| Option | Default | Purpose |
| --- | --- | --- |
| `enable` | `false` | Enable the daemon. |
| `serverUrl` | `https://git.cafecito.cloud` | Forgejo instance (tailnet-only; the host must be on the tailnet). |
| `name` | hostname | Runner display name. |
| `labels` | `<host>-darwin:host`, `darwin:host`, `nix-darwin:host` | Labels advertised to Forgejo. Synced from the config file at startup — changing them does **not** re-register. |
| `timeout` / `capacity` | `3h` / `1` | Per-job wall clock limit / concurrent jobs. |
| `uuid` | — | UUID of the pre-registered runner (not sensitive). |
| `secretFile` | — | Runtime path to the raw 40-hex shared secret (use an agenix secret, `owner` = `user`). |
| `user` | `cmp` | macOS user jobs run as. |
| `stateDir` | `/var/lib/forgejo-runner` | Registration state, workspaces, logs (`logs/runner*.log`). |
| `extraPackages` | `[ ]` | Extra tools on the job PATH. |

## Registration semantics (declarative pre-registered runner, v12+)

There is no registration step on the runner at all — the deprecated
`register` and `create-runner-file` commands are not used. The connection is
declared in the generated config file (`server.connections.cafecito`) with
the instance `url`, the runner `uuid`, and `token_url: file:<secretFile>`,
which forgejo-runner v12+ reads directly:

1. Generate the shared secret: `openssl rand -hex 20`.
2. Pre-register it server-side (liara):
   `forgejo-cli actions register --name lux --secret <secret>` — this
   prints the runner UUID (derived from the secret's first 32 hex chars,
   formatted 8-4-4-4-12).
3. Set `uuid` in the host config (it is not sensitive) and encrypt the
   secret as the agenix secret referenced by `secretFile`
   (`cd secrets && agenix -e lux-forgejo-runner-secret.age`; replaces the
   committed placeholder).

The runner identity is fully determined by the config, so rotating the
secret is: re-register server-side, re-encrypt, update `uuid` if it
changed, and `sudo launchctl kickstart -k
system/cloud.cafecito.forgejo-runner`. Labels live in `runner.labels` in
the same config and never touch registration.

## Dependencies

- Host must reach `serverUrl` (tailscale).
- `nix` on the job PATH is the client for the host nix-daemon; builds run as
  the daemon's build users as usual.
- JS actions (e.g. `actions/checkout`) need `node` — provided on the PATH.
- Pairs with `modules/darwin/nix-cache-push` so everything jobs build gets
  pushed to the niks3 cache.
