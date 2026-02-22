{
  pkgs,
  title ? "OSM Tiles Demo",
  maptilesPath ? "/maptiles",
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
        <link rel="stylesheet" href="https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.css" />
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
          <div>Layers: landcover, water, boundary, place</div>
        </div>
        <div id="map"></div>

        <script src="https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.js"></script>
        <script>
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
                  tiles: ["${normalizedPath}/landcover,water,boundary,place/{z}/{x}/{y}"],
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
                  type: "circle",
                  source: "osm_tiles",
                  "source-layer": "place",
                  paint: {
                    "circle-color": "#2d6cdf",
                    "circle-radius": ["interpolate", ["linear"], ["zoom"], 1, 1.5, 5, 4],
                    "circle-opacity": 0.9
                  }
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
