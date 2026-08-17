# Aufgabe: Multi-Country Overpass GIS Server

Erstelle in diesem **leeren Projektordner `GIS-Overpass-Server`** ein vollständiges Docker-basiertes Setup zum Betrieb eigener Overpass-API-Instanzen.

## Ziel

Für jedes installierte Land soll eine **eigene Overpass-API-Instanz** mit eigener Datenbank laufen.

Beispiel:

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

Die genaue Struktur darf verbessert werden, wenn es technisch sinnvoller ist.

---

## Grundarchitektur

Verwende Docker Compose und das Image:

```text
wiktorn/overpass-api
```

Jedes Land erhält:

- eigenen Docker-Container
- eigene Overpass-Datenbank
- eigenes persistentes Datenverzeichnis
- eigenen Port
- eigenen Geofabrik-PBF-Download
- eigenen Geofabrik-Replication/Update-Feed

Beispiel:

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

Die Ports sollen automatisch verwaltet werden.

---

# Wichtig: keine statische Compose-Datei pro Land

Die Länder sollen dynamisch verwaltet werden können.

Ich möchte beispielsweise:

```bash
./bin/setup-country italy
./bin/setup-country germany
./bin/setup-country czech-republic
```

ausführen können.

Danach:

```bash
./bin/status
```

z. B.:

```text
COUNTRY          PORT    STATUS       DB SIZE
------------------------------------------------
italy            18001   running      18.4 GB
germany          18002   stopped      37.2 GB
czech-republic   18003   running       8.1 GB
```

Entwirf dafür eine robuste, aber möglichst einfache Lösung.

Falls Docker Compose Profiles, dynamisch generierte Compose-Dateien oder ein anderes Compose-Konzept dafür sinnvoll sind, entscheide dich für die wartbarste Lösung.

**Keine Kubernetes-Lösung.**

---

# Länder-Konfiguration

Die Konfiguration soll deklarativ sein.

Beispielsweise:

```text
config/countries.conf
```

oder YAML/JSON, falls sinnvoller.

Darin sollen mindestens stehen:

```text
country
Geofabrik PBF URL
Geofabrik Update URL
Port
```

Die Geofabrik-URLs sollen nicht unnötig hart im Code verteilt sein.

Beispiele:

```text
italy
germany
austria
switzerland
czech-republic
france
```

Es muss aber einfach möglich sein, weitere Geofabrik-Regionen hinzuzufügen.

---

# setup-country

Der wichtigste Befehl:

```bash
./bin/setup-country italy
```

Er soll:

1. prüfen, ob das Land bekannt ist
2. prüfen, ob es bereits installiert ist
3. benötigte Verzeichnisse erzeugen
4. freien bzw. konfigurierten Port bestimmen
5. PBF von Geofabrik herunterladen
6. notwendige Konvertierung für Overpass durchführen
7. Overpass-Datenbank initialisieren
8. Update/Replication-Konfiguration einrichten
9. Container starten
10. auf erfolgreiche Initialisierung warten bzw. verständlich den Fortschritt anzeigen
11. am Ende Endpoint und Status ausgeben

Beispiel:

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

Der Prozess muss auch bei großen Ländern robust sein.

Downloads sollten möglichst wiederaufnehmbar sein (`curl -C -` o. ä.).

---

# Start / Stop

Einzelne Länder:

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

Ein gestoppter Server darf natürlich seine Datenbank nicht verlieren.

---

# Status

```bash
./bin/status
```

soll mindestens anzeigen:

```text
COUNTRY          PORT    CONTAINER              STATUS       DISK
------------------------------------------------------------------
italy            18001   overpass-italy         running      18G
germany          18002   overpass-germany       stopped      39G
```

Optional zusätzlich:

- Health
- Zeitpunkt des letzten Updates
- Container-Uptime

---

# Logs

Unterstütze:

```bash
./bin/logs italy
```

entsprechend ungefähr:

```bash
docker logs -f overpass-italy
```

---

# Entfernen

```bash
./bin/remove-country italy
```

Dabei muss ausdrücklich darauf hingewiesen werden, dass die Overpass-Datenbank gelöscht wird.

Beispiel:

```text
This will remove:

Container: overpass-italy
Database:  ./data/italy (18.4 GB)

Type "italy" to confirm:
```

Ohne korrekte Bestätigung darf nichts gelöscht werden.

---

# Updates

Die Overpass-Instanzen sollen nach dem initialen Import automatisch mit den entsprechenden Geofabrik-Diffs aktuell gehalten werden.

Jedes Land muss seinen eigenen Replication-State besitzen.

Beispiel:

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

Überprüfe anhand der aktuellen Dokumentation von `wiktorn/overpass-api`, wie `OVERPASS_DIFF_URL`, Update-Intervalle und Replication-State korrekt konfiguriert werden.

Keine selbst erfundene Update-Mechanik verwenden, wenn das Image dies bereits unterstützt.

---

# Docker

Container-Namen:

```text
overpass-<country>
```

Beispiele:

```text
overpass-italy
overpass-germany
overpass-czech-republic
```

Persistente Daten:

```text
./data/<country>/
```

Container sollen:

```yaml
restart: unless-stopped
```

verwenden.

API-Port intern:

```text
80
```

Host-Ports beispielsweise ab:

```text
18001
```

Ports dürfen nicht kollidieren.

---

# Netzwerkzugriff

Standardmäßig soll die API auf allen Interfaces des Docker-Hosts erreichbar sein:

```text
0.0.0.0:18001
```

Damit kann sie auch aus dem LAN benutzt werden.

Dokumentiere den entsprechenden Endpoint:

```text
http://HOST:18001/api/interpreter
```

Es soll **keine Authentifizierung** eingebaut werden.

Im README deutlich darauf hinweisen, dass die Ports deshalb **nicht ungeschützt ins Internet veröffentlicht werden sollten**.

---

# Test

Erstelle:

```bash
./bin/test-country italy
```

Der Test soll eine kleine Overpass-Abfrage gegen die entsprechende Instanz senden.

Zum Beispiel eine ungefährliche kleine Query wie:

```overpass
[out:json][timeout:10];
node(1);
out;
```

oder eine andere Query, die zuverlässig überprüft, ob `/api/interpreter` korrekt arbeitet.

Erwartetes Verhalten:

```text
Testing overpass-italy at localhost:18001...

HTTP: 200
Overpass API: OK
```

---

# Fehlerbehandlung

Alle Scripts sollen:

```bash
set -euo pipefail
```

oder eine entsprechend robuste Fehlerbehandlung verwenden.

Prüfe Voraussetzungen wie:

```text
docker
docker compose
curl
```

und liefere verständliche Fehlermeldungen.

Beispiele:

```text
ERROR: Docker is not installed.
ERROR: Country 'xyz' is unknown.
ERROR: Port 18001 is already in use.
ERROR: Country 'italy' is already installed.
```

---

# PBF-Dateien

Vermeide unnötigen SSD-Verbrauch.

Wenn die heruntergeladene `.osm.pbf` nach erfolgreichem Aufbau der Overpass-Datenbank nicht mehr benötigt wird, soll sie standardmäßig gelöscht werden.

Optional:

```bash
./bin/setup-country italy --keep-pbf
```

damit die Quelldatei erhalten bleibt.

Temporäre Konvertierungsdateien ebenfalls nach erfolgreichem Import entfernen.

---

# Speicherplatzprüfung

Vor dem Import soll möglichst abgeschätzt bzw. geprüft werden, ob genügend freier Speicherplatz vorhanden ist.

Mindestens:

```bash
df
```

auswerten und freien Speicher anzeigen.

Nicht versuchen, eine vermeintlich exakte Größe der fertigen Overpass-Datenbank vorherzusagen.

Bei offensichtlich wenig freiem Speicher eine deutliche Warnung ausgeben.

---

# Idempotenz

Scripts dürfen bestehende Installationen nicht versehentlich zerstören.

Insbesondere:

```bash
./bin/setup-country italy
```

bei bereits vorhandenem Italien muss abbrechen und darf `/data/italy` nicht überschreiben.

---

# README

Erstelle eine gute, kompakte `README.md`.

Sie soll mindestens enthalten:

## Installation

```bash
git clone ...
cd GIS-Overpass-Server
```

## Land installieren

```bash
./bin/setup-country italy
```

## Status

```bash
./bin/status
```

## Stoppen

```bash
./bin/stop-country italy
```

## Starten

```bash
./bin/start-country italy
```

## Testen

```bash
./bin/test-country italy
```

## Entfernen

```bash
./bin/remove-country italy
```

## Overpass Query

Beispiel:

```bash
curl \
  --data-urlencode 'data=[out:json];node["amenity"="restaurant"](43.39,10.84,43.42,10.89);out;' \
  http://localhost:18001/api/interpreter
```

Außerdem Architektur, Verzeichnisstruktur, Updates und Speicherverbrauch kurz erklären.

---

# Implementierungsprinzipien

Prioritäten:

1. Einfachheit
2. Robustheit
3. Wartbarkeit
4. möglichst wenig SSD-Verbrauch
5. Länder vollständig voneinander unabhängig
6. keine unnötigen zusätzlichen Services
7. keine Kubernetes-/Swarm-Abhängigkeit

Shell-Scripts bevorzugen, wenn keine andere Sprache einen deutlichen Vorteil bringt.

Keine unnötig komplexe Framework-Lösung bauen.

---

# Wichtig: zuerst recherchieren

Bevor du implementierst:

1. Prüfe die **aktuelle Dokumentation** von `wiktorn/overpass-api`.
2. Prüfe die aktuellen Geofabrik Download- und Update-URLs.
3. Prüfe insbesondere, wie ein `.osm.pbf` mit dem aktuellen Docker-Image korrekt initialisiert wird.
4. Prüfe, ob die PBF-Konvertierung tatsächlich erforderlich ist oder inzwischen ein direkter Import möglich ist.
5. Prüfe die korrekte Verwendung von:
   - `OVERPASS_MODE`
   - `OVERPASS_PLANET_URL`
   - `OVERPASS_DIFF_URL`
   - `OVERPASS_UPDATE_SLEEP`
   - `OVERPASS_META`
   - `/db`
6. Implementiere anhand der aktuellen Funktionsweise und **nicht anhand veralteter Beispiele**.

Wenn meine vorgeschlagene technische Umsetzung an einer Stelle nicht zur aktuellen Funktionsweise des Images passt, ändere sie entsprechend und dokumentiere kurz im README, warum.

## Ergebnis

Implementiere das Projekt vollständig im aktuellen Ordner.

Am Ende soll insbesondere dies funktionieren:

```bash
./bin/setup-country italy
./bin/setup-country germany

./bin/status

./bin/stop-country germany

./bin/test-country italy

./bin/start-country germany

./bin/remove-country italy
```

Italien und Deutschland müssen dabei vollständig unabhängige Overpass-Datenbanken und Update-Streams besitzen.
