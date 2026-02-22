# osm-tiles-demo Docker image

This package builds a self-contained Docker image that runs:

- PostgreSQL + PostGIS
- runtime external imports (Natural Earth + water polygons)
- runtime OSM import via `imposm` (selected countries or empty bootstrap)
- generated OpenMapTiles SQL (minimal layer subset)
- Martin vector tile server
- nginx cache reverse proxy
- sample MapLibre JS site

## Build image

From the NUR repo root:

```bash
nix build .#osm-tiles-demo
```

On macOS, build with a Linux builder, for example:

```bash
nix-build . -A osm-tiles-demo --arg pkgs 'import <nixpkgs> { system = "x86_64-linux"; }'
```

## Build with custom locales/countries

`osm-tiles-demo` accepts build-time args:

- `locales` (list of strings, default `["en"]`)
- `countries` (list of Geofabrik path suffixes, default `[]`)
- `ramMB` (integer, default `4096`; managed PostgreSQL memory target)
- `geofabrikBaseUrl` (default `https://download.geofabrik.de`)

Example:

```bash
nix-build . \
  -A osm-tiles-demo \
  --arg pkgs 'import <nixpkgs> { system = "x86_64-linux"; }' \
  --arg ramMB 8192 \
  --arg locales '["en" "de" "hu"]' \
  --arg countries '["europe/hungary"]'
```

## Load image into Docker

```bash
docker load < result
```

## Run

```bash
docker run --rm -p 8080:8080 --name osm-tiles-demo osm-tiles-demo:latest
```

Open http://localhost:8080/.

First startup imports external sources and OSM, then prepares SQL/materialized views.

## Persist demo data (optional)

```bash
mkdir -p ./osm-tiles-demo-data
chmod 0777 ./osm-tiles-demo-data

docker run --rm \
  -p 8080:8080 \
  -v "$(pwd)/osm-tiles-demo-data:/data" \
  --name osm-tiles-demo \
  osm-tiles-demo:latest
```

## Runtime skip flags (advanced)

Skip external imports:

```bash
docker run --rm -p 8080:8080 -e OSM_TILES_SKIP_EXTERNAL_IMPORT=1 osm-tiles-demo:latest
```

Skip OSM import:

```bash
docker run --rm -p 8080:8080 -e OSM_TILES_SKIP_OSM_IMPORT=1 osm-tiles-demo:latest
```

## Use custom MapLibre asset URLs

```bash
nix-build . \
  -A osm-tiles-demo \
  --arg pkgs 'import <nixpkgs> { system = "x86_64-linux"; }' \
  --argstr maplibreCssUrl /assets/maplibre/maplibre-gl.css \
  --argstr maplibreJsUrl /assets/maplibre/maplibre-gl.js
```

## Tests

From `nix/nur-packages`, run:

```bash
nix-build -A osm-tiles-tests
```

Smoke tests (Linux builder required):

```bash
nix-build -A osm-tiles-tests.passthru.tests.moduleSmoke
nix-build -A osm-tiles-tests.passthru.tests.dockerSmoke
```

Notes:

- NixOS VM smoke tests require a builder with `nixos-test` and `kvm` features.
- Docker smoke requires builder network/DNS access to fetch pinned upstream OpenMapTiles sources.
