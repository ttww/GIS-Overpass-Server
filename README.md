# GIS-Overpass-Server

Docker-basiertes Setup zum Betrieb mehrerer eigener [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API)-Instanzen — eine pro Land, mit eigener Datenbank, eigenem Port und eigenem Geofabrik-Update-Feed. Basiert auf dem Image [`wiktorn/overpass-api`](https://github.com/wiktorn/Overpass-API).

## Voraussetzungen

- `docker` mit Docker Compose v2 (`docker compose ...`)
- `curl`
- genug freier Speicherplatz (siehe [Speicherverbrauch](#speicherverbrauch))

## Installation

```bash
git clone <repo-url>
cd GIS-Overpass-Server
```

Es muss nichts weiter installiert werden — alle Befehle liegen unter `bin/`.

## Land installieren

```bash
./bin/setup-country italy
```

Lädt die PBF-Datei von Geofabrik herunter, initialisiert die Overpass-Datenbank, startet den Container und wartet, bis die API antwortet. Der Download ist unterbrechbar — bei einem Abbruch (z. B. Verbindungsproblemen) einfach denselben Befehl erneut ausführen, er setzt fort statt neu zu beginnen (siehe [Deviations](#deviations-from-the-original-technical-proposal)).

Optionen:

```bash
./bin/setup-country italy --keep-pbf   # Quell-PBF nach dem Import behalten
./bin/setup-country italy --yes        # Speicherplatz-Warnung ohne Rückfrage bestätigen
```

Verfügbare Länder stehen in [`config/countries.conf`](config/countries.conf); weitere lassen sich durch eine zusätzliche Zeile hinzufügen (siehe Kommentar dort).

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

## Starten / Stoppen / Neustarten

Einzelnes Land:

```bash
./bin/start-country italy
./bin/stop-country italy
./bin/restart-country italy
```

Alle installierten Länder:

```bash
./bin/start-all
./bin/stop-all
./bin/restart-all
```

Gestoppte Container verlieren ihre Datenbank nicht — die Daten liegen persistent unter `./data/<land>/db`.

## Logs

```bash
./bin/logs italy
```

## Testen

```bash
./bin/test-country italy
```

```text
Testing overpass-italy at localhost:18001...

HTTP: 200
Overpass API: OK
```

## Entfernen

```bash
./bin/remove-country italy
```

Zeigt Container- und Datenbankgröße an und verlangt die exakte Eingabe des Ländernamens zur Bestätigung. Ohne korrekte Bestätigung wird nichts gelöscht.

## Overpass-Query ausführen

```bash
curl \
  --data-urlencode 'data=[out:json];node["amenity"="restaurant"](43.39,10.84,43.42,10.89);out;' \
  http://localhost:18001/api/interpreter
```

## Architektur

Jedes Land bekommt einen eigenen, vollständig unabhängigen Container samt Datenbank, Port und Update-Stream:

```text
italy   → overpass-italy   → ./data/italy/db    → Port 18001 → italy-updates/
germany → overpass-germany → ./data/germany/db  → Port 18002 → germany-updates/
```

Es gibt **keine statische `docker-compose.yml` pro Land**. Stattdessen wird eine einzige `docker-compose.yml` im Projektwurzelverzeichnis von `lib/common.sh` (Funktion `render_compose`) **automatisch neu generiert**, sobald ein Land hinzugefügt oder entfernt wird. Grundlage dafür ist ausschließlich `data/<land>/instance.env` — diese Datei ist die einzige Zustandsquelle für "welche Länder sind installiert, mit welchem Port". `docker-compose.yml` wird deshalb nicht versioniert (`.gitignore`) und darf nicht von Hand editiert werden.

### Verzeichnisstruktur

```text
GIS-Overpass-Server/
├── docker-compose.yml       # auto-generiert, nicht von Hand editieren
├── config/
│   └── countries.conf       # Katalog: land|pbf_url|diff_url
├── lib/
│   └── common.sh            # gemeinsame Funktionen aller bin/*-Skripte
├── bin/                      # setup-country, status, logs, ...
└── data/
    └── <land>/
        ├── instance.env      # Port, URLs, Zeitstempel (unser State)
        └── db/                # persistente Overpass-Datenbank (Bind-Mount von /db)
```

### Ports

Ports werden automatisch vergeben, beginnend bei `18001`, aufsteigend, unter Vermeidung bereits belegter Ports (sowohl unserer eigenen Installationen als auch fremder Prozesse auf dem Host). Die API ist standardmäßig auf **allen Interfaces** erreichbar (`0.0.0.0:<port>`), damit sie auch aus dem LAN nutzbar ist:

```text
http://HOST:18001/api/interpreter
```

> **Sicherheitshinweis:** Es ist **keine Authentifizierung** eingebaut. Die Ports dürfen deshalb **nicht ungeschützt ins Internet veröffentlicht werden** (kein Port-Forwarding, keine öffentliche Firewall-Freigabe) — nur im vertrauenswürdigen LAN bzw. hinter einem eigenen Reverse Proxy mit Auth verwenden.

## Updates

Nach dem initialen Import hält sich jede Instanz automatisch über den in `config/countries.conf` hinterlegten Geofabrik-Replication-Feed (`<land>-updates/`) aktuell — das ist die eingebaute Update-Mechanik von `wiktorn/overpass-api` (`OVERPASS_DIFF_URL` + `OVERPASS_UPDATE_SLEEP`, hier auf täglich gestellt), keine selbstgebaute Lösung. Jedes Land hat dabei seinen eigenen, unabhängigen Replication-State innerhalb seiner eigenen `/db`.

```text
italy   → italy-updates/   → overpass-italy   (eigener Replication-State)
germany → germany-updates/ → overpass-germany (eigener Replication-State)
```

## Speicherverbrauch

- Vor jedem `setup-country` wird der freie Speicherplatz per `df` geprüft; bei offensichtlich wenig freiem Platz (Standard: < 20 GB, überschreibbar über `MIN_FREE_GB`) erscheint eine Warnung mit Rückfrage. Es wird bewusst **keine** exakte Vorhersage der fertigen Datenbankgröße versucht.
- Die heruntergeladene Quell-PBF wird nach erfolgreichem Aufbau der Datenbank standardmäßig gelöscht. Mit `--keep-pbf` bleibt sie unter `data/<land>/db/source.osm.pbf` erhalten.
- Während der Initialisierung entsteht kurzzeitig eine zusätzliche Kopie der PBF-Daten im Container (siehe unten) — das ist vorübergehend und wird automatisch aufgeräumt.

## Deviations from the original technical proposal

Diese drei Punkte weichen bewusst von der ursprünglichen Anfrage ab, basierend auf der aktuellen Dokumentation von `wiktorn/overpass-api` und den tatsächlichen Netzwerkbedingungen:

1. **Resumable Download auf dem Host statt im Container.** Das Image lädt `OVERPASS_PLANET_URL` selbst herunter — aber mit einem einzelnen, nicht fortsetzbaren `curl -L -o` (kein `-C -`). Auf einer langsamen oder instabilen Leitung würde ein Verbindungsabbruch bei großen Ländern (mehrere GB) den kompletten Download zunichtemachen. Stattdessen lädt `bin/setup-country` die PBF-Datei selbst mit `curl -C - --retry` auf den Host herunter (`data/<land>/db/source.osm.pbf`) und übergibt dem Container eine `file://`-URL. Ein Abbruch lässt sich durch einfaches erneutes Ausführen von `setup-country` fortsetzen. Dadurch entsteht während der Initialisierung kurzzeitig eine zweite Kopie der Datei im Container (`osmium`-Konvertierung), die danach automatisch gelöscht wird.
2. **`OVERPASS_STOP_AFTER_INIT=false`.** Der Default des Images (`true`) lässt den Container nach der Initialisierung beenden und verlässt sich auf `restart: unless-stopped`, um danach in den Serve-Modus überzugehen. Für einen einzigen, klar nachvollziehbaren Lebenszyklus (inkl. Fortschrittsanzeige über den Docker-Healthcheck) wird das hier explizit deaktiviert.
3. **Geofabrik-eigene `-updates/`-Feeds statt des openstreetmap.fr-Mirrors** aus dem Beispiel in der Overpass-API-Dokumentation, da die Aufgabenstellung explizit einen Geofabrik-Replication-Feed vorsieht.

## Beispiel-Workflow

```bash
./bin/setup-country italy
./bin/setup-country germany

./bin/status

./bin/stop-country germany

./bin/test-country italy

./bin/start-country germany

./bin/remove-country italy
```
