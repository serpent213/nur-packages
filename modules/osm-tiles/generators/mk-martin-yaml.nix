{
  lib,
  routePrefix,
  connectionString,
  poolSize,
  workerProcesses,
  servingSchema ? "osm_serving",
  profile ? "compact",
}:
if profile == "openmaptiles"
then
  import ./mk-martin-yaml-openmaptiles.nix {
    inherit
      connectionString
      lib
      poolSize
      routePrefix
      servingSchema
      workerProcesses
      ;
  }
else
  import ./mk-martin-yaml-compact.nix {
    inherit
      connectionString
      lib
      poolSize
      routePrefix
      servingSchema
      workerProcesses
      ;
  }
