#!/usr/bin/env bash
# Shared helpers for bin/* scripts. Must stay compatible with bash 3.2 (macOS default):
# no associative arrays, no mapfile/readarray, no `local -n`.

# ROOT_DIR = repository root (parent of lib/), resolved from this file's own location
# so it works regardless of the caller's current working directory.
_COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${_COMMON_SH_DIR}/.." && pwd -P)"

CONFIG_FILE="${ROOT_DIR}/config/countries.conf"
DATA_DIR="${ROOT_DIR}/data"
COMPOSE_FILE="${ROOT_DIR}/docker-compose.yml"

OVERPASS_IMAGE="${OVERPASS_IMAGE:-wiktorn/overpass-api:v0.7.62}"
BASE_PORT="${BASE_PORT:-18001}"
MIN_FREE_GB="${MIN_FREE_GB:-20}"

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------

log() {
  printf '%s\n' "$*"
}

error() {
  printf 'ERROR: %s\n' "$*" >&2
}

die() {
  error "$*"
  exit 1
}

# ---------------------------------------------------------------------------
# prerequisites
# ---------------------------------------------------------------------------

check_prereqs() {
  command -v docker >/dev/null 2>&1 || die "Docker is not installed."
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 ('docker compose') is not available."
  command -v curl >/dev/null 2>&1 || die "curl is not installed."
}

usage_die() {
  die "Usage: $(basename "$0") $*"
}

require_country_arg() {
  if [ -z "${1:-}" ]; then
    usage_die "<country>"
  fi
}

# ---------------------------------------------------------------------------
# catalog (config/countries.conf) — key|pbf_url|diff_url
# ---------------------------------------------------------------------------

# Populates CATALOG_PBF_URL / CATALOG_DIFF_URL for a known country.
# Returns 1 (and leaves the vars unset) if the country is not in the catalog.
catalog_get() {
  local key="$1" line
  line=$(awk -F'|' -v k="$key" '!/^[[:space:]]*#/ && NF>=3 && $1==k {print; exit}' "$CONFIG_FILE")
  if [ -z "$line" ]; then
    return 1
  fi
  CATALOG_PBF_URL=$(printf '%s' "$line" | awk -F'|' '{print $2}')
  CATALOG_DIFF_URL=$(printf '%s' "$line" | awk -F'|' '{print $3}')
  return 0
}

require_known_country() {
  local key="$1"
  catalog_get "$key" || die "Country '${key}' is unknown. See config/countries.conf for available countries."
}

list_catalog_countries() {
  awk -F'|' '!/^[[:space:]]*#/ && NF>=3 {print $1}' "$CONFIG_FILE" | sort
}

# ---------------------------------------------------------------------------
# installed-country state (data/<country>/instance.env)
# ---------------------------------------------------------------------------

instance_dir() {
  printf '%s/%s\n' "$DATA_DIR" "$1"
}

instance_env_path() {
  printf '%s/%s/instance.env\n' "$DATA_DIR" "$1"
}

country_installed() {
  [ -f "$(instance_env_path "$1")" ]
}

# True only once the overpass image itself has finished the initial import
# (it touches /db/init_done — see wiktorn/overpass-api docker-entrypoint.sh).
# Used by setup-country to tell "fully installed" apart from "download/import
# still in progress, safe to resume".
country_fully_initialized() {
  [ -f "$(instance_dir "$1")/db/init_done" ]
}

require_installed_country() {
  local key="$1"
  country_installed "$key" || die "Country '${key}' is not installed. Run: bin/setup-country ${key}"
}

# Sources data/<country>/instance.env into the current shell.
# Provides: PORT, PBF_URL, DIFF_URL, PREPROCESS, UPDATE_SLEEP, KEEP_PBF, INSTALLED_AT
load_instance_env() {
  local key="$1" f
  f="$(instance_env_path "$key")"
  [ -f "$f" ] || die "Country '${key}' is not installed."
  # shellcheck disable=SC1090
  . "$f"
}

list_installed_countries() {
  local f
  for f in "$DATA_DIR"/*/instance.env; do
    [ -e "$f" ] || continue
    basename "$(dirname "$f")"
  done | sort
}

# ---------------------------------------------------------------------------
# ports
# ---------------------------------------------------------------------------

# True (exit 0) if something is listening on 127.0.0.1:<port>.
port_in_use() {
  (: >"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1
}

port_registered() {
  local port="$1" f
  for f in "$DATA_DIR"/*/instance.env; do
    [ -e "$f" ] || continue
    if grep -q "^PORT=${port}\$" "$f"; then
      return 0
    fi
  done
  return 1
}

allocate_port() {
  local port="$BASE_PORT"
  while [ "$port" -le 65000 ]; do
    if ! port_registered "$port" && ! port_in_use "$port"; then
      printf '%s\n' "$port"
      return 0
    fi
    port=$((port + 1))
  done
  die "No free port found starting at ${BASE_PORT}."
}

# ---------------------------------------------------------------------------
# disk space
# ---------------------------------------------------------------------------

check_disk_space() {
  mkdir -p "$DATA_DIR"
  local avail_kb avail_gb fs
  avail_kb=$(df -k "$DATA_DIR" | awk 'NR==2{print $4}')
  fs=$(df -k "$DATA_DIR" | awk 'NR==2{print $1}')
  avail_gb=$((avail_kb / 1024 / 1024))
  log "Free disk space on ${fs}: ${avail_gb} GB"
  if [ "$avail_gb" -lt "$MIN_FREE_GB" ]; then
    error "Only ${avail_gb} GB free (recommended minimum: ${MIN_FREE_GB} GB). A full country import may not fit."
    if [ "${ASSUME_YES:-0}" != "1" ]; then
      printf 'Continue anyway? [y/N] '
      read -r reply
      case "$reply" in
        y | Y | yes | YES) ;;
        *) die "Aborted." ;;
      esac
    fi
  fi
}

# ---------------------------------------------------------------------------
# PBF download
# ---------------------------------------------------------------------------

# The wiktorn/overpass-api image downloads OVERPASS_PLANET_URL itself with a
# single plain `curl -L -o`, no resume support. On a slow/unreliable line a
# multi-GB country extract can easily be interrupted, forcing a full restart.
# We instead download the PBF here on the host with `curl -C -` (resumable,
# retries on transient failures) and hand the container a file:// URL — see
# README "Deviations from the original technical proposal".
download_pbf() {
  local url="$1" dest="$2"
  log "Downloading (resumable):"
  log "  ${url}"
  log "-> ${dest}"
  curl -f -L -C - --retry 10 --retry-delay 5 -o "$dest" "$url"
  if [ ! -s "$dest" ]; then
    die "Download produced an empty file: ${dest}"
  fi
}

# ---------------------------------------------------------------------------
# docker compose file generation
# ---------------------------------------------------------------------------

# Rewrites docker-compose.yml from scratch based on data/*/instance.env.
# This is the single source of truth for "which countries are installed" —
# never hand-edit docker-compose.yml.
render_compose() {
  local tmp_body tmp_vols tmp_out f key any
  tmp_body="${COMPOSE_FILE}.body.$$"
  tmp_vols="${COMPOSE_FILE}.vols.$$"
  tmp_out="${COMPOSE_FILE}.tmp.$$"
  : >"$tmp_body"
  : >"$tmp_vols"
  any=0
  for f in "$DATA_DIR"/*/instance.env; do
    [ -e "$f" ] || continue
    any=1
    key=$(basename "$(dirname "$f")")
    PORT="" PBF_URL="" DIFF_URL="" UPDATE_SLEEP=""
    # shellcheck disable=SC1090
    . "$f"
    # OVERPASS_PLANET_URL points at the file we downloaded on the host (see
    # bin/setup-country / download_pbf) rather than PBF_URL directly, so the
    # container never needs to re-download a multi-GB file over the network.
    #
    # /db/db (the OSM3S database + its dispatcher Unix sockets) is mounted
    # from a named Docker volume, not the host bind mount: on Docker Desktop
    # for Mac, VirtioFS-backed bind mounts fail to bind AF_UNIX sockets
    # (File_Error "Invalid argument"/"Operation not supported"), which
    # crash-loops the dispatcher. A named volume lives entirely inside the
    # Docker VM, so socket binding works normally. Everything else under
    # /db (source pbf, diffs, logs) stays on the host bind mount.
    cat >>"$tmp_body" <<YAML
  overpass-${key}:
    image: ${OVERPASS_IMAGE}
    container_name: overpass-${key}
    restart: unless-stopped
    ports:
      - "0.0.0.0:${PORT}:80"
    volumes:
      - ./data/${key}/db:/db
      - overpass-${key}-db:/db/db
    environment:
      OVERPASS_MODE: init
      OVERPASS_PLANET_URL: "file:///db/source.osm.pbf"
      OVERPASS_DIFF_URL: "${DIFF_URL}"
      OVERPASS_UPDATE_SLEEP: "${UPDATE_SLEEP:-86400}"
      OVERPASS_META: "no"
      OVERPASS_STOP_AFTER_INIT: "false"
      OVERPASS_PLANET_PREPROCESS: "mv /db/planet.osm.bz2 /db/planet.osm.pbf && osmium cat -o /db/planet.osm.bz2 /db/planet.osm.pbf && rm -f /db/planet.osm.pbf"
    healthcheck:
      test: ["CMD-SHELL", "curl -sfg --noproxy '*' 'http://localhost/api/interpreter?data=[out:json];node(1);out;' | grep -q version"]
      interval: 60s
      timeout: 15s
      start_period: 48h
      retries: 3
YAML
    cat >>"$tmp_vols" <<YAML
  overpass-${key}-db:
    name: overpass-${key}-db
YAML
  done
  {
    echo "# AUTO-GENERATED by lib/common.sh (render_compose)."
    echo "# Do not edit by hand — regenerated by bin/setup-country and bin/remove-country"
    echo "# from data/<country>/instance.env. Local machine state, not meant to be committed."
    if [ "$any" -eq 1 ]; then
      echo "services:"
      cat "$tmp_body"
      echo "volumes:"
      cat "$tmp_vols"
    else
      echo "services: {}"
    fi
  } >"$tmp_out"
  rm -f "$tmp_body" "$tmp_vols"
  mv "$tmp_out" "$COMPOSE_FILE"
}

# ---------------------------------------------------------------------------
# container introspection
# ---------------------------------------------------------------------------

container_name_for() {
  printf 'overpass-%s\n' "$1"
}

# Human status string as reported by `docker ps`, e.g. "Up 3 hours (healthy)"
# or "Exited (0) 5 minutes ago". Empty string if the container was never created.
container_ps_status() {
  docker ps -a --filter "name=^/$(container_name_for "$1")\$" --format '{{.Status}}' 2>/dev/null
}

container_state() {
  docker inspect -f '{{.State.Status}}' "$(container_name_for "$1")" 2>/dev/null
}

container_health() {
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$(container_name_for "$1")" 2>/dev/null
}

dir_size_human() {
  du -sh "$1" 2>/dev/null | awk '{print $1}'
}

# Streams logs and blocks until the container's healthcheck reports "healthy",
# or dies loudly if the container exits/dies while we wait.
wait_for_healthy() {
  local key="$1" name status state log_pid
  name="$(container_name_for "$key")"
  log "Waiting for ${name} to become healthy — this can take a long time for large countries."
  log "(Streaming container logs below; safe to Ctrl-C and check back later with: bin/logs ${key})"
  (cd "$ROOT_DIR" && docker compose logs -f --no-log-prefix "$name") &
  log_pid=$!
  while :; do
    state=$(container_state "$key")
    if [ "$state" = "exited" ] || [ "$state" = "dead" ]; then
      kill "$log_pid" >/dev/null 2>&1 || true
      die "Container ${name} exited unexpectedly during initialization. Check: bin/logs ${key}"
    fi
    status=$(container_health "$key")
    if [ "$status" = "healthy" ]; then
      kill "$log_pid" >/dev/null 2>&1 || true
      wait "$log_pid" 2>/dev/null
      break
    fi
    sleep 5
  done
}
