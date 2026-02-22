{
  lib,
  locales,
  countrySchemas,
  dbUser,
  servingSchema ? "osm_serving",
  lowresSchema ? "osm_lowres",
  profile ? "compact",
}:
if profile == "openmaptiles"
then
  import ./mk-serving-setup-sql-openmaptiles.nix {
    inherit
      countrySchemas
      dbUser
      lib
      lowresSchema
      servingSchema
      ;
  }
else
  import ./mk-serving-setup-sql-compact.nix {
    inherit
      countrySchemas
      dbUser
      lib
      locales
      lowresSchema
      servingSchema
      ;
  }
