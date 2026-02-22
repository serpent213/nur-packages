{
  lib,
  servingSchema ? "osm_serving",
  profile ? "compact",
}:
if profile == "openmaptiles"
then
  import ./mk-serving-refresh-sql-openmaptiles.nix {
    inherit
      lib
      servingSchema
      ;
  }
else
  import ./mk-serving-refresh-sql-compact.nix {
    inherit
      lib
      servingSchema
      ;
  }
