#!/usr/bin/env bash
# Tests for the shell completions in ../completions.
#
# Drives the real completion scripts against a fake HOME holding an AWS config,
# an AWS credentials file and a couple of exported .ovpn profiles, with the real
# aws-client-vpn.sh on PATH answering the `__complete` queries. bash is required;
# zsh, fish and nushell are exercised when they are installed and skipped
# otherwise.
#
# Usage: ./test-completions.sh

set -euo pipefail

here="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
script="$here/../aws-client-vpn.sh"
completions="$here/../completions"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() { echo "PASS: $*"; }
skip() { echo "SKIP: $*"; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- a plausible AWS setup -----------------------------------------------

mkdir -p "$tmp/home/.aws" "$tmp/home/.config/aws-client-vpn" "$tmp/bin"

cat > "$tmp/home/.aws/config" << 'EOF'
[default]
region = us-east-1

[profile work]
region = eu-west-2

[sso-session corp]
sso_region = eu-west-2
EOF

cat > "$tmp/home/.aws/credentials" << 'EOF'
[legacy-keys]
aws_access_key_id = AKIAEXAMPLE
EOF

: > "$tmp/home/.config/aws-client-vpn/default.ovpn"
: > "$tmp/home/.config/aws-client-vpn/cvpn-endpoint-0123456789abcdef.ovpn"

# aws-client-vpn on PATH, assembled the way default.nix assembles it. Only the
# `__complete` path is reached here, so the store paths can be placeholders.
{
  echo '#!/usr/bin/env bash'
  echo 'set -euo pipefail'
  printf 'OPENVPN_AWS=%q\n' "/nonexistent/openvpn-aws"
  printf 'SAML_LISTENER=%q\n' "/nonexistent/saml-listener.py"
  printf 'PYTHON=%q\n' "/nonexistent/python3"
  printf 'RESOLVED_HELPER=%q\n' "/nonexistent/update-systemd-resolved"
  printf 'RESOLVED_PATH=%q\n' "/nonexistent/bin"
  echo 'readonly OPENVPN_AWS SAML_LISTENER PYTHON RESOLVED_HELPER RESOLVED_PATH'
  cat "$script"
} > "$tmp/bin/aws-client-vpn"
chmod +x "$tmp/bin/aws-client-vpn"

export HOME="$tmp/home"
export PATH="$tmp/bin:$PATH"
unset AWS_CONFIG_FILE AWS_SHARED_CREDENTIALS_FILE XDG_CONFIG_HOME

# --- the candidate lists themselves --------------------------------------

got="$(aws-client-vpn __complete profiles | tr '\n' ' ')"
[ "$got" = "default legacy-keys work " ] ||
  fail "profiles: expected 'default legacy-keys work', got '$got'"
pass "profiles come from both AWS files, without the sso-session section"

got="$(aws-client-vpn __complete endpoints | tr '\n' ' ')"
[ "$got" = "cvpn-endpoint-0123456789abcdef " ] ||
  fail "endpoints: expected the exported endpoint id only, got '$got'"
pass "endpoints list exported profiles and skip 'default'"

got="$(aws-client-vpn __complete regions | tr '\n' ' ')"
[ "$got" = "eu-west-2 us-east-1 " ] || fail "regions: got '$got'"
pass "regions come from the AWS config"

aws-client-vpn __complete configs | grep -q '/default\.ovpn$' ||
  fail "configs did not list the exported profile paths"
pass "configs list the exported profile paths"

[ -z "$(aws-client-vpn __complete not-a-kind)" ] || fail "unknown kind produced output"
pass "an unknown kind is quietly empty"

# --- bash -----------------------------------------------------------------

complete_with_bash() {
  # $@ = the words on the command line; completes the last one.
  local words=("$@")
  bash --noprofile --norc -c '
    source "$1"; shift
    COMP_WORDS=("$@")
    COMP_CWORD=$(($# - 1))
    compopt() { :; }
    _aws_client_vpn
    printf "%s\n" "${COMPREPLY[@]}"
  ' bash "$completions/aws-client-vpn.bash" "${words[@]}"
}

got="$(complete_with_bash aws-client-vpn --profile "" | tr '\n' ' ')"
[ "$got" = "default legacy-keys work " ] || fail "bash --profile: got '$got'"
pass "bash completes --profile from the AWS config"

got="$(complete_with_bash aws-client-vpn --profile w | tr '\n' ' ')"
[ "$got" = "work " ] || fail "bash --profile w: got '$got'"
pass "bash filters --profile on the typed prefix"

got="$(complete_with_bash aws-client-vpn --endpoint "" | tr '\n' ' ')"
[ "$got" = "cvpn-endpoint-0123456789abcdef " ] || fail "bash --endpoint: got '$got'"
pass "bash completes --endpoint from the exported profiles"

got="$(complete_with_bash aws-client-vpn --dns "" | tr '\n' ' ')"
[ "$got" = "auto systemd-resolved none " ] || fail "bash --dns: got '$got'"
pass "bash completes --dns with the three modes"

complete_with_bash aws-client-vpn --config "" | grep -q '/default\.ovpn$' ||
  fail "bash --config did not offer the exported profiles"
pass "bash completes --config with the exported profiles"

got="$(complete_with_bash aws-client-vpn --no | tr '\n' ' ')"
[ "$got" = "--no-browser " ] || fail "bash flag completion: got '$got'"
pass "bash completes flag names"

# --- zsh ------------------------------------------------------------------

if command -v zsh > /dev/null; then
  zsh -n "$completions/_aws-client-vpn" || fail "_aws-client-vpn is not valid zsh"
  pass "zsh parses the completion"

  # compinit reads the #compdef tag, so this proves zsh would actually reach
  # the completion for this command — short of driving a real keystroke.
  got="$(zsh -f -c "
    fpath=('$completions' \$fpath)
    autoload -Uz compinit
    compinit -u -d '$tmp/zcompdump'
    print -r -- \${_comps[aws-client-vpn]}
  ")"
  [ "$got" = "_aws-client-vpn" ] ||
    fail "zsh did not register the completion for aws-client-vpn (got '$got')"
  pass "zsh registers _aws-client-vpn for the command"

  got="$(zsh -f -c "
    local -a names
    names=(\${(f)\"\$(aws-client-vpn __complete profiles 2>/dev/null)\"})
    print -r -- \$names
  ")"
  [ "$got" = "default legacy-keys work" ] ||
    fail "zsh candidate splitting is wrong (got '$got')"
  pass "zsh splits the candidate list into one entry per line"
else
  skip "zsh is not installed"
fi

# --- fish -----------------------------------------------------------------

if command -v fish > /dev/null; then
  fish --no-config --command "source '$completions/aws-client-vpn.fish'" ||
    fail "fish could not source the completion"
  pass "fish sources the completion"

  # fish returns its candidates sorted, so compare as a set.
  got="$(fish --no-config --command "
    source '$completions/aws-client-vpn.fish'
    complete --do-complete 'aws-client-vpn --dns '
  " | awk '{print $1}' | sort | tr '\n' ' ')"
  [ "$got" = "auto none systemd-resolved " ] || fail "fish --dns: got '$got'"
  pass "fish completes --dns with the three modes"

  got="$(fish --no-config --command "
    source '$completions/aws-client-vpn.fish'
    complete --do-complete 'aws-client-vpn --profile '
  " | awk '{print $1}' | sort | tr '\n' ' ')"
  [ "$got" = "default legacy-keys work " ] || fail "fish --profile: got '$got'"
  pass "fish completes --profile from the AWS config"
else
  skip "fish is not installed"
fi

# --- nushell --------------------------------------------------------------

if command -v nu > /dev/null; then
  nu --no-config-file --commands "source '$completions/aws-client-vpn.nu'" ||
    fail "nushell could not parse the completion"
  pass "nushell parses the completion module"
else
  skip "nushell is not installed"
fi

echo "All checks passed."
