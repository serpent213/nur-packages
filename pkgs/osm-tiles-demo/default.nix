{
  lib,
  pkgs,
  locales ? ["en"],
  countries ? [],
  ramMB ? 4096,
  geofabrikBaseUrl ? "https://download.geofabrik.de",
  osm2pgsqlImportCacheMB ? 4096,
  osm2pgsqlImportProcesses ? 4,
  servingProfile ? "openmaptiles",
  maplibreCssUrl ? "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.css",
  maplibreJsUrl ? "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.js",
}:
assert lib.assertMsg (locales != []) "osm-tiles-demo: `locales` must not be empty.";
assert lib.assertMsg (builtins.all builtins.isString locales) "osm-tiles-demo: `locales` must be a list of strings.";
assert lib.assertMsg (builtins.all builtins.isString countries) "osm-tiles-demo: `countries` must be a list of Geofabrik path strings (for example `europe/germany`).";
assert lib.assertMsg (builtins.isInt ramMB && ramMB > 0) "osm-tiles-demo: `ramMB` must be a positive integer.";
assert lib.assertMsg (builtins.elem servingProfile ["openmaptiles" "compact"]) "osm-tiles-demo: `servingProfile` must be `openmaptiles` or `compact`.";
assert lib.assertMsg pkgs.stdenv.hostPlatform.isLinux ''
  osm-tiles-demo builds a Linux Docker image and must be evaluated on a Linux target system.
  On macOS, build with a Linux builder (for example: `nix build --system aarch64-linux .#osm-tiles-demo`).
''; let
  div = a: b: builtins.floor (a / b);

  sharedBuffersMB = lib.max 256 ramMB;
  effectiveCacheMB = lib.max 512 (sharedBuffersMB * 2);
  maintenanceWorkMemMB = lib.max 256 (div ramMB 8);
  autovacuumWorkMemMB = lib.max 128 (div ramMB 16);
  workMemMB = lib.max 8 (div ramMB 256);

  toMB = mb: "${toString mb}MB";

  sanitizeSchema = name:
    lib.replaceStrings ["/" " " "." "-"] ["_" "_" "_" "_"] name;

  geofabrikBase =
    if lib.hasSuffix "/" geofabrikBaseUrl
    then lib.removeSuffix "/" geofabrikBaseUrl
    else geofabrikBaseUrl;

  countrySpecs =
    map (path: {
      geofabrikPath = path;
      schema = "osm_${sanitizeSchema path}";
      pbfUrl = "${geofabrikBase}/${path}-latest.osm.pbf";
    })
    countries;

  countrySchemas = map (country: country.schema) countrySpecs;

  analyzeTables =
    if servingProfile == "openmaptiles"
    then [
      "landcover"
      "landuse"
      "park"
      "water"
      "waterway"
      "boundary"
      "transportation"
      "aeroway"
      "transportation_name"
      "building"
      "water_name"
      "place"
    ]
    else [
      "landcover"
      "water"
      "boundary"
      "place"
    ];

  postgres =
    if pkgs ? postgresql_18
    then pkgs.postgresql_18.withPackages (ps: [ps.postgis])
    else pkgs.postgresql.withPackages (ps: [ps.postgis]);

  martin = pkgs.callPackage ../martin {};

  preSetupSql = pkgs.writeText "osm-tiles-demo-pre-setup.sql" (
    import ../../modules/osm-tiles/generators/mk-serving-setup-sql.nix {
      inherit lib;
      locales = locales;
      countrySchemas = [];
      dbUser = "osm_maps";
      servingSchema = "osm_serving";
      lowresSchema = "osm_lowres";
      profile = servingProfile;
    }
  );

  setupSql = pkgs.writeText "osm-tiles-demo-setup.sql" (
    import ../../modules/osm-tiles/generators/mk-serving-setup-sql.nix {
      inherit lib;
      locales = locales;
      countrySchemas = countrySchemas;
      dbUser = "osm_maps";
      servingSchema = "osm_serving";
      lowresSchema = "osm_lowres";
      profile = servingProfile;
    }
  );

  refreshSql = pkgs.writeText "osm-tiles-demo-refresh.sql" (
    import ../../modules/osm-tiles/generators/mk-serving-refresh-sql.nix {
      inherit lib;
      servingSchema = "osm_serving";
      profile = servingProfile;
    }
  );

  flexStyle = import ../../modules/osm-tiles/generators/mk-flex-lua.nix {
    inherit
      lib
      pkgs
      ;
    locales = locales;
    profile = servingProfile;
  };

  martinConfig = pkgs.writeText "osm-tiles-demo-martin.yaml" (
    import ../../modules/osm-tiles/generators/mk-martin-yaml.nix {
      inherit lib;
      routePrefix = "/maptiles";
      connectionString = "postgresql://osm_maps@/osm_maps?host=/tmp/pgsocket&port=5432&sslmode=disable";
      poolSize = 20;
      workerProcesses = 2;
      servingSchema = "osm_serving";
      profile = servingProfile;
    }
  );

  sampleClient = import ../../modules/osm-tiles/generators/mk-sample-client.nix {
    inherit pkgs;
    title = "OSM Tiles Docker Demo";
    maptilesPath = "/maptiles";
    servingProfile = servingProfile;
    maplibreCssUrl = maplibreCssUrl;
    maplibreJsUrl = maplibreJsUrl;
  };

  countryImportScript =
    lib.concatMapStringsSep "\n" (country: ''
      echo "Ensuring country import: ${country.geofabrikPath} -> ${country.schema}"

      has_landcover="$(${postgres}/bin/psql -X -A -t -U osm_maps -d osm_maps -c "SELECT to_regclass('${country.schema}.landcover') IS NOT NULL")"
      if [ "$has_landcover" = "t" ]; then
        echo "Country ${country.geofabrikPath} already imported."
      else
        ${postgres}/bin/psql -v ON_ERROR_STOP=1 -U osm_maps -d osm_maps \
          -c "CREATE SCHEMA IF NOT EXISTS \"${country.schema}\" AUTHORIZATION osm_maps"

        pbf_file="$(mktemp -p "$OSM_TILES_DATA_DIR" "country-${sanitizeSchema country.geofabrikPath}.XXXXXX.osm.pbf")"
        curl --fail --location --retry 5 --output "$pbf_file.tmp" ${lib.escapeShellArg country.pbfUrl}
        mv "$pbf_file.tmp" "$pbf_file"

        ${pkgs.osm2pgsql}/bin/osm2pgsql \
          --create \
          --slim \
          --output=flex \
          --style "$OSM_TILES_DATA_DIR/map-style.lua" \
          --cache "$OSM_TILES_IMPORT_CACHE_MB" \
          --number-processes "$OSM_TILES_IMPORT_PROCESSES" \
          --database osm_maps \
          --username osm_maps \
          --host "$PG_SOCKET_DIR" \
          --port "$PGPORT" \
          --schema ${lib.escapeShellArg country.schema} \
          "$pbf_file"

        rm -f "$pbf_file"
        for table in ${lib.concatStringsSep " " (map lib.escapeShellArg analyzeTables)}; do
          has_table="$(${postgres}/bin/psql -X -A -t -U osm_maps -d osm_maps -c "SELECT to_regclass('${country.schema}.' || quote_ident('$table')) IS NOT NULL")"
          if [ "$has_table" = "t" ]; then
            ${postgres}/bin/psql -v ON_ERROR_STOP=1 -U osm_maps -d osm_maps -c "ANALYZE ${country.schema}.\"$table\""
          fi
        done
      fi
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
      postgres
      pkgs.gdal
      martin
      pkgs.nginx
      pkgs.osm2pgsql
    ]}
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    OSM_TILES_DATA_DIR="''${OSM_TILES_DATA_DIR:-/data}"
    PGDATA="''${OSM_TILES_PGDATA:-$OSM_TILES_DATA_DIR/postgres}"
    PG_SOCKET_DIR="''${OSM_TILES_PG_SOCKET_DIR:-/tmp/pgsocket}"
    PGPORT="''${OSM_TILES_PGPORT:-5432}"
    OSM_TILES_IMPORT_CACHE_MB="''${OSM_TILES_IMPORT_CACHE_MB:-${toString osm2pgsqlImportCacheMB}}"
    OSM_TILES_IMPORT_PROCESSES="''${OSM_TILES_IMPORT_PROCESSES:-${toString osm2pgsqlImportProcesses}}"
    PGHOST="$PG_SOCKET_DIR"
    export PGDATA PGHOST PGPORT

    if [ ! -w "$OSM_TILES_DATA_DIR" ]; then
      echo "Data dir $OSM_TILES_DATA_DIR is not writable."
      echo "If you mounted a volume, ensure it is writable by container uid 65534."
      exit 1
    fi

    mkdir -p \
      "$OSM_TILES_DATA_DIR" \
      "$OSM_TILES_DATA_DIR/cache/nginx" \
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

    pg_ctl -D "$PGDATA" -o "-c listen_addresses='127.0.0.1' -c port=$PGPORT -c unix_socket_directories='$PG_SOCKET_DIR' -c jit=off -c shared_buffers=${toMB sharedBuffersMB} -c effective_cache_size=${toMB effectiveCacheMB} -c work_mem=${toMB workMemMB} -c maintenance_work_mem=${toMB maintenanceWorkMemMB} -c autovacuum_work_mem=${toMB autovacuumWorkMemMB} -c wal_buffers=16MB -c wal_compression=on -c min_wal_size=512MB -c max_wal_size=4GB -c checkpoint_timeout=15min -c checkpoint_completion_target=0.9 -c random_page_cost=1.3 -c effective_io_concurrency=64" -w start

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

    psql -v ON_ERROR_STOP=1 -U postgres -d postgres <<'SQL'
      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'osm_maps') THEN
          CREATE ROLE osm_maps LOGIN;
        END IF;
      END
      $$;
    SQL

    if [ "$(psql -X -A -t -U postgres -d postgres -c "SELECT 1 FROM pg_database WHERE datname = 'osm_maps'")" != "1" ]; then
      createdb -U postgres -O osm_maps --encoding=UTF8 --locale=C --template=template0 osm_maps
    fi

    db_encoding="$(psql -X -A -t -U postgres -d postgres -c "SELECT pg_encoding_to_char(encoding) FROM pg_database WHERE datname = 'osm_maps'")"
    if [ "$db_encoding" != "UTF8" ]; then
      echo "Database encoding for osm_maps is '$db_encoding', but osm2pgsql requires UTF8."
      echo "If you use persisted data, remove or migrate OSM_TILES_PGDATA and restart."
      exit 1
    fi

    psql -v ON_ERROR_STOP=1 -U postgres -d osm_maps <<'SQL'
      CREATE EXTENSION IF NOT EXISTS postgis;
      CREATE EXTENSION IF NOT EXISTS hstore;
      GRANT CONNECT, TEMP ON DATABASE osm_maps TO osm_maps;
    SQL

    # Optional OSM import stub so users can mount and run manual country import later.
    ln -sf ${flexStyle} "$OSM_TILES_DATA_DIR/map-style.lua"

    ${postgres}/bin/psql -v ON_ERROR_STOP=1 -U osm_maps -d osm_maps -f ${preSetupSql}

    NE_MARKER="$OSM_TILES_DATA_DIR/.ne_imported"
    if [ "''${OSM_TILES_SKIP_NE_DOWNLOAD:-0}" != "1" ] && [ ! -f "$NE_MARKER" ]; then
      tmp_dir="$(mktemp -d)"
      cleanup_tmp() {
        rm -rf "$tmp_dir"
      }
      trap 'cleanup_tmp; cleanup' EXIT INT TERM

      import_dataset() {
        local url="$1"
        local table="$2"

        echo "Importing Natural Earth dataset: $table"
        local zip_file="$tmp_dir/$table.zip"
        local unzip_dir="$tmp_dir/$table"

        curl --fail --location --retry 5 --output "$zip_file.tmp" "$url"
        mv "$zip_file.tmp" "$zip_file"
        mkdir -p "$unzip_dir"
        unzip -q "$zip_file" -d "$unzip_dir"

        local shp_file
        shp_file="$(find "$unzip_dir" -type f -name '*.shp' | head -n1 || true)"
        if [ -z "$shp_file" ]; then
          echo "No shapefile found in $zip_file"
          return 1
        fi

        OGR_PG_ENABLE_METADATA=NO ogr2ogr \
          -makevalid \
          -f PostgreSQL \
          "PG:dbname=osm_maps user=osm_maps host=$PG_SOCKET_DIR port=$PGPORT" \
          "$shp_file" \
          -overwrite \
          -nlt PROMOTE_TO_MULTI \
          -nln "osm_lowres.$table" \
          -lco GEOMETRY_NAME=geom \
          -lco FID=id \
          -lco PRECISION=NO \
          -lco SPATIAL_INDEX=GIST

        psql -v ON_ERROR_STOP=1 -U osm_maps -d osm_maps -c "ANALYZE osm_lowres.$table"
      }

      import_dataset "https://naciscdn.org/naturalearth/110m/physical/ne_110m_land.zip" "lowres_landcover"
      import_dataset "https://naciscdn.org/naturalearth/110m/physical/ne_110m_ocean.zip" "lowres_ocean"
      import_dataset "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip" "lowres_boundary"
      import_dataset "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_populated_places_simple.zip" "lowres_place"

      touch "$NE_MARKER"

      trap cleanup EXIT INT TERM
      cleanup_tmp
    fi

    ${lib.optionalString (countrySpecs != []) ''
      if [ "''${OSM_TILES_SKIP_COUNTRY_IMPORT:-0}" != "1" ]; then
        ${countryImportScript}
      fi
    ''}

    if [ "''${OSM_TILES_SKIP_COUNTRY_IMPORT:-0}" = "1" ] && [ "${toString (countrySpecs != [])}" = "true" ]; then
      psql -v ON_ERROR_STOP=1 -U osm_maps -d osm_maps -f ${preSetupSql}
    else
      psql -v ON_ERROR_STOP=1 -U osm_maps -d osm_maps -f ${setupSql}
    fi
    psql -v ON_ERROR_STOP=1 -U osm_maps -d osm_maps -f ${refreshSql}

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
      pkgs.osm2pgsql
      postgres
      martin
      pkgs.nginx
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
