{
  lib,
  pkgs,
  locales ? ["en"],
  countries ? [],
  ramMB ? 4096,
  geofabrikBaseUrl ? "https://download.geofabrik.de",
  maplibreCssUrl ? "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.css",
  maplibreJsUrl ? "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.js",
}:
assert lib.assertMsg (locales != []) "osm-tiles-demo: `locales` must not be empty.";
assert lib.assertMsg (builtins.all builtins.isString locales) "osm-tiles-demo: `locales` must be a list of strings.";
assert lib.assertMsg (builtins.all builtins.isString countries) "osm-tiles-demo: `countries` must be a list of Geofabrik path strings (for example `europe/germany`).";
assert lib.assertMsg (builtins.isInt ramMB && ramMB > 0) "osm-tiles-demo: `ramMB` must be a positive integer.";
assert lib.assertMsg pkgs.stdenv.hostPlatform.isLinux ''
  osm-tiles-demo builds a Linux Docker image and must be evaluated on a Linux target system.
  On macOS, build with a Linux builder (for example: `nix build --system aarch64-linux .#osm-tiles-demo`).
''; let
  postgresTuning = import ../../modules/osm-tiles/generators/mk-postgres-tuning.nix {
    inherit lib ramMB;
  };
  postgresArgs = lib.concatStringsSep " " (
    lib.mapAttrsToList (key: value: "-c ${key}=${lib.escapeShellArg value}") postgresTuning.settings
  );

  sanitizeUnit = name:
    lib.replaceStrings ["/" " " "." "_"] ["-" "-" "-" "-"] name;

  normalizeUrl = url:
    if lib.hasSuffix "/" url
    then lib.removeSuffix "/" url
    else url;

  geofabrikBase = normalizeUrl geofabrikBaseUrl;

  countrySpecs =
    map (path: {
      geofabrikPath = path;
      unitName = sanitizeUnit path;
      pbfUrl = "${geofabrikBase}/${path}-latest.osm.pbf";
      replicationUrl = "${geofabrikBase}/${path}-updates";
    })
    countries;

  openmaptilesSource = pkgs.fetchgit {
    url = "https://github.com/openmaptiles/openmaptiles.git";
    rev = "672980fcd3b0b2c499a3aa3e9ce576af29ce2f15";
    hash = "sha256-O1cYB8q9ZWPLF9p/Klvxy4go025U4QvFO/ySAFjtER8=";
  };

  openmaptilesTools = pkgs.callPackage ../openmaptiles-tools {};

  tilesetYaml = pkgs.writeText "osm-tiles-demo-openmaptiles.yaml" (
    import ../../modules/osm-tiles/generators/mk-openmaptiles-tileset.nix {
      inherit
        lib
        locales
        ;
    }
  );

  artifacts =
    pkgs.runCommand "osm-tiles-demo-openmaptiles-artifacts" {
      nativeBuildInputs = [
        openmaptilesTools
        pkgs.coreutils
        pkgs.findutils
      ];
    } ''
      set -euo pipefail

      mkdir -p "$out/sql"
      cp ${tilesetYaml} "$out/tileset.yaml"
      ln -s ${openmaptilesSource}/layers "$out/layers"

      generate-imposm3 "$out/tileset.yaml" > "$out/mapping.yaml"
      generate-sql "$out/tileset.yaml" --dir "$out/sql"

      generate-sqltomvt "$out/tileset.yaml" --layer landcover --function --fname landcover_zxy >> "$out/sql/run_last.sql"
      generate-sqltomvt "$out/tileset.yaml" --layer water --function --fname water_zxy >> "$out/sql/run_last.sql"
      generate-sqltomvt "$out/tileset.yaml" --layer boundary --function --fname boundary_zxy >> "$out/sql/run_last.sql"
      generate-sqltomvt "$out/tileset.yaml" --layer place --function --fname place_zxy >> "$out/sql/run_last.sql"
    '';

  postgres =
    if pkgs ? postgresql_18
    then pkgs.postgresql_18.withPackages (ps: [ps.postgis])
    else pkgs.postgresql.withPackages (ps: [ps.postgis]);

  martin = pkgs.callPackage ../martin {};

  martinConfig = pkgs.writeText "osm-tiles-demo-martin.yaml" (
    import ../../modules/osm-tiles/generators/mk-martin-yaml.nix {
      inherit lib;
      routePrefix = "/maptiles";
      connectionString = "postgresql://osm_maps@127.0.0.1:5432/osm_maps?sslmode=disable";
      poolSize = 20;
      workerProcesses = 2;
      schema = "public";
    }
  );

  sampleClient = import ../../modules/osm-tiles/generators/mk-sample-client.nix {
    inherit
      pkgs
      maplibreCssUrl
      maplibreJsUrl
      ;
    title = "OSM Tiles Docker Demo";
    maptilesPath = "/maptiles";
  };

  countryImportSnippet =
    lib.concatMapStringsSep "\n" (country: ''
      import_country ${lib.escapeShellArg country.unitName} ${lib.escapeShellArg country.pbfUrl} ${lib.escapeShellArg country.replicationUrl}
    '')
    countrySpecs;

  nginxConf = pkgs.writeText "osm-tiles-demo-nginx.conf" ''
    worker_processes 1;
    pid /tmp/nginx.pid;
    error_log /dev/stderr notice;

    events {
      worker_connections 1024;
    }

    http {
      include ${pkgs.nginx}/conf/mime.types;
      default_type application/octet-stream;

      access_log /dev/stdout;
      error_log /dev/stderr notice;

      sendfile on;
      tcp_nopush on;
      tcp_nodelay on;

      client_body_temp_path /tmp/nginx-client;
      proxy_temp_path /tmp/nginx-proxy;
      fastcgi_temp_path /tmp/nginx-fastcgi;
      uwsgi_temp_path /tmp/nginx-uwsgi;
      scgi_temp_path /tmp/nginx-scgi;

      proxy_cache_path /data/cache/nginx levels=1:2 keys_zone=osm_tiles_cache:64m max_size=1g inactive=30d use_temp_path=off;

      server {
        listen 0.0.0.0:8080;
        server_name _;

        location = /maptiles {
          return 400;
        }

        location = /maptiles/ {
          return 400;
        }

        location ^~ /maptiles/ {
          proxy_pass http://127.0.0.1:3000;

          proxy_cache osm_tiles_cache;
          proxy_cache_key "$scheme|$host|$request_uri";
          proxy_cache_methods GET HEAD;
          proxy_cache_valid 200 206 30d;
          proxy_cache_lock on;
          proxy_cache_background_update on;
          proxy_cache_use_stale updating error timeout http_500 http_502 http_503 http_504;

          proxy_read_timeout 2m;
          proxy_send_timeout 2m;

          add_header Access-Control-Allow-Origin "*" always;
          add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
          add_header Access-Control-Allow-Headers "Origin, Accept, Range, Content-Type" always;
          add_header Access-Control-Max-Age "86400" always;

          if ($request_method = OPTIONS) { return 204; }
        }

        location / {
          root ${sampleClient};
          index index.html;
          try_files $uri $uri/ /index.html;
        }
      }
    }
  '';

  entrypoint = pkgs.writeShellScript "osm-tiles-demo-entrypoint" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    export PATH=${lib.makeBinPath [
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.unzip
      pkgs.imposm
      pkgs.osmium-tool
      postgres
      pkgs.gdal
      martin
      pkgs.nginx
      openmaptilesTools
    ]}
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    OSM_TILES_DATA_DIR="''${OSM_TILES_DATA_DIR:-/data}"
    PGDATA="''${OSM_TILES_PGDATA:-$OSM_TILES_DATA_DIR/postgres}"
    PG_SOCKET_DIR="''${OSM_TILES_PG_SOCKET_DIR:-/tmp/pgsocket}"
    PGPORT="''${OSM_TILES_PGPORT:-5432}"
    PGHOST="127.0.0.1"
    export PGDATA PGHOST PGPORT

    mkdir -p \
      "$OSM_TILES_DATA_DIR" \
      "$OSM_TILES_DATA_DIR/cache/nginx" \
      "$OSM_TILES_DATA_DIR/external" \
      "$OSM_TILES_DATA_DIR/imposm/cache" \
      "$OSM_TILES_DATA_DIR/imposm/diff" \
      "$OSM_TILES_DATA_DIR/imposm/expire" \
      "$OSM_TILES_DATA_DIR/imposm/config" \
      "$OSM_TILES_DATA_DIR/pbf" \
      "$PGDATA" \
      "$PG_SOCKET_DIR" \
      /tmp/nginx-client \
      /tmp/nginx-proxy \
      /tmp/nginx-fastcgi \
      /tmp/nginx-uwsgi \
      /tmp/nginx-scgi

    chmod 700 "$PGDATA"

    if [ ! -s "$PGDATA/PG_VERSION" ]; then
      initdb -D "$PGDATA" --auth=trust --username=postgres --encoding=UTF8 --locale=C
    fi

    pg_ctl -D "$PGDATA" -o "-c listen_addresses='127.0.0.1' -c port=$PGPORT -c unix_socket_directories='$PG_SOCKET_DIR' ${postgresArgs}" -w start

    cleanup() {
      if [ -n "''${nginx_pid:-}" ] && kill -0 "$nginx_pid" 2>/dev/null; then
        kill "$nginx_pid" 2>/dev/null || true
      fi
      if [ -n "''${martin_pid:-}" ] && kill -0 "$martin_pid" 2>/dev/null; then
        kill "$martin_pid" 2>/dev/null || true
      fi
      pg_ctl -D "$PGDATA" -m fast stop >/dev/null 2>&1 || true
    }
    trap cleanup EXIT INT TERM

    psql -v ON_ERROR_STOP=1 -U postgres -d postgres -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'osm_maps') THEN CREATE ROLE osm_maps LOGIN; END IF; END \$\$;"

    if [ "$(psql -X -A -t -U postgres -d postgres -c "SELECT 1 FROM pg_database WHERE datname = 'osm_maps'")" != "1" ]; then
      createdb -U postgres -O osm_maps --encoding=UTF8 --locale=C --template=template0 osm_maps
    fi

    psql -v ON_ERROR_STOP=1 -U postgres -d osm_maps -c "CREATE EXTENSION IF NOT EXISTS postgis;"
    psql -v ON_ERROR_STOP=1 -U postgres -d osm_maps -c "CREATE EXTENSION IF NOT EXISTS hstore;"
    psql -v ON_ERROR_STOP=1 -U postgres -d osm_maps -c "GRANT CONNECT, TEMP ON DATABASE osm_maps TO osm_maps;"

    export POSTGRES_HOST=127.0.0.1
    export POSTGRES_PORT="$PGPORT"
    export POSTGRES_DB=osm_maps
    export POSTGRES_USER=osm_maps
    export POSTGRES_PASSWORD=x
    export IMPOSM_MAPPING_FILE=${lib.escapeShellArg "${artifacts}/mapping.yaml"}
    export SQL_TOOLS_DIR=${lib.escapeShellArg "${openmaptilesTools}/sql"}

    write_cfg() {
      local unit="$1"
      local repl_url="$2"
      local out="$OSM_TILES_DATA_DIR/imposm/config/$unit.json"
      local norm="$repl_url"
      norm="''${norm%/}"
      printf '{\n  "replication_url": "%s/",\n  "replication_interval": "1m"\n}\n' "$norm" > "$out"
      echo "$out"
    }

    import_external() {
      if [ "''${OSM_TILES_SKIP_EXTERNAL_IMPORT:-0}" = "1" ]; then
        return
      fi

      if [ -f "$OSM_TILES_DATA_DIR/.external-imported" ]; then
        return
      fi

      ne_zip="$OSM_TILES_DATA_DIR/external/natural_earth_vector.sqlite_v5.1.2.zip"
      ne_sqlite="$OSM_TILES_DATA_DIR/external/natural_earth_vector.sqlite"

      curl --fail --location --retry 5 --output "$ne_zip.tmp" https://dev.maptiler.download/geodata/omt/natural_earth_vector.sqlite_v5.1.2.zip
      mv "$ne_zip.tmp" "$ne_zip"
      unzip -oj "$ne_zip" -d "$OSM_TILES_DATA_DIR/external"

      OGR_PG_ENABLE_METADATA=NO ogr2ogr \
        -f PostgreSQL \
        -s_srs EPSG:4326 \
        -t_srs EPSG:3857 \
        -clipsrc -180.1 -85.0511 180.1 85.0511 \
        "PG:dbname=osm_maps user=osm_maps host=127.0.0.1 port=$PGPORT password=x" \
        -lco GEOMETRY_NAME=geometry \
        -lco OVERWRITE=YES \
        -lco DIM=2 \
        -nlt GEOMETRY \
        -overwrite \
        "$ne_sqlite"

      water_zip="$OSM_TILES_DATA_DIR/external/water-polygons-split-3857.zip"
      curl --fail --location --retry 5 --output "$water_zip.tmp" http://osmdata.openstreetmap.de/download/water-polygons-split-3857.zip
      mv "$water_zip.tmp" "$water_zip"
      unzip -oj "$water_zip" -d "$OSM_TILES_DATA_DIR/external"

      OGR_PG_ENABLE_METADATA=NO ogr2ogr \
        -f PostgreSQL \
        -s_srs EPSG:3857 \
        -t_srs EPSG:3857 \
        -lco OVERWRITE=YES \
        -lco GEOMETRY_NAME=geometry \
        -overwrite \
        -nln "osm_ocean_polygon" \
        -nlt geometry \
        --config PG_USE_COPY YES \
        "PG:dbname=osm_maps user=osm_maps host=127.0.0.1 port=$PGPORT password=x" \
        "$OSM_TILES_DATA_DIR/external/water_polygons.shp"

      touch "$OSM_TILES_DATA_DIR/.external-imported"
    }

    run_import() {
      local unit="$1"
      local repl_url="$2"
      local pbf_file="$3"
      local append="$4"
      export IMPOSM_CONFIG_FILE="$(write_cfg "$unit" "$repl_url")"
      export IMPOSM_CACHE_DIR="$OSM_TILES_DATA_DIR/imposm/cache/$unit"
      export IMPOSM_DIFF_DIR="$OSM_TILES_DATA_DIR/imposm/diff/$unit"
      export EXPIRETILES_DIR="$OSM_TILES_DATA_DIR/imposm/expire/$unit"
      mkdir -p "$IMPOSM_CACHE_DIR" "$IMPOSM_DIFF_DIR" "$EXPIRETILES_DIR"
      if [ "$append" = "1" ]; then
        APPEND_MODE=true DIFF_MODE=true import-osm "$pbf_file"
      else
        APPEND_MODE=false DIFF_MODE=true import-osm "$pbf_file"
      fi
    }

    import_country() {
      local unit="$1"
      local pbf_url="$2"
      local repl_url="$3"
      local pbf_file="$OSM_TILES_DATA_DIR/pbf/$unit.osm.pbf"
      curl --fail --location --retry 5 --output "$pbf_file.tmp" "$pbf_url"
      mv "$pbf_file.tmp" "$pbf_file"

      if [ "''${append_mode:-0}" = "0" ]; then
        run_import "$unit" "$repl_url" "$pbf_file" 0
        append_mode=1
      else
        run_import "$unit" "$repl_url" "$pbf_file" 1
      fi
    }

    import_osm_data() {
      if [ "''${OSM_TILES_SKIP_OSM_IMPORT:-0}" = "1" ]; then
        return
      fi

      if [ -f "$OSM_TILES_DATA_DIR/.osm-imported" ]; then
        return
      fi

      append_mode=0
      ${lib.optionalString (countrySpecs != []) countryImportSnippet}

      if [ ${toString (builtins.length countrySpecs)} -eq 0 ]; then
        printf "%s\n" "<?xml version='1.0' encoding='UTF-8'?>" "<osm version='0.6' generator='osm-tiles'/>" > "$OSM_TILES_DATA_DIR/pbf/empty.osm"
        osmium cat "$OSM_TILES_DATA_DIR/pbf/empty.osm" -o "$OSM_TILES_DATA_DIR/pbf/empty.osm.pbf"
        run_import "ne-only" "http://planet.openstreetmap.org/replication/day/" "$OSM_TILES_DATA_DIR/pbf/empty.osm.pbf" 0
      fi

      touch "$OSM_TILES_DATA_DIR/.osm-imported"
    }

    import_sql_views() {
      if [ -f "$OSM_TILES_DATA_DIR/.sql-imported" ]; then
        return
      fi

      psql -h 127.0.0.1 -p "$PGPORT" -U osm_maps -d osm_maps <<'SQL'
      CREATE OR REPLACE FUNCTION osml10n_get_name_without_brackets_from_tags(
        tags hstore,
        lang text,
        geometry geometry
      ) RETURNS text AS $$
        SELECT NULLIF(
          regexp_replace(
            COALESCE(tags -> ('name:' || lang), tags -> 'name'),
            '\s*[\(\[].*?[\)\]]\s*',
            ' ',
            'g'
          ),
          left('x', 0)
        );
      $$ LANGUAGE SQL IMMUTABLE;
      SQL

      export SQL_DIR=${lib.escapeShellArg "${artifacts}/sql"}
      import-sql
      export PGHOST=127.0.0.1
      export PGPORT="$PGPORT"
      export PGDATABASE=osm_maps
      export PGUSER=osm_maps
      export PGPASSWORD=x
      refresh-views --schema public
      touch "$OSM_TILES_DATA_DIR/.sql-imported"
    }

    import_external
    import_osm_data
    import_sql_views

    ${martin}/bin/martin --config ${martinConfig} --listen-addresses 127.0.0.1:3000 &
    martin_pid=$!

    ${pkgs.nginx}/bin/nginx -c ${nginxConf} -g 'daemon off;' &
    nginx_pid=$!

    wait -n "$martin_pid" "$nginx_pid"
  '';
in
  pkgs.dockerTools.buildLayeredImage {
    name = "osm-tiles-demo";
    tag = "latest";

    contents = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.findutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.unzip
      pkgs.cacert
      pkgs.gdal
      pkgs.imposm
      pkgs.osmium-tool
      postgres
      martin
      pkgs.nginx
      openmaptilesTools
      pkgs.fakeNss
    ];

    extraCommands = ''
      mkdir -p tmp data data/cache/nginx
      chmod 1777 tmp
      chmod 0777 data data/cache data/cache/nginx
    '';

    config = {
      Cmd = ["${entrypoint}"];
      ExposedPorts = {
        "8080/tcp" = {};
      };
      WorkingDir = "/";
      Volumes = {
        "/data" = {};
      };
      User = "65534:65534";
      Env = [
        "OSM_TILES_DATA_DIR=/data"
        "OSM_TILES_PGDATA=/data/postgres"
        "OSM_TILES_PG_SOCKET_DIR=/tmp/pgsocket"
      ];
    };
  }
