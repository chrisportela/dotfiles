# forgejo-runner (NixOS)

Runs one or more [Forgejo Actions](https://forgejo.org/docs/latest/admin/actions/)
runners as systemd services, wrapping nixpkgs' `services.gitea-actions-runner`
with the declarative uuid+token connection flow (no `register` step). Ported
from the infra repo's `cafecito.forgejoRunners` module so dotfiles-managed
hosts can join the fleet — the NixOS sibling of `modules/darwin/forgejo-runner`.

flamme uses it to serve the shared `nix-docker` label (docker backend, host
`/nix/store` + nix-daemon shared into job containers), the same shape as
lucy's `nix-docker` instance in the infra repo.

## Options (`chrisportela.forgejo-runner`)

| Option | Default | Purpose |
| --- | --- | --- |
| `enable` | `false` | Enable the runners. |
| `serverUrl` | `https://git.cafecito.cloud` | Forgejo instance (tailnet-only; the host must be on the tailnet). |
| `instances.<name>` | `{ }` | One attrset per runner daemon. |
| `slice.enable` | `false` | Put every runner daemon (`Slice=`) and its docker job containers (`--cgroup-parent`) in one `forgejo-runner.slice`, managed by systemd-oomd. |
| `slice.memoryMax` / `slice.memoryHigh` | — | Hard ceiling / soft throttle threshold for that slice as a whole. |

Per instance:

| Option | Default | Purpose |
| --- | --- | --- |
| `enable` | `true` | Enable this instance. |
| `name` | attr name | Runner display name on the server. |
| `backend` | `docker` | `docker` (jobs in containers) or `native` (jobs on the host). |
| `uuid` | — | UUID of the pre-created runner (not sensitive). |
| `tokenFile` | — | Runtime path (agenix) to a file containing `TOKEN=<40-hex secret>`. |
| `labels` | — | Labels advertised to Forgejo; synced from config on startup, changes do **not** re-register. |
| `timeout` / `capacity` | `3h` / `1` | Per-job wall clock limit / concurrent jobs. |
| `docker.shareHostNixStore` | `false` | Mount host `/nix/store` (ro) + nix-daemon socket into job containers, `NIX_REMOTE=daemon`. Grants effective host-store write — trusted workloads only. |
| `docker.shareHostCAs` | `false` | Mount the host CA bundle and set `SSL_CERT_FILE`/`NODE_EXTRA_CA_CERTS` in containers (internal-CA TLS, e.g. git.cafecito.cloud). |
| `docker.extraHosts` | `[ ]` | `--add-host=<name>:host-gateway` entries for names the host resolves to loopback. |
| `docker.networkMode` | `bridge` | Docker network mode. |
| `native.packages` | `[ ]` | Extra packages on the job PATH (native backend). |

## Registration semantics (declarative pre-registered runner)

Identical to the darwin module: no registration command ever runs on the
host. The generated config declares `server.connections.forgejo` with the
instance `url`, the runner `uuid`, and the token. The token is kept out of
the world-readable store config via an `@FORGEJO_RUNNER_TOKEN@` placeholder:
an `ExecStartPre` renders the real config into the instance's private state
directory from the systemd `EnvironmentFile` (`tokenFile`).

1. Generate the shared secret: `openssl rand -hex 20`.
2. Pre-register it server-side (liara):
   `forgejo-cli actions register --name <name> --secret <secret>` — prints
   the runner UUID (minted server-side; also visible in the forgejo DB's
   `action_runner` table).
3. Set `uuid` in the host config and encrypt `TOKEN=<secret>` as the agenix
   secret referenced by `tokenFile`.

Rotation: re-register server-side, re-encrypt, update `uuid`, and
`systemctl restart gitea-runner-<name>` (systemd escapes dashes:
`gitea-runner-flamme\x2ddocker.service`).

## Memory containment (`slice`)

A CI job's memory lives in up to three cgroups, and `slice` covers only the
first two:

1. the runner daemon (`gitea-runner-<name>.service`), which is tiny;
2. the job container, which by default is a child of **dockerd**
   (`system.slice`), not of the runner service, so capping the service alone
   caps nothing. `--cgroup-parent=forgejo-runner.slice` re-parents it. This
   relies on docker's systemd cgroup driver, the NixOS default on cgroup v2;
3. **nix builds** a `shareHostNixStore` job starts through the daemon socket,
   which run in `nix-daemon.service`. Bound them with
   `chrisportela.memory-protection.nixDaemon` and the host's
   `nix.settings.max-jobs`/`cores`, not with this slice.

Verify on a live job: `docker inspect -f '{{.HostConfig.CgroupParent}}' <id>`
should print `forgejo-runner.slice`, and `oomctl` should list the slice.

## Dependencies

- Host must reach `serverUrl` (tailscale).
- `docker` backend requires `virtualisation.docker.enable` (asserted).
- Internal-CA TLS inside containers needs `docker.shareHostCAs = true` and
  the CA in the host bundle (the `cafecitocloud` module adds it via
  `security.pki.certificateFiles`).
- Jobs on the `nix-docker`-style shared-store runners must run the shared
  `setup-nix` action (cafecitocloud/actions) — the host store is multi-arch
  and picking `nix` by glob order self-poisons (see docs/ci.md gotchas).
