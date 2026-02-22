{
  pkgs,
  title ? "OSM Tiles Demo",
  maptilesPath ? "/maptiles",
  servingProfile ? "compact",
  maplibreCssUrl ? "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.css",
  maplibreJsUrl ? "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.js",
}: let
  normalizedPath =
    if maptilesPath == ""
    then "/maptiles"
    else if builtins.substring 0 1 maptilesPath == "/"
    then maptilesPath
    else "/${maptilesPath}";

  sourceLayers =
    if servingProfile == "openmaptiles"
    then [
      "landcover"
      "landuse"
      "park"
      "water"
      "waterway"
      "boundary"
      "transportation"
      "transportation_name"
      "water_name"
      "place"
    ]
    else [
      "landcover"
      "water"
      "boundary"
      "place"
    ];

  sourceLayersCsv = builtins.concatStringsSep "," sourceLayers;
  sourceLayersLegend = builtins.concatStringsSep ", " sourceLayers;
in
  pkgs.runCommand "osm-tiles-sample-client" {} ''
    mkdir -p "$out"

    cat > "$out/index.html" <<'HTML'
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>${title}</title>
        <link rel="stylesheet" href="${maplibreCssUrl}" />
        <style>
          html, body {
            margin: 0;
            height: 100%;
            font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
            background: #f4f7fb;
          }

          #map {
            height: 100%;
            width: 100%;
          }

          .legend {
            position: absolute;
            right: 12px;
            top: 12px;
            background: rgba(255, 255, 255, 0.92);
            border: 1px solid #d8dee8;
            border-radius: 8px;
            padding: 10px 12px;
            font-size: 12px;
            line-height: 1.3;
            color: #1f2a37;
            z-index: 10;
          }
        </style>
      </head>
      <body>
        <div class="legend">
          <div><strong>Sample MapLibre Client</strong></div>
          <div>Tiles: ${normalizedPath}</div>
          <div>Layers: ${sourceLayersLegend}</div>
        </div>
        <div id="map"></div>

        <script src="${maplibreJsUrl}"></script>
        <script>
          const maptilesBaseUrl = window.location.origin + "${normalizedPath}";
          const maptilesUrlTemplate = maptilesBaseUrl + "/${sourceLayersCsv}/{z}/{x}/{y}";

          const map = new maplibregl.Map({
            container: "map",
            center: [8, 20],
            zoom: 2,
            style: {
              version: 8,
              glyphs: "https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf",
              sources: {
                osm_tiles: {
                  type: "vector",
                  tiles: [maptilesUrlTemplate],
                  minzoom: 0,
                  maxzoom: 14
                }
              },
              layers: [
                {
                  id: "background",
                  type: "background",
                  paint: {"background-color": "#ecf1f6"}
                },
                {
                  id: "landcover",
                  type: "fill",
                  source: "osm_tiles",
                  "source-layer": "landcover",
                  paint: {"fill-color": "#dbe9d5", "fill-opacity": 0.9}
                },
                ${
      if servingProfile == "openmaptiles"
      then ''
        {
          id: "landuse",
          type: "fill",
          source: "osm_tiles",
          "source-layer": "landuse",
          paint: {"fill-color": "#e9e2c2", "fill-opacity": 0.35}
        },
        {
          id: "park",
          type: "fill",
          source: "osm_tiles",
          "source-layer": "park",
          paint: {"fill-color": "#cfe8c8", "fill-opacity": 0.55}
        },
        {
          id: "waterway",
          type: "line",
          source: "osm_tiles",
          "source-layer": "waterway",
          paint: {"line-color": "#8ab6e3", "line-width": ["interpolate", ["linear"], ["zoom"], 4, 0.2, 12, 1.3]}
        },
        {
          id: "transportation",
          type: "line",
          source: "osm_tiles",
          "source-layer": "transportation",
          paint: {"line-color": "#5f6672", "line-width": ["interpolate", ["linear"], ["zoom"], 4, 0.35, 12, 2.2]}
        },
        {
          id: "transportation_name",
          type: "symbol",
          source: "osm_tiles",
          "source-layer": "transportation_name",
          minzoom: 10,
          layout: {"text-field": ["coalesce", ["get", "name_en"], ["get", "name"], ["get", "ref"]], "text-size": 11},
          paint: {"text-color": "#354052", "text-halo-color": "#f4f7fb", "text-halo-width": 1}
        },
        {
          id: "water_name",
          type: "symbol",
          source: "osm_tiles",
          "source-layer": "water_name",
          minzoom: 9,
          layout: {"text-field": ["coalesce", ["get", "name_en"], ["get", "name"]], "text-size": 11},
          paint: {"text-color": "#4f7fb4", "text-halo-color": "#f4f7fb", "text-halo-width": 1}
        },
      ''
      else ""
    }
                {
                  id: "water",
                  type: "fill",
                  source: "osm_tiles",
                  "source-layer": "water",
                  paint: {"fill-color": "#a8c9f0", "fill-opacity": 0.95}
                },
                {
                  id: "boundary",
                  type: "line",
                  source: "osm_tiles",
                  "source-layer": "boundary",
                  paint: {"line-color": "#6f7f95", "line-width": ["interpolate", ["linear"], ["zoom"], 1, 0.5, 5, 1.2]}
                },
                {
                  id: "place",
                  type: "symbol",
                  source: "osm_tiles",
                  "source-layer": "place",
                  layout: {
                    "text-field": ["coalesce", ["get", "name_en"], ["get", "name"]],
                    "text-size": ["interpolate", ["linear"], ["zoom"], 2, 10, 8, 14]
                  },
                  paint: {"text-color": "#213042", "text-halo-color": "#f4f7fb", "text-halo-width": 1}
                }
              ]
            }
          });

          map.addControl(new maplibregl.NavigationControl(), "top-left");
        </script>
      </body>
    </html>
    HTML
  ''
