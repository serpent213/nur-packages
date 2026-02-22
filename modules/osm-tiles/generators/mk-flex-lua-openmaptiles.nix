{pkgs}:
pkgs.writeText "osm-tiles-flex-openmaptiles.lua" (builtins.readFile ./templates/flex-openmaptiles.lua)
