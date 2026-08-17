# GIS-Overpass-Server

Docker-based setup for running multiple self-hosted [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API) instances — one per country, each with its own database, its own port, and its own Geofabrik update feed. Built on the [`wiktorn/overpass-api`](https://github.com/wiktorn/Overpass-API) image.

## Requirements

- `docker` with Docker Compose v2 (`docker compose ...`)
- `curl`
- enough free disk space (see [Disk usage](#disk-usage))

## Installation

```bash
git clone <repo-url>
cd GIS-Overpass-Server
```

Nothing else needs to be installed — all commands live under `bin/`.

## Installing a country

```bash
./bin/setup-country italy
```

Downloads the PBF file from Geofabrik, initializes the Overpass database, starts the container, and waits until the API responds. The download is resumable — if it's interrupted (e.g. by connection problems), just run the same command again; it continues instead of starting over (see [Deviations](#deviations-from-the-original-technical-proposal)).

Options:

```bash
./bin/setup-country italy --keep-pbf   # keep the source PBF after import
./bin/setup-country italy --yes        # confirm the disk-space warning without prompting
```

Available countries live in [`config/countries.conf`](config/countries.conf); more can be added with a single extra line (see the comment in that file).

## Status

```bash
./bin/status
```

```text
COUNTRY            PORT    CONTAINER                STATUS                         DISK
------------------------------------------------------------------------------------------
italy              18001   overpass-italy           Up 3 hours (healthy)           18G
germany             18002   overpass-germany         Exited (0) 12 minutes ago      37G
```

## Start / stop / restart

Single country:

```bash
./bin/start-country italy
./bin/stop-country italy
./bin/restart-country italy
```

All installed countries:

```bash
./bin/start-all
./bin/stop-all
./bin/restart-all
```

A stopped container never loses its database — data persists under `./data/<country>/db`.

## Logs

```bash
./bin/logs italy
```

## Testing

```bash
./bin/test-country italy
```

```text
Testing overpass-italy at localhost:18001...

HTTP: 200
Overpass API: OK
```

## Removing

```bash
./bin/remove-country italy
```

Shows the container and database size and requires typing the exact country name to confirm. Without correct confirmation, nothing is deleted.

## Running an Overpass query

```bash
curl \
  --data-urlencode 'data=[out:json];node["amenity"="restaurant"](43.39,10.84,43.42,10.89);out;' \
  http://localhost:18001/api/interpreter
```

## Architecture

Each country gets its own, fully independent container with its own database, port, and update stream:

```text
italy   → overpass-italy   → ./data/italy/db    → port 18001 → italy-updates/
germany → overpass-germany → ./data/germany/db  → port 18002 → germany-updates/
```

There is **no static `docker-compose.yml` per country**. Instead, a single `docker-compose.yml` at the project root is **automatically regenerated** by `lib/common.sh` (function `render_compose`) whenever a country is added or removed. It is built purely from `data/<country>/instance.env` — that file is the single source of truth for "which countries are installed, on which port". `docker-compose.yml` is therefore not version-controlled (`.gitignore`) and should never be hand-edited.

### Directory structure

```text
GIS-Overpass-Server/
├── docker-compose.yml       # auto-generated, do not edit by hand
├── config/
│   └── countries.conf       # catalog: country|pbf_url|diff_url
├── lib/
│   └── common.sh            # shared functions used by all bin/* scripts
├── bin/                      # setup-country, status, logs, ...
└── data/
    └── <country>/
        ├── instance.env      # port, URLs, timestamp (our state)
        └── db/                # persistent Overpass database (bind-mounted /db)
```

### Ports

Ports are assigned automatically, starting at `18001` and counting up, avoiding ports already in use (both by our own installations and by other processes on the host). The API is reachable on **all interfaces** by default (`0.0.0.0:<port>`), so it can also be used from the LAN:

```text
http://HOST:18001/api/interpreter
```

> **Security note:** There is **no authentication** built in. The ports must therefore **never be exposed unprotected to the internet** (no port forwarding, no public firewall rule) — only use this on a trusted LAN or behind your own reverse proxy with authentication.

## Updates

After the initial import, each instance keeps itself up to date automatically via the Geofabrik replication feed configured in `config/countries.conf` (`<country>-updates/`) — this is the built-in update mechanism of `wiktorn/overpass-api` (`OVERPASS_DIFF_URL` + `OVERPASS_UPDATE_SLEEP`, set to daily here), not a custom-built solution. Each country has its own, independent replication state inside its own `/db`.

```text
italy   → italy-updates/   → overpass-italy   (own replication state)
germany → germany-updates/ → overpass-germany (own replication state)
```

## Disk usage

- Before every `setup-country`, free disk space is checked via `df`; if it's clearly low (default: < 20 GB, overridable via `MIN_FREE_GB`), a warning with a confirmation prompt appears. No attempt is made to precisely predict the final database size.
- The downloaded source PBF is deleted by default once the database has been built successfully. With `--keep-pbf` it is kept at `data/<country>/db/source.osm.pbf`.
- A short-lived extra copy of the PBF data is created inside the container during initialization (see below) — this is temporary and cleaned up automatically.

## Deviations from the original technical proposal

These three points deliberately deviate from the original request, based on the current documentation of `wiktorn/overpass-api` and the actual network conditions:

1. **Resumable download on the host instead of inside the container.** The image downloads `OVERPASS_PLANET_URL` itself — but with a single, non-resumable `curl -L -o` (no `-C -`). On a slow or unstable connection, a dropped connection during a large country (several GB) would waste the entire download. Instead, `bin/setup-country` downloads the PBF file itself with `curl -C - --retry` onto the host (`data/<country>/db/source.osm.pbf`) and hands the container a `file://` URL. An interruption can be resumed by simply re-running `setup-country`. This creates a short-lived second copy of the file inside the container during initialization (`osmium` conversion), which is deleted automatically afterwards.
2. **`OVERPASS_STOP_AFTER_INIT=false`.** The image's default (`true`) makes the container exit after initialization and relies on `restart: unless-stopped` to bring it back up into serving mode. For a single, easy-to-follow lifecycle (including progress tracking via the Docker healthcheck), this is explicitly disabled here.
3. **Geofabrik's own `-updates/` feeds instead of the openstreetmap.fr mirror** shown in the Overpass API documentation's example, since the task explicitly calls for a Geofabrik replication feed.

## Example workflow

```bash
./bin/setup-country italy
./bin/setup-country germany

./bin/status

./bin/stop-country germany

./bin/test-country italy

./bin/start-country germany

./bin/remove-country italy
```
