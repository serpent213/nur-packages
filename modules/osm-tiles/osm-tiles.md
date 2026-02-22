# osmTiles

`services.osmTiles` provides a composable map tile stack based on:

- `osm2pgsql` imports + replication updates
- Natural Earth low-resolution fallback data
- Martin vector tile server
- Optional nginx caching reverse proxy
- Optional sample MapLibre JS website

## Minimal NE-only setup

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

This starts with Natural Earth data only (no country extracts) and exposes the sample client on `http://127.0.0.1:8080/`.

## Country extracts

```nix
{
  services.osmTiles.data.countries = {
    germany = {
      geofabrikPath = "europe/germany";
    };

    senegal-and-gambia = {
      geofabrikPath = "africa/senegal-and-gambia";
    };
  };
}
```

## Jobs

Two update timers are exposed and configurable:

- `services.osmTiles.jobs.osmUpdate.*`
- `services.osmTiles.jobs.neUpdate.*`

Serving refresh behavior is controlled via:

- `services.osmTiles.jobs.servingRefresh.*`

When OSM update job succeeds, `osm-tiles-serving-refresh.service` is triggered automatically.

## Managed PostgreSQL RAM

`services.osmTiles.database.managed.ramMB` controls managed PostgreSQL memory tuning:

- `shared_buffers = ramMB`
- `effective_cache_size = 2 * ramMB`
