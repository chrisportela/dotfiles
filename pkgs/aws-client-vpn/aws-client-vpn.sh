# Drive the AWS Client VPN SAML handshake around the AWS-patched OpenVPN build.
#
# AWS splits the connection in two: a first, deliberately failing connection
# whose AUTH_FAILED reply carries the IdP URL and a session id, and a second one
# that sends the SAML assertion back as the OpenVPN password. Both have to land
# on the same endpoint host, so the name is resolved once and the resulting
# address is used for both.
#
# The nix wrapper prepends OPENVPN_AWS, SAML_LISTENER, PYTHON, RESOLVED_HELPER
# and RESOLVED_PATH.
#
# Descended from samm-git/aws-vpn-client's aws-connect.sh; see ./README.md for
# the full list of prior art.

usage() {
  cat <<'EOF'
Usage: aws-client-vpn [options] [-- <extra openvpn arguments>]

Connect to an AWS Client VPN endpoint that uses SAML federated authentication.

Options:
  -c, --config FILE    OpenVPN profile exported from the endpoint. Defaults to
                       $AWS_VPN_CONFIG, else ~/.config/aws-client-vpn/<endpoint>.ovpn
                       (<endpoint> is "default" unless --endpoint is given).
  -e, --endpoint ID    Client VPN endpoint id. Used to export the profile with
                       the AWS CLI when the config file does not exist yet.
  -p, --profile NAME   AWS CLI profile for the export (default: $AWS_PROFILE).
  -r, --region NAME    AWS region for the export (default: $AWS_REGION).
      --port PORT      Loopback port the IdP posts the assertion back to
                       (default: 35001). AWS endpoints expect 35001.
      --timeout SECS   How long to wait for the browser login (default: 180).
      --dns MODE       auto | systemd-resolved | none (default: auto). Controls
                       whether pushed DNS servers are handed to systemd-resolved.
      --no-browser     Print the login URL instead of opening a browser.
  -h, --help           Show this help.

Everything after -- is passed through to the second openvpn invocation.
EOF
}

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[1;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

# Candidate values for the shell completions in completions/, reached as
# `aws-client-vpn __complete <kind>`. Kept out of usage() on purpose: it is
# plumbing, not an interface. Never fails — a completion that errors is worse
# than one that offers nothing.
complete_candidates() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/aws-client-vpn"
  local file entry name

  case "${1:-}" in
    flags)
      printf '%s\n' \
        -c --config \
        -e --endpoint \
        -p --profile \
        -r --region \
        --port --timeout --dns --no-browser \
        -h --help
      ;;
    profiles)
      {
        # In ~/.aws/config a profile is [profile NAME], with [default] the one
        # exception; [sso-session ...] and [services ...] are not profiles.
        file="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
        if [ -r "$file" ]; then
          awk '
            /^[[:space:]]*\[[[:space:]]*profile[[:space:]]+[^]]+\][[:space:]]*$/ {
              name = $0
              sub(/^[[:space:]]*\[[[:space:]]*profile[[:space:]]+/, "", name)
              sub(/[[:space:]]*\][[:space:]]*$/, "", name)
              print name
              next
            }
            /^[[:space:]]*\[[[:space:]]*default[[:space:]]*\][[:space:]]*$/ { print "default" }
          ' "$file"
        fi

        # In ~/.aws/credentials every section is a profile.
        file="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
        if [ -r "$file" ]; then
          awk '
            /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
              name = $0
              sub(/^[[:space:]]*\[[[:space:]]*/, "", name)
              sub(/[[:space:]]*\][[:space:]]*$/, "", name)
              if (name !~ /[[:space:]]/) print name
            }
          ' "$file"
        fi
      } | sort -u
      ;;
    configs)
      for entry in "$dir"/*.ovpn; do
        if [ -f "$entry" ]; then printf '%s\n' "$entry"; fi
      done
      ;;
    endpoints)
      # Endpoint ids of the profiles already exported; asking AWS for the live
      # list would need credentials and a round trip per keystroke.
      for entry in "$dir"/*.ovpn; do
        if [ -f "$entry" ]; then
          name="$(basename "$entry" .ovpn)"
          if [ "$name" != default ]; then printf '%s\n' "$name"; fi
        fi
      done
      ;;
    regions)
      if [ -r "${AWS_CONFIG_FILE:-$HOME/.aws/config}" ]; then
        awk '
          /^[[:space:]]*region[[:space:]]*=/ {
            sub(/^[^=]*=[[:space:]]*/, "")
            sub(/[[:space:]]*$/, "")
            if ($0 != "") print
          }
        ' "${AWS_CONFIG_FILE:-$HOME/.aws/config}" | sort -u
      fi
      ;;
    dns)
      printf '%s\n' auto systemd-resolved none
      ;;
  esac
}

if [ "${1:-}" = "__complete" ]; then
  complete_candidates "${2:-}"
  exit 0
fi

config="${AWS_VPN_CONFIG:-}"
endpoint="${AWS_VPN_ENDPOINT_ID:-}"
aws_profile="${AWS_PROFILE:-}"
aws_region="${AWS_REGION:-}"
saml_port=35001
timeout=180
dns_mode=auto
open_browser=1
passthrough=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c | --config)
      config="${2:-}"
      shift 2
      ;;
    -e | --endpoint)
      endpoint="${2:-}"
      shift 2
      ;;
    -p | --profile)
      aws_profile="${2:-}"
      shift 2
      ;;
    -r | --region)
      aws_region="${2:-}"
      shift 2
      ;;
    --port)
      saml_port="${2:-}"
      shift 2
      ;;
    --timeout)
      timeout="${2:-}"
      shift 2
      ;;
    --dns)
      dns_mode="${2:-}"
      shift 2
      ;;
    --no-browser)
      open_browser=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      passthrough=("$@")
      break
      ;;
    *)
      die "unknown argument: $1 (see --help)"
      ;;
  esac
done

case "$dns_mode" in
  auto | systemd-resolved | none) ;;
  *) die "--dns must be auto, systemd-resolved or none" ;;
esac

if [ -z "$config" ]; then
  config="${XDG_CONFIG_HOME:-$HOME/.config}/aws-client-vpn/${endpoint:-default}.ovpn"
fi

if [ ! -f "$config" ]; then
  [ -n "$endpoint" ] || die "no profile at $config; pass --config FILE, or --endpoint ID to export one"
  command -v aws > /dev/null || die "the AWS CLI is needed to export a profile; install awscli2 or pass --config FILE"

  log "Exporting the profile for $endpoint to $config"
  export_args=(ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id "$endpoint" --output text)
  [ -z "$aws_profile" ] || export_args+=(--profile "$aws_profile")
  [ -z "$aws_region" ] || export_args+=(--region "$aws_region")

  mkdir -p "$(dirname "$config")"
  aws "${export_args[@]}" > "$config" || {
    rm -f "$config"
    die "could not export the profile for $endpoint"
  }
fi

workdir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/aws-client-vpn.XXXXXX")"
chmod 700 "$workdir"
trap 'rm -rf "$workdir"' EXIT INT TERM

remote_line="$(grep -m1 -E '^[[:space:]]*remote[[:space:]]' "$config" || true)"
[ -n "$remote_line" ] || die "no 'remote' line in $config; is it an AWS Client VPN profile?"
read -r _ vpn_host vpn_port _ <<< "$remote_line"
[ -n "$vpn_host" ] || die "could not read the endpoint host from $config"
vpn_port="${vpn_port:-443}"

# The SAML handshake is driven from the command line instead, and the endpoint
# address is pinned below, so drop the profile's auth and remote directives.
# `remote-cert-tls` and `verify-x509-name` are deliberately left alone.
profile="$workdir/profile.ovpn"
grep -v -E '^[[:space:]]*(auth-federate|auth-user-pass|auth-retry|remote-random-hostname|remote[[:space:]])' \
  "$config" > "$profile"

# AWS asks clients to prefix a random label to the endpoint name so sessions
# spread over the endpoint's addresses; resolving it once keeps both
# connections on the host that issued the session id.
lookup="$("$PYTHON" -c 'import secrets, sys; print(secrets.token_hex(12) + "." + sys.argv[1])' "$vpn_host")"
vpn_addr="$("$PYTHON" -c 'import socket, sys; print(socket.gethostbyname(sys.argv[1]))' "$lookup")" ||
  die "could not resolve $vpn_host"

log "Endpoint $vpn_host resolved to $vpn_addr:$vpn_port"
log "Asking the endpoint for the SAML login URL"

# Expected to fail: the AUTH_FAILED reply is what carries the challenge.
handshake="$workdir/handshake.log"
timeout 60 "$OPENVPN_AWS" \
  --config "$profile" \
  --remote "$vpn_addr" "$vpn_port" \
  --verb 3 \
  --auth-retry none \
  --auth-nocache \
  --connect-retry-max 3 \
  --auth-user-pass <(printf '%s\n%s\n' "N/A" "ACS::$saml_port") > "$handshake" 2>&1 || true
[ -z "${AWS_CLIENT_VPN_DEBUG:-}" ] || cat "$handshake" >&2

challenge="$(grep -m1 'AUTH_FAILED,CRV1:' "$handshake" || true)"
[ -n "$challenge" ] || die "the endpoint did not return a SAML challenge; re-run with AWS_CLIENT_VPN_DEBUG=1 to see the handshake log"

# The challenge is OpenVPN's dynamic-challenge format:
#   AUTH_FAILED,CRV1:<flags>:<session id>:<base64 username>:<login URL>
rest="${challenge#*AUTH_FAILED,CRV1:}"
rest="${rest#*:}"
session_id="${rest%%:*}"
rest="${rest#*:}"
saml_url="${rest#*:}"

case "$saml_url" in
  https://*) ;;
  *) die "could not parse the login URL out of: $challenge" ;;
esac
[ -n "$session_id" ] || die "could not parse the session id out of: $challenge"

if [ "$open_browser" -eq 1 ] && command -v xdg-open > /dev/null; then
  xdg-open "$saml_url" > /dev/null 2>&1 &
  log "Opened the login page in your browser. If nothing appeared, open:"
else
  log "Open this URL to log in:"
fi
printf '%s\n' "$saml_url"

assertion="$workdir/saml-response"
"$PYTHON" "$SAML_LISTENER" --port "$saml_port" --output "$assertion" --timeout "$timeout" ||
  die "no SAML response received"

auth="$workdir/auth"
(
  umask 077
  printf '%s\nCRV1::%s::%s\n' "N/A" "$session_id" "$(cat "$assertion")" > "$auth"
)
rm -f "$assertion"

dns_args=()
if [ "$dns_mode" = auto ]; then
  if [ -e /run/systemd/resolve/resolv.conf ] && [ -x "$RESOLVED_HELPER" ]; then
    dns_mode=systemd-resolved
  else
    dns_mode=none
  fi
fi

if [ "$dns_mode" = systemd-resolved ]; then
  [ -x "$RESOLVED_HELPER" ] || die "update-systemd-resolved is not available in this build"
  dns_args=(
    --script-security 2
    --setenv PATH "$RESOLVED_PATH"
    --up "$RESOLVED_HELPER"
    --down "$RESOLVED_HELPER"
    --up-restart
    --down-pre
  )
else
  log "Pushed DNS servers will not be applied (--dns $dns_mode)"
fi

sudo_cmd=()
if [ "$(id -u)" -ne 0 ]; then
  command -v sudo > /dev/null || die "sudo is needed to bring up the tunnel"
  sudo_cmd=(sudo)
  log "Starting the tunnel; sudo may ask for your password"
else
  log "Starting the tunnel"
fi

status=0
"${sudo_cmd[@]}" "$OPENVPN_AWS" \
  --config "$profile" \
  --remote "$vpn_addr" "$vpn_port" \
  --auth-user-pass "$auth" \
  --auth-nocache \
  --verb 3 \
  "${dns_args[@]}" \
  "${passthrough[@]}" || status=$?

exit "$status"
