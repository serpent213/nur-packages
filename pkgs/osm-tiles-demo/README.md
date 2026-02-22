# osm-tiles-demo Docker image

This package builds a self-contained Docker image that runs:

- PostgreSQL + PostGIS
- Natural Earth import (on first start)
- Martin vector tile server
- nginx cache reverse proxy
- sample MapLibre JS site

## Build image

From the NUR repo root:

```bash
nix build .#osm-tiles-demo
```

Example forcing a specific system (required on my macOS/Darwin to pick my x86_64-linux remote build host – Docker build requires some Linux build host):

```bash
nix-build . -A osm-tiles-demo --arg pkgs 'import <nixpkgs> { system = "x86_64-linux"; }'
```

## Build with custom locales/countries

`osm-tiles-demo` accepts build-time args:

- `locales` (list of strings, default `["en"]`)
- `countries` (list of Geofabrik path suffixes, default `[]`)
- `ramMB` (integer, default `4096`; drives PostgreSQL managed-memory tuning in the demo)
- `geofabrikBaseUrl` (default `https://download.geofabrik.de`)
- `servingProfile` (`"openmaptiles"` or `"compact"`, default `"openmaptiles"`)

Example:

```bash
nix-build . \
  -A osm-tiles-demo \
  --arg pkgs 'import <nixpkgs> { system = "x86_64-linux"; }' \
  --arg ramMB 8192 \
  --argstr servingProfile openmaptiles \
  --arg locales '["en" "de"]' \
  --arg countries '["europe/germany" "africa/senegal-and-gambia"]'
```

If `countries` is non-empty, those extracts are imported automatically on first container startup.

## Load image into Docker

```bash
docker load < result
```

## Run

```bash
docker run --rm -p 8080:8080 --name osm-tiles-demo osm-tiles-demo:latest
```

Then open:

- http://localhost:8080/

The first startup imports Natural Earth files and may take a short while.

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

## Skip Natural Earth download (advanced)

```bash
docker run --rm -p 8080:8080 -e OSM_TILES_SKIP_NE_DOWNLOAD=1 osm-tiles-demo:latest
```

This starts with empty low-res tables.

## Skip country imports (advanced)

```bash
docker run --rm -p 8080:8080 -e OSM_TILES_SKIP_COUNTRY_IMPORT=1 osm-tiles-demo:latest
```

## Tune country import resources (advanced)

```bash
docker run --rm -p 8080:8080 \
  -e OSM_TILES_IMPORT_CACHE_MB=2048 \
  -e OSM_TILES_IMPORT_PROCESSES=2 \
  osm-tiles-demo:latest
```

## Use custom/relative MapLibre asset paths

You can override the sample client MapLibre JS/CSS URLs at build time. Relative paths are supported if your deployment serves those files:

```bash
nix-build . \
  -A osm-tiles-demo \
  --arg pkgs 'import <nixpkgs> { system = "x86_64-linux"; }' \
  --argstr maplibreCssUrl /assets/maplibre/maplibre-gl.css \
  --argstr maplibreJsUrl /assets/maplibre/maplibre-gl.js
```

## Tests

From the NUR repo root (`nix/nur-packages`), run:

```bash
nix-build -A osm-tiles-tests
```

Quick checks only (generator/output assertions).

```bash
nix-build -A osm-tiles-tests.passthru.tests.moduleSmoke
```

NixOS VM smoke test for the `services.osmTiles` module.

```bash
nix-build -A osm-tiles-tests.passthru.tests.dockerSmoke
```

NixOS VM smoke test that loads/runs the `osm-tiles-demo` Docker image and checks HTTP/tile endpoints.

Notes:

- Full smoke tests require a Linux build host.
- On non-Linux hosts (for example macOS), both smoke targets resolve to explicit `*-skipped` derivations with a reason file.
