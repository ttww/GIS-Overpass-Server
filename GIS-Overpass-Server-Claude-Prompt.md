# Task: Multi-Country Overpass GIS Server

Create a complete Docker-based setup for running self-hosted Overpass API instances in this **empty project folder `GIS-Overpass-Server`**.

## Goal

Each installed country should run its **own Overpass API instance** with its own database.

Example:

```text
GIS-Overpass-Server/
├── docker-compose.yml
├── bin/
│   ├── setup-country
│   ├── start-country
│   ├── stop-country
│   ├── restart-country
│   ├── remove-country
│   ├── status
│   └── logs
├── config/
│   └── countries.conf
├── data/
│   ├── germany/
│   ├── italy/
│   └── ...
└── README.md
```

The exact structure may be improved if technically sensible.

---

## Base architecture

Use Docker Compose and the image:

```text
wiktorn/overpass-api
```

Each country gets:

- its own Docker container
- its own Overpass database
- its own persistent data directory
- its own port
- its own Geofabrik PBF download
- its own Geofabrik replication/update feed

Example:

```text
Germany
  Container: overpass-germany
  Data:      ./data/germany/
  Port:      18001

Italy
  Container: overpass-italy
  Data:      ./data/italy/
  Port:      18002
```

Ports should be managed automatically.

---

# Important: no static compose file per country

Countries should be manageable dynamically.

For example, I want to be able to run:

```bash
./bin/setup-country italy
./bin/setup-country germany
./bin/setup-country czech-republic
```

Afterwards:

```bash
./bin/status
```

e.g.:

```text
COUNTRY          PORT    STATUS       DB SIZE
------------------------------------------------
italy            18001   running      18.4 GB
germany          18002   stopped      37.2 GB
czech-republic   18003   running       8.1 GB
```

Design a robust yet as-simple-as-possible solution for this.

If Docker Compose profiles, dynamically generated compose files, or another Compose concept make sense for this, choose whichever solution is most maintainable.

**No Kubernetes solution.**

---

# Country configuration

The configuration should be declarative.

For example:

```text
config/countries.conf
```

or YAML/JSON, if that makes more sense.

It should contain at least:

```text
country
Geofabrik PBF URL
Geofabrik update URL
Port
```

The Geofabrik URLs should not be unnecessarily hardcoded and scattered throughout the code.

Examples:

```text
italy
germany
austria
switzerland
czech-republic
france
```

However, it must be easy to add further Geofabrik regions.

---

# setup-country

The most important command:

```bash
./bin/setup-country italy
```

It should:

1. check whether the country is known
2. check whether it is already installed
3. create the required directories
4. determine a free/configured port
5. download the PBF from Geofabrik
6. perform the necessary conversion for Overpass
7. initialize the Overpass database
8. set up the update/replication configuration
9. start the container
10. wait for successful initialization, or show progress in an understandable way
11. print the endpoint and status at the end

Example:

```text
Setting up Italy...

Downloading:
https://download.geofabrik.de/europe/italy-latest.osm.pbf

PBF size: 2.1 GB

Initializing Overpass database...
[...]

Overpass Italy ready.

Endpoint:
http://localhost:18001/api/interpreter

Data directory:
./data/italy

Database size:
18.4 GB
```

The process must also be robust for large countries.

Downloads should be resumable where possible (`curl -C -` or similar).

---

# Start / stop

Individual countries:

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

A stopped server must of course not lose its database.

---

# Status

```bash
./bin/status
```

should show at least:

```text
COUNTRY          PORT    CONTAINER              STATUS       DISK
------------------------------------------------------------------
italy            18001   overpass-italy         running      18G
germany          18002   overpass-germany       stopped      39G
```

Optionally in addition:

- Health
- Time of last update
- Container uptime

---

# Logs

Support:

```bash
./bin/logs italy
```

roughly corresponding to:

```bash
docker logs -f overpass-italy
```

---

# Removal

```bash
./bin/remove-country italy
```

This must explicitly warn that the Overpass database will be deleted.

Example:

```text
This will remove:

Container: overpass-italy
Database:  ./data/italy (18.4 GB)

Type "italy" to confirm:
```

Without correct confirmation, nothing may be deleted.

---

# Updates

After the initial import, the Overpass instances should be kept up to date automatically using the corresponding Geofabrik diffs.

Each country must have its own replication state.

Example:

```text
Italy
   ↓
italy-updates
   ↓
overpass-italy

Germany
   ↓
germany-updates
   ↓
overpass-germany
```

Check the current documentation of `wiktorn/overpass-api` for how `OVERPASS_DIFF_URL`, update intervals, and replication state are correctly configured.

Do not invent your own update mechanism if the image already supports this.

---

# Docker

Container names:

```text
overpass-<country>
```

Examples:

```text
overpass-italy
overpass-germany
overpass-czech-republic
```

Persistent data:

```text
./data/<country>/
```

Containers should use:

```yaml
restart: unless-stopped
```

Internal API port:

```text
80
```

Host ports, for example starting at:

```text
18001
```

Ports must not collide.

---

# Network access

By default, the API should be reachable on all interfaces of the Docker host:

```text
0.0.0.0:18001
```

This allows it to also be used from the LAN.

Document the corresponding endpoint:

```text
http://HOST:18001/api/interpreter
```

**No authentication** should be built in.

Clearly point out in the README that the ports should therefore **not be exposed unprotected to the internet**.

---

# Test

Create:

```bash
./bin/test-country italy
```

The test should send a small Overpass query against the corresponding instance.

For example a harmless small query like:

```overpass
[out:json][timeout:10];
node(1);
out;
```

or another query that reliably verifies that `/api/interpreter` works correctly.

Expected behavior:

```text
Testing overpass-italy at localhost:18001...

HTTP: 200
Overpass API: OK
```

---

# Error handling

All scripts should use:

```bash
set -euo pipefail
```

or equally robust error handling.

Check prerequisites such as:

```text
docker
docker compose
curl
```

and provide understandable error messages.

Examples:

```text
ERROR: Docker is not installed.
ERROR: Country 'xyz' is unknown.
ERROR: Port 18001 is already in use.
ERROR: Country 'italy' is already installed.
```

---

# PBF files

Avoid unnecessary SSD wear.

If the downloaded `.osm.pbf` is no longer needed after the Overpass database has been built successfully, it should be deleted by default.

Optional:

```bash
./bin/setup-country italy --keep-pbf
```

to keep the source file.

Also remove temporary conversion files after a successful import.

---

# Disk space check

Before the import, it should be estimated/checked whether there is enough free disk space.

At minimum, evaluate:

```bash
df
```

and show free space.

Do not try to predict an allegedly exact size of the finished Overpass database.

Print a clear warning if there is obviously little free space.

---

# Idempotency

Scripts must not accidentally destroy existing installations.

In particular:

```bash
./bin/setup-country italy
```

must abort if Italy is already installed, and must not overwrite `/data/italy`.

---

# README

Create a good, compact `README.md`.

It should contain at least:

## Installation

```bash
git clone ...
cd GIS-Overpass-Server
```

## Installing a country

```bash
./bin/setup-country italy
```

## Status

```bash
./bin/status
```

## Stopping

```bash
./bin/stop-country italy
```

## Starting

```bash
./bin/start-country italy
```

## Testing

```bash
./bin/test-country italy
```

## Removing

```bash
./bin/remove-country italy
```

## Overpass query

Example:

```bash
curl \
  --data-urlencode 'data=[out:json];node["amenity"="restaurant"](43.39,10.84,43.42,10.89);out;' \
  http://localhost:18001/api/interpreter
```

Also briefly explain the architecture, directory structure, updates, and disk usage.

---

# Implementation principles

Priorities:

1. Simplicity
2. Robustness
3. Maintainability
4. as little SSD usage as possible
5. countries fully independent of each other
6. no unnecessary additional services
7. no Kubernetes/Swarm dependency

Prefer shell scripts, unless another language offers a clear advantage.

Do not build an unnecessarily complex framework-based solution.

---

# Important: research first

Before implementing:

1. Check the **current documentation** of `wiktorn/overpass-api`.
2. Check the current Geofabrik download and update URLs.
3. Check in particular how an `.osm.pbf` is correctly initialized with the current Docker image.
4. Check whether PBF conversion is actually required, or whether a direct import is now possible.
5. Check the correct use of:
   - `OVERPASS_MODE`
   - `OVERPASS_PLANET_URL`
   - `OVERPASS_DIFF_URL`
   - `OVERPASS_UPDATE_SLEEP`
   - `OVERPASS_META`
   - `/db`
6. Implement based on the current behavior, **not on outdated examples**.

If my proposed technical approach doesn't match the image's current behavior at some point, change it accordingly and briefly document why in the README.

## Result

Implement the project completely in the current folder.

In particular, the following should work in the end:

```bash
./bin/setup-country italy
./bin/setup-country germany

./bin/status

./bin/stop-country germany

./bin/test-country italy

./bin/start-country germany

./bin/remove-country italy
```

Italy and Germany must have fully independent Overpass databases and update streams.
