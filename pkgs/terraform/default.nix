{ terraform, ... }:
terraform.withPlugins (p: [
  p.cloudflare_cloudflare
  p.hashicorp_aws
  p.hashicorp_google
  p."hashicorp_google-beta"
])
