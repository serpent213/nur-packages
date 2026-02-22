{
  pkgs,
  title ? "OSM Tiles Demo",
  maptilesPath ? "/maptiles",
  maplibreCssUrl ? "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.css",
  maplibreJsUrl ? "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.js",
}: let
  normalizedPath =
    if maptilesPath == ""
    then "/maptiles"
    else if builtins.substring 0 1 maptilesPath == "/"
    then maptilesPath
    else "/${maptilesPath}";
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
          html, body { margin: 0; height: 100%; }
          #map { height: 100%; width: 100%; }
          .legend {
            position: absolute;
            right: 12px;
            top: 12px;
            z-index: 10;
            background: rgba(255, 255, 255, 0.9);
            border: 1px solid #d4dce8;
            border-radius: 8px;
            padding: 10px 12px;
            font: 12px/1.3 ui-sans-serif, system-ui, -apple-system, Segoe UI, sans-serif;
            color: #22324a;
          }
        </style>
      </head>
      <body>
        <div class="legend">
          <div><strong>Sample MapLibre Client</strong></div>
          <div>Source: landcover, water, boundary, place</div>
        </div>
        <div id="map"></div>

        <script src="${maplibreJsUrl}"></script>
        <script>
          const maptilesBaseUrl = window.location.origin + "${normalizedPath}";
          const maptilesUrlTemplate = maptilesBaseUrl + "/landcover,water,boundary,place/{z}/{x}/{y}";

          const map = new maplibregl.Map({
            container: "map",
            center: [10, 25],
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
                { id: "background", type: "background", paint: {"background-color": "#eaf0f5"} },
                { id: "landcover", type: "fill", source: "osm_tiles", "source-layer": "landcover", paint: {"fill-color": "#d6e6cd", "fill-opacity": 0.9} },
                { id: "water", type: "fill", source: "osm_tiles", "source-layer": "water", paint: {"fill-color": "#9fc2ec", "fill-opacity": 0.95} },
                { id: "boundary", type: "line", source: "osm_tiles", "source-layer": "boundary", paint: {"line-color": "#6e7f95", "line-width": ["interpolate", ["linear"], ["zoom"], 1, 0.5, 5, 1.2]} },
                {
                  id: "place",
                  type: "symbol",
                  source: "osm_tiles",
                  "source-layer": "place",
                  layout: {
                    "text-field": ["coalesce", ["get", "name_en"], ["get", "name"]],
                    "text-size": ["interpolate", ["linear"], ["zoom"], 2, 10, 8, 14]
                  },
                  paint: {"text-color": "#213042", "text-halo-color": "#f3f6fb", "text-halo-width": 1}
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
