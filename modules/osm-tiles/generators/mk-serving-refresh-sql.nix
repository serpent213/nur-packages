{
  lib,
  servingSchema ? "osm_serving",
}: let
  common = import ./common.nix {inherit lib;};
  inherit (common) quoteIdent;
in ''
  BEGIN;

  REFRESH MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"};
  REFRESH MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"};
  REFRESH MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"};
  REFRESH MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "place_api"};

  ANALYZE ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"};
  ANALYZE ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"};
  ANALYZE ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"};
  ANALYZE ${quoteIdent servingSchema}.${quoteIdent "place_api"};

  COMMIT;
''
