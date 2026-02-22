# osmTiles

`services.osmTiles` provides an OpenMapTiles-based vector tile stack using:

- `openmaptiles-tools` code generation (`generate-imposm3`, `generate-sql`, `generate-sqltomvt`)
- `imposm` for OSM snapshot imports and replication updates
- runtime imports for Natural Earth and water polygons
- Martin tile server
- optional nginx cache reverse proxy
- optional sample MapLibre site

## Minimal setup (NE-only by default countries)

```nix
{
  services.osmTiles = {
    enable = true;

    data.countries = {};

    nginx = {
      listenAddress = "127.0.0.1";
      listenPort = 8080;
      serverName = "_";
    };
  };
}
```

## Country extracts

```nix
{
  services.osmTiles.data.countries = {
    hungary.geofabrikPath = "europe/hungary";
    germany.geofabrikPath = "europe/germany";
  };
}
```

## Components

- `services.osmTiles.components.osmImport.enable`
- `services.osmTiles.components.osmUpdate.enable`
- `services.osmTiles.components.martin.enable`
- `services.osmTiles.components.nginx.enable`
- `services.osmTiles.components.sampleClient.enable`

If OSM import or update is enabled, Natural Earth/water external imports are enabled as part of bootstrap.

## Jobs

Two update timers:

- `services.osmTiles.jobs.osmUpdate.*`
- `services.osmTiles.jobs.neUpdate.*`

Serving refresh timer:

- `services.osmTiles.jobs.servingRefresh.*`

The OSM update job triggers `osm-tiles-serving-refresh.service` on successful completion.

## Managed PostgreSQL RAM

`services.osmTiles.database.managed.ramMB` controls managed PostgreSQL tuning:

- `shared_buffers = ramMB`
- `effective_cache_size = 2 * ramMB`
