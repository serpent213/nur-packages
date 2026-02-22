{
  lib,
  locales,
}: let
  languageLines = lib.concatMapStringsSep "\n" (locale: "    - ${locale}") locales;
in ''
  tileset:
    layers:
      - layers/water/water.yaml
      - layers/landcover/landcover.yaml
      - layers/boundary/boundary.yaml
      - layers/place/place.yaml
    name: OpenMapTiles Minimal
    version: 3.16.0
    id: openmaptiles_minimal
    description: "Minimal OpenMapTiles subset for self-hosted Martin demos"
    attribution: '<a href="https://www.openmaptiles.org/" target="_blank">&copy; OpenMapTiles</a> <a href="https://www.openstreetmap.org/copyright" target="_blank">&copy; OpenStreetMap contributors</a>'
    center: [0, 0, 1]
    bounds: [-180.0, -85.0511, 180.0, 85.0511]
    maxzoom: 14
    minzoom: 0
    pixel_scale: 256
    languages:
  ${languageLines}
    defaults:
      srs: +proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0.0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs +over
      datasource:
        srid: 900913
''
