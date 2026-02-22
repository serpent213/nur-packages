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
