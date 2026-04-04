# use_plane — load Plane project management credentials for MCP
#
# Usage in .envrc:
#   use_plane                    # use default workspace from credentials file
#   use_plane other-workspace    # override workspace slug
#
# Credentials file (@credentialsFile@) should contain:
#   PLANE_API_KEY=...
#   PLANE_BASE_URL=...
#   PLANE_WORKSPACE_SLUG=...

use_plane() {
  local credentials_file="@credentialsFile@"

  # Expand ~ if present
  credentials_file="${credentials_file/#\~/$HOME}"

  if [[ ! -f "$credentials_file" ]]; then
    log_error "use_plane: credentials file not found: $credentials_file"
    log_error "Create it with PLANE_API_KEY, PLANE_BASE_URL, and PLANE_WORKSPACE_SLUG"
    return 1
  fi

  # Source credentials (sets PLANE_API_KEY, PLANE_BASE_URL, PLANE_WORKSPACE_SLUG)
  # shellcheck disable=SC1090
  source "$credentials_file"

  # Override workspace slug if argument provided
  if [[ -n "${1:-}" ]]; then
    PLANE_WORKSPACE_SLUG="$1"
  fi

  # Validate required variables
  local missing=()
  [[ -z "${PLANE_API_KEY:-}" ]] && missing+=("PLANE_API_KEY")
  [[ -z "${PLANE_BASE_URL:-}" ]] && missing+=("PLANE_BASE_URL")
  [[ -z "${PLANE_WORKSPACE_SLUG:-}" ]] && missing+=("PLANE_WORKSPACE_SLUG")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "use_plane: missing variables in $credentials_file: ${missing[*]}"
    return 1
  fi

  export PLANE_API_KEY PLANE_BASE_URL PLANE_WORKSPACE_SLUG
  log_status "Plane: workspace=${PLANE_WORKSPACE_SLUG} url=${PLANE_BASE_URL}"
}
