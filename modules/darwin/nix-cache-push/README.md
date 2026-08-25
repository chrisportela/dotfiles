# nix-cache-push (darwin)

Installs a `nix.settings.post-build-hook` that pushes every locally-built
store path to the [niks3](https://github.com/Mic92/niks3) cache at
`https://niks3.cafecito.cloud` (tailnet-only, hosted on liara — see the infra
repo). Darwin analog of infra's NixOS `cafecito.nixCachePush` module: the
linux build hosts (liara/lucy/ada) get the hook from infra; lux gets it from
here so darwin CI builds land in the cache too, and roxy can substitute darwin
closures instead of rebuilding them.

Because the hook is installed at the daemon level, **CI workflows need no
push step at all** — anything a runner builds is pushed automatically, as is
anything built interactively on the host.

## Options (`chrisportela.nix-cache-push`)

| Option | Default | Purpose |
| --- | --- | --- |
| `enable` | `false` | Enable the hook. |
| `package` | `inputs.niks3.packages.<system>.niks3` | niks3 client. |
| `serverUrl` | `https://niks3.cafecito.cloud` | Push target. |
| `tokenFile` | — | Runtime path to the API token (agenix secret; root-readable is enough — the hook runs inside the root nix-daemon). |
| `pushTimeout` | `900` | Kill a hung push after this many seconds (builds block on the hook). |

## Failure semantics

Push failures are downgraded to warnings and a hard `timeout` bounds every
invocation — the hook must never wedge or fail builds. If the cache is down,
builds proceed and the paths are simply pushed the next time something
references them in a fresh build.

## Dependencies

- `nix.settings.post-build-hook` is a **single** nix.conf value; do not
  assign it elsewhere on hosts with this module enabled.
- The niks3 API token is minted on liara (infra repo) and stored as an
  agenix secret here; the committed placeholder must be replaced with
  `agenix -e <name>.age`.
- Reads (`extra-substituters` for niks3) are configured fleet-wide by the
  infra repo; this module only handles the push side.
