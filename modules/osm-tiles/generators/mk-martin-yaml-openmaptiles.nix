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

  baseNameProps = {
    class = "text";
    name = "text";
    name_de = "text";
    name_en = "text";
    name_fr = "text";
    "name:latin" = "text";
    "name:nonlatin" = "text";
  };

  baseNameRefProps = baseNameProps // {ref = "text";};

  mkTable = {
    table,
    properties ? {},
    geometryType ? "GEOMETRY",
    minzoom ? null,
    maxzoom ? null,
  }:
    {
      schema = servingSchema;
      inherit
        bounds
        properties
        table
        ;
      geometry_column = "geom";
      geometry_type = geometryType;
      srid = 3857;
    }
    // lib.optionalAttrs (minzoom != null) {inherit minzoom;}
    // lib.optionalAttrs (maxzoom != null) {inherit maxzoom;};

  mkFunction = {
    functionName,
    minzoom ? null,
    maxzoom ? null,
  }:
    {
      schema = servingSchema;
      function = functionName;
      inherit bounds;
    }
    // lib.optionalAttrs (minzoom != null) {inherit minzoom;}
    // lib.optionalAttrs (maxzoom != null) {inherit maxzoom;};
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

      tables = {
        aeroway = mkTable {
          table = "aeroway";
          properties = baseNameRefProps // {iata = "text";};
          minzoom = 10;
        };

        building = mkTable {
          table = "building";
          properties = baseNameProps;
          minzoom = 12;
        };
      };

      functions = {
        park = mkFunction {
          functionName = "park_zxy";
          minzoom = 4;
        };

        water = mkFunction {
          functionName = "water_zxy";
          minzoom = 0;
        };

        boundary = mkFunction {
          functionName = "boundary_zxy";
          minzoom = 0;
        };

        landcover = mkFunction {
          functionName = "landcover_zxy";
          minzoom = 0;
        };

        landuse = mkFunction {
          functionName = "landuse_zxy";
          minzoom = 7;
        };

        transportation = mkFunction {
          functionName = "transportation_zxy";
          minzoom = 4;
        };

        transportation_name = mkFunction {
          functionName = "transportation_name_zxy";
          minzoom = 6;
        };

        waterway = mkFunction {
          functionName = "waterway_zxy";
          minzoom = 5;
        };

        water_name = mkFunction {
          functionName = "water_name_zxy";
          minzoom = 9;
        };

        place = mkFunction {
          functionName = "place_zxy";
          minzoom = 0;
        };
      };
    };
  }
