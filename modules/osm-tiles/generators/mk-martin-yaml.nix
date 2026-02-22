{
  lib,
  routePrefix,
  connectionString,
  poolSize,
  workerProcesses,
  servingSchema ? "osm_serving",
}: let
  bounds = [
    (-180.0)
    (-85.051129)
    180.0
    85.051129
  ];

  mkFunction = functionName: {
    schema = servingSchema;
    function = functionName;
    inherit bounds;
  };
in
  lib.generators.toYAML {} {
    cache_size_mb = 0;
    worker_processes = workerProcesses;
    route_prefix = routePrefix;

    postgres = {
      connection_string = connectionString;
      pool_size = poolSize;
      auto_bounds = "skip";
      auto_publish = false;
      functions = {
        landcover = mkFunction "landcover_zxy";
        water = mkFunction "water_zxy";
        boundary = mkFunction "boundary_zxy";
        place = mkFunction "place_zxy";
      };
    };
  }
