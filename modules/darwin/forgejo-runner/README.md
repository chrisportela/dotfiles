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
| `tokenFile` | — | Runtime path to the raw registration token (use an agenix secret, `owner` = `user`). |
| `user` | `cmp` | macOS user jobs run as. |
| `stateDir` | `/var/lib/forgejo-runner` | Registration state, workspaces, logs (`logs/runner*.log`). |
| `extraPackages` | `[ ]` | Extra tools on the job PATH. |

## Registration semantics

Upstream `forgejo-runner` mints a **new server-side runner identity** every
time `register` runs, orphaning the old row in the Forgejo admin UI. The
daemon script therefore only registers when there is no `.runner` file yet or
the token content actually changed (tracked via a sha256 in
`<stateDir>/.token-hash`). Ported from the infra repo's NixOS
`forgejo-runner.nix`.

To force a re-registration: delete `<stateDir>/.runner` and `.token-hash`,
then `sudo launchctl kickstart -k system/cloud.cafecito.forgejo-runner`.

## Getting a token

Forgejo → Site/Org/Repo settings → Actions → Runners → Create registration
token. Encrypt it as the agenix secret referenced by `tokenFile` (see
`secrets/secrets.nix`; the placeholder committed there must be replaced with
`agenix -e <name>.age` before the runner can register).

## Dependencies

- Host must reach `serverUrl` (tailscale).
- `nix` on the job PATH is the client for the host nix-daemon; builds run as
  the daemon's build users as usual.
- JS actions (e.g. `actions/checkout`) need `node` — provided on the PATH.
- Pairs with `modules/darwin/nix-cache-push` so everything jobs build gets
  pushed to the niks3 cache.
