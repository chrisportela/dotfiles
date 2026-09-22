#!/usr/bin/env bash
# Integration test for the aws-client-vpn SAML handshake.
#
# Runs the real aws-client-vpn.sh with the header that pkgs/aws-client-vpn/default.nix
# normally prepends, but pointed at stubs: a fake openvpn that replies with the
# AUTH_FAILED challenge AWS sends, a fake python that answers the DNS lookups
# (and defers to the real one for the SAML listener), and a fake sudo. A curl
# in the background plays the identity provider posting the assertion back.
#
# Usage: ./test-connect-flow.sh   (needs bash, curl, python3)

set -euo pipefail

here="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script="$here/../aws-client-vpn.sh"
listener="$here/../saml-listener.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() { echo "PASS: $*"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

port=35099
endpoint_host="cvpn-endpoint-0123456789abcdef.prod.clientvpn.us-east-1.amazonaws.com"
endpoint_addr="203.0.113.5"
session_id="instance-1/8b2a1c3d4e5f6a7b/abcd1234"
assertion="PHNhbWxwOlJlc3BvbnNlPmZvbytiYXIvYmF6PT0="
saml_url="https://idp.example.com/app/awsvpn/exk1abc/sso/saml?SAMLRequest=fZJdb%2FIw&RelayState=x"

cat > "$tmp/profile.ovpn" << EOF
client
dev tun
proto udp
remote $endpoint_host 443
remote-random-hostname
resolv-retry infinite
remote-cert-tls server
verify-x509-name *.prod.clientvpn.us-east-1.amazonaws.com name
reneg-sec 0
auth-federate
auth-retry interact
auth-user-pass
EOF

# --- stubs ---------------------------------------------------------------

mkdir -p "$tmp/bin"

cat > "$tmp/bin/openvpn-aws" << EOF
#!/usr/bin/env bash
set -euo pipefail
n=1
[ ! -f "$tmp/calls" ] || n=\$((\$(cat "$tmp/calls") + 1))
echo "\$n" > "$tmp/calls"
printf '%s\n' "\$@" > "$tmp/args.\$n"

config=""
auth=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --config) config="\$2"; shift 2 ;;
    --auth-user-pass) auth="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "\$config" "$tmp/config.\$n"
[ -z "\$auth" ] || cat "\$auth" > "$tmp/auth.\$n"

if [ "\$n" = 1 ]; then
  echo "Mon Jul 13 12:00:00 2026 AUTH: Received control message: AUTH_FAILED,CRV1:R:$session_id:Tjav:$saml_url"
  exit 1
fi
exit 0
EOF

# The script asks python for a random label and for the endpoint address; the
# SAML listener must still run under the real interpreter.
cat > "$tmp/bin/python3" << EOF
#!/usr/bin/env bash
set -euo pipefail
case "\${2:-}" in
  *secrets*) printf 'deadbeef.%s\n' "\$3" ;;
  *gethostbyname*) printf '%s\n' "$endpoint_addr" ;;
  *) exec $(command -v python3) "\$@" ;;
esac
EOF

printf '#!/usr/bin/env bash\nexec "$@"\n' > "$tmp/bin/sudo"
chmod +x "$tmp/bin/openvpn-aws" "$tmp/bin/python3" "$tmp/bin/sudo"

# --- assemble the wrapper the way default.nix does -----------------------

{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  printf 'OPENVPN_AWS=%q\n' "$tmp/bin/openvpn-aws"
  printf 'SAML_LISTENER=%q\n' "$listener"
  printf 'PYTHON=%q\n' "$tmp/bin/python3"
  printf 'RESOLVED_HELPER=%q\n' "/nonexistent/update-systemd-resolved"
  printf 'RESOLVED_PATH=%q\n' "/nonexistent/bin"
  echo 'readonly OPENVPN_AWS SAML_LISTENER PYTHON RESOLVED_HELPER RESOLVED_PATH'
  cat "$script"
} > "$tmp/aws-client-vpn"
chmod +x "$tmp/aws-client-vpn"

# --- run ------------------------------------------------------------------

PATH="$tmp/bin:$PATH" "$tmp/aws-client-vpn" \
  --config "$tmp/profile.ovpn" \
  --port "$port" \
  --timeout 30 \
  --dns none \
  --no-browser \
  -- --inactive 3600 > "$tmp/stdout" 2>&1 &
runner=$!

# Play the identity provider once the listener is up.
posted=0
for _ in $(seq 1 60); do
  if curl -fsS --noproxy '*' -o /dev/null \
    --data-urlencode "SAMLResponse=$assertion" \
    --data "RelayState=x" \
    "http://127.0.0.1:$port/" 2> /dev/null; then
    posted=1
    break
  fi
  sleep 0.5
done
[ "$posted" = 1 ] || {
  cat "$tmp/stdout" >&2
  fail "could not post the SAML response to the listener"
}

wait "$runner" || {
  cat "$tmp/stdout" >&2
  fail "aws-client-vpn exited non-zero"
}
pass "the full handshake ran end to end"

# --- assertions -----------------------------------------------------------

[ "$(cat "$tmp/calls")" = 2 ] || fail "expected two openvpn invocations, got $(cat "$tmp/calls")"
pass "openvpn was invoked twice"

grep -qx -- "$endpoint_addr" "$tmp/args.1" || fail "first connection did not use the resolved address"
grep -qx -- "$endpoint_addr" "$tmp/args.2" || fail "second connection did not use the resolved address"
pass "both connections pinned the same endpoint address"

grep -qx 'ACS::'"$port" "$tmp/auth.1" || fail "first connection did not send the ACS::<port> password"
pass "first connection asked for the SAML challenge"

printf 'N/A\nCRV1::%s::%s\n' "$session_id" "$assertion" > "$tmp/auth.expected"
diff -u "$tmp/auth.expected" "$tmp/auth.2" > /dev/null ||
  fail "second connection sent the wrong credentials:"$'\n'"$(cat "$tmp/auth.2")"
pass "second connection sent CRV1::<session id>::<assertion>"

grep -qx -- '--inactive' "$tmp/args.2" && grep -qx -- '3600' "$tmp/args.2" ||
  fail "pass-through arguments did not reach openvpn"
pass "arguments after -- reached openvpn"

for directive in auth-federate auth-user-pass auth-retry remote-random-hostname; do
  ! grep -q "^$directive" "$tmp/config.2" || fail "$directive survived into the profile"
done
pass "auth and remote directives were stripped from the profile"

for directive in remote-cert-tls verify-x509-name reneg-sec; do
  grep -q "^$directive" "$tmp/config.2" || fail "$directive was dropped from the profile"
done
pass "verification directives were kept"

! grep -q "^remote " "$tmp/config.2" || fail "the profile's remote line was not stripped"
pass "the endpoint address comes only from the command line"

echo "All checks passed."
