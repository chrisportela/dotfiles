# aws-client-vpn(1) nushell completion — candidates come from
# `aws-client-vpn __complete`.

def "nu-complete aws-client-vpn configs" [] {
  do -i { ^aws-client-vpn __complete configs } | lines
}

def "nu-complete aws-client-vpn endpoints" [] {
  do -i { ^aws-client-vpn __complete endpoints } | lines
}

def "nu-complete aws-client-vpn profiles" [] {
  do -i { ^aws-client-vpn __complete profiles } | lines
}

def "nu-complete aws-client-vpn regions" [] {
  do -i { ^aws-client-vpn __complete regions } | lines
}

def "nu-complete aws-client-vpn dns" [] {
  [ "auto", "systemd-resolved", "none" ]
}

export extern "aws-client-vpn" [
  --config(-c): string@"nu-complete aws-client-vpn configs"      # OpenVPN profile exported from the endpoint
  --endpoint(-e): string@"nu-complete aws-client-vpn endpoints"  # Client VPN endpoint id to export a profile from
  --profile(-p): string@"nu-complete aws-client-vpn profiles"    # AWS CLI profile used for the export
  --region(-r): string@"nu-complete aws-client-vpn regions"      # AWS region used for the export
  --port: int                                                    # loopback port the assertion is posted back to
  --timeout: int                                                 # seconds to wait for the browser login
  --dns: string@"nu-complete aws-client-vpn dns"                 # how pushed DNS servers are applied
  --no-browser                                                   # print the login URL instead of opening a browser
  --help(-h)                                                     # show help
  ...args: string
]
