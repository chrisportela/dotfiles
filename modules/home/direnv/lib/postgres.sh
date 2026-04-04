# layout_postgres — per-project PostgreSQL via direnv
#
# Usage in .envrc:
#   export POSTGRES_DATABASE='myapp'
#   export POSTGRES_USER='myapp'
#   use flake
#   layout_postgres
#
# Requires: POSTGRES_DATABASE and POSTGRES_USER set before calling.
# Provides: PGDATA, PGHOST, DATABASE_URL

layout_postgres() {
  if [[ -z "${POSTGRES_DATABASE:-}" ]] || [[ -z "${POSTGRES_USER:-}" ]]; then
    log_error "layout_postgres: POSTGRES_DATABASE and POSTGRES_USER must be set"
    return 1
  fi

  export PGDATA="$(direnv_layout_dir)/postgres"
  export PGHOST="$PGDATA"

  if [[ ! -d "$PGDATA" ]]; then
    log_status "initializing PostgreSQL database in $PGDATA"
    initdb --no-locale --encoding=UTF8 >/dev/null

    cat >> "$PGDATA/postgresql.conf" <<-EOF
      listen_addresses = ''
      unix_socket_directories = '$PGHOST'
EOF

    echo "CREATE USER ${POSTGRES_USER};" | postgres --single -E postgres >/dev/null
    echo "CREATE DATABASE ${POSTGRES_DATABASE} OWNER ${POSTGRES_USER};" | postgres --single -E postgres >/dev/null
    echo "GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DATABASE} TO ${POSTGRES_USER};" | postgres --single -E postgres >/dev/null
    echo "ALTER ROLE ${POSTGRES_USER} WITH CREATEDB;" | postgres --single -E postgres >/dev/null
    echo "ALTER ROLE ${POSTGRES_USER} WITH SUPERUSER;" | postgres --single -E postgres >/dev/null

    log_status "PostgreSQL initialized: database=${POSTGRES_DATABASE} user=${POSTGRES_USER}"
  fi

  export DATABASE_URL="postgresql://${POSTGRES_USER}@localhost/${POSTGRES_DATABASE}?host=${PGHOST}"
  log_status "PGDATA=$PGDATA"
}
