# MapLibre Vector Tile Styling Landscape

## The Core Concept

A MapLibre "style" is a single JSON document that defines **both** where data comes from (sources / tile endpoints) and how it looks (paint/layout rules for each layer). To render a map, you point MapLibre GL JS at a `style.json` URL — that's it. Changing the style is how you "theme" the map.[1][2]

The data inside vector tiles is organized according to a **schema** — a contract defining which layers exist (`water`, `road`, `building`, …) and what attributes they carry (`class`, `name`, `subclass`, …). A style is written *against* a specific schema. If two tile servers produce tiles with the same schema, the same style works on both.[3][1]

## Tile Schemas: The Three Main Options

| | **OpenMapTiles (OMT)** | **Shortbread** | **Protomaps** |
|---|---|---|---|
| **Maintainer** | MapTiler / community[4] | Geofabrik[5] | Protomaps project[6] |
| **License (schema)** | CC-BY 4.0[7] | CC0 (public domain)[7][8] | BSD-3 (code), ODbL (tiles)[6] |
| **Design goal** | Feature-rich general-purpose[9] | Lean, minimal, general-purpose[10] | Google-Maps-like completeness[11] |
| **Layer count** | ~14 thematic layers | ~20 fine-grained layers[12] | Few compacted "theme" layers[11] |
| **Ecosystem maturity** | Largest — most existing styles[13] | Growing — now on osm.org vector layer[14] | Newer — tight coupling to one style set[11] |
| **Tile generators** | OpenMapTiles toolchain, Planetiler, Tilemaker | Tilemaker, Planetiler | Planetiler (custom profile)[6] |
| **Container** | MBTiles, PMTiles | MBTiles, PMTiles, VersaTiles[15] | PMTiles (primary)[16] |

### What "OpenMapTiles style" means

When people say "I want an OpenMapTiles style," they mean a `style.json` whose layer references (like `source-layer: "transportation"`, `class: "motorway"`) match the **OpenMapTiles schema**. Any tile server that outputs OMT-schema tiles — whether it's MapTiler Cloud, a self-hosted tileserver-gl, or tiles from OpenFreeMap — can be used as the source for that style.[9][1][3]

### Shortbread

Developed by Geofabrik and published under CC0, Shortbread aims to be a clean, minimal schema without the attribution requirement of OMT's CC-BY license. It's now used by the **VersaTiles** project and was recently adopted as the vector tile layer on **osm.org** itself. Fewer pre-made styles exist for it, but that's changing.[7][14][10]

### Protomaps

Protomaps takes a different approach: its own schema is tightly coupled to its own style, shipping 5 color themes (light, dark, white, grayscale, black) from a single TypeScript style generator. The schema intentionally compacts layers to solve cross-feature ordering inside the style. Think of it as an opinionated all-in-one package rather than a mix-and-match ecosystem.[11][6]

## Pre-Made Styles Worth Knowing

| Style | Look | Schema | Self-hostable? | Notes |
|-------|------|--------|---------------|-------|
| **OSM Liberty** | Clean, daily-driver | OMT | Yes — swap tile source[17] | Fork of OSM Bright, actively maintained[17] |
| **Positron / Dark Matter** | Light / dark minimal | OMT | Yes, but CARTO-coupled by default[13] | Retarget sources for self-hosting |
| **OSM Bright** | Colorful, OSM-carto-inspired | OMT | Yes[13] | Good starting point for custom work |
| **Protomaps Light** | Google-Maps-like | Protomaps | Yes — serve PMTiles[6] | Closest to "default Google" look out-of-the-box[11] |
| **VersaTiles Colorful** | General purpose | Shortbread | Yes[14] | Used on osm.org's vector layer[14] |

**For a "Google Maps-like" look that's easy to customize**: **Protomaps Light** is the closest match out of the box, with clean cartography and a familiar color palette. The trade-off is its own schema, so you can't easily swap in OMT tiles.[18][11]

If you want schema flexibility (use any OMT tile source), **OSM Liberty** is the best starting point — clean look, fully open, editable in Maputnik.[17][19]

## Editing & Tooling

**Maputnik** is the de-facto visual style editor for MapLibre styles. It's maintained under the MapLibre org and runs in the browser at `maplibre.org/maputnik/`. Load any `style.json`, tweak colors/fonts/filters visually, export the result. It's essentially the open-source equivalent of Mapbox Studio.[20][21][22]

For programmatic style generation, Protomaps generates styles from TypeScript, and the OpenStreetMap Americana project generates styles from JavaScript. This approach is powerful when you need dynamic theming (dark mode, brand colors) without maintaining raw JSON.[6][23]

## The MLT Format (Future)

The **MapLibre Tile (MLT)** specification was declared stable in October 2025. It's a next-gen replacement for the Mapbox Vector Tile (MVT) format, offering up to 6× better compression and 3× faster decoding through a column-oriented layout. MLT supports 3D coordinates, complex nested properties, and is designed for GPU-native rendering.[24][25]

MLT doesn't change the *style* layer — styles still reference layers and attributes the same way. What changes is the wire format of the tiles themselves. A JavaScript decoder exists (`@maplibre/mlt`), and conversion from MVT is possible in real-time via Planetiler. Adoption is early but progressing.[26][27]

## Practical Recommendations for Self-Hosting

For a backend engineer standing up a self-hosted map stack:

- **Quickest path**: Serve a Protomaps `planet.pmtiles` file from static storage (S3, Cloudflare R2, local nginx), use the `protomaps-themes-base` npm package to get a styled map in ~10 lines of code.[16][6][18]
- **Most flexible path**: Generate OMT-schema tiles (via Planetiler or tileserver-gl + MBTiles), pick any OMT-compatible style (OSM Liberty, Positron, etc.), edit freely in Maputnik.[3][17][20]
- **Lightest schema / no attribution hassle**: Use Shortbread-schema tiles (via Tilemaker or VersaTiles), apply a Shortbread-compatible style, benefit from CC0 licensing.[10][8]

In all cases, the pattern is the same: grab the `style.json`, rewrite the `sources` block to point at your tile server, and optionally rewrite `glyphs`/`sprite` URLs to your own hosted fonts and icons.[28][17]



Here's the landscape of OSM → vector tile tools:

## Two Fundamental Approaches

There are **offline/batch generators** (OSM PBF → tileset file) and **on-the-fly servers** (database → tiles at request time). For self-hosting, the batch approach dominates because it's simpler and faster to serve.

### Batch Generators (PBF → MBTiles/PMTiles)

| Tool | Language | Input | How it works | Notes |
|------|----------|-------|-------------|-------|
| **Planetiler** | Java | `.osm.pbf` | Streaming sort — reads OSM, maps to features, sorts by tile ID. Planet in ~5h on a single box [github](https://github.com/onthegomap/planetiler) | Supports OMT, Shortbread, Protomaps profiles. The go-to for planet-scale |
| **Tilemaker** | C++ | `.osm.pbf` | Similar direct approach, Lua scripting for filtering/transform. Lighter but slower than Planetiler at planet scale [github](https://github.com/systemed/tilemaker) | Used by osm.org for Shortbread tiles (via "Tilekiln" wrapper) [community.openstreetmap](https://community.openstreetmap.org/t/vector-tiles-are-deployed-on-openstreetmap-org/133008) |
| **Tippecanoe** | C++ | GeoJSON/FlatGeobuf/CSV | Not OSM-native — takes already-extracted geometry. Excels at density-aware simplification and drop strategies [github](https://github.com/felt/tippecanoe) | Great for overlays or custom datasets, not a full OSM→basemap pipeline |
| **OpenMapTiles Tools** | Python/Docker | `.osm.pbf` via **imposm3** → PostgreSQL | The "classic" heavy stack: import OSM into PostGIS with imposm3, run SQL transforms, generate tiles [github](https://github.com/openmaptiles/openmaptiles-tools) | Slower (days for planet), but powerful if you need custom SQL logic |

### On-the-Fly Servers (PostGIS → tiles per request)

| Tool | Language | Backend | Notes |
|------|----------|---------|-------|
| **Martin** | Rust | PostGIS, PMTiles, MBTiles | MapLibre project. Generates MVT from `ST_AsMVT()` or serves static tiles. Fast, versatile [github](https://github.com/RustWorks/martin-PostGIS-vector-tiles-server) |
| **Tegola** | Go | PostGIS, GeoPackage | Does its own geometry clipping/simplification, doesn't rely on PostGIS MVT functions [github](https://github.com/go-spatial/tegola) |
| **pg_tileserv** | Go | PostGIS | Thin wrapper around `ST_AsMVT()`. Minimal config — auto-discovers tables [dev](https://dev.to/mierune/comparing-postgis-backend-vectortile-servers-tegolamartinpgtileserv-5c6n) |

The on-the-fly approach is useful when your data changes frequently (minutes-level freshness) or you need custom queries, but it's harder on the database under load. [dev](https://dev.to/mierune/comparing-postgis-backend-vectortile-servers-tegolamartinpgtileserv-5c6n)

## The Typical Self-Hosting Stack

For most people wanting a static basemap, the pipeline looks like:

1. **Download** `.osm.pbf` from Geofabrik
2. **Generate** tiles with Planetiler or Tilemaker → outputs `.pmtiles` or `.mbtiles`
3. **Serve** the file via Martin, tileserver-gl, or even plain nginx (PMTiles supports HTTP range requests) [github](https://github.com/hyperknot/openfreemap)
4. **Style** with any compatible `style.json`

OpenFreeMap is a great reference implementation of exactly this: Planetiler + OMT schema + Btrfs file serving + weekly planet rebuilds. [blog.hyperknot](https://blog.hyperknot.com/p/openfreemap-survived-100000-requests)

## Zoom-Level Filtering

You asked specifically about the filtering/simplification — every tool handles this differently:

- **Planetiler**: Profile-defined Java/YAML rules decide what features appear at which zoom, with geometry simplification per zoom [github](https://github.com/onthegomap/planetiler)
- **Tilemaker**: Lua scripting — you write `node_function`/`way_function` and decide per-zoom inclusion and min-area thresholds [github](https://github.com/systemed/tilemaker)
- **Tippecanoe**: Automatic density-based dropping (`--drop-densest-as-needed`, `--coalesce-densest-as-needed`). Unique "keep the texture" philosophy [github](https://github.com/felt/tippecanoe)
- **OpenMapTiles Tools**: SQL-based — views/materialized views filter by zoom in PostgreSQL before tile generation [github](https://github.com/openmaptiles/openmaptiles-tools)

**For your use case** (self-hosted tile server, OMT or similar schema), Planetiler is the clear default — it's fast, actively maintained, and supports all three major schemas out of the box. Tilemaker is the lighter alternative if you prefer C++ and Lua over Java. [github](https://github.com/onthegomap/planetiler)
