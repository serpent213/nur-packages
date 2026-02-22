{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.osmTiles;

  sanitizeUnit = name:
    lib.replaceStrings ["/" " " "." "_"] ["-" "-" "-" "-"] name;

  sanitizeSchema = name:
    lib.replaceStrings ["/" " " "." "-"] ["_" "_" "_" "_"] name;

  normalizeUrl = url:
    if lib.hasSuffix "/" url
    then lib.removeSuffix "/" url
    else url;

  geofabrikBase = normalizeUrl cfg.source.geofabrikBaseUrl;

  enabledCountries = lib.mapAttrsToList (name: ccfg: ccfg // {inherit name;}) (
    lib.filterAttrs (_: ccfg: ccfg.enable) cfg.data.countries
  );

  countrySpecs = map (country: let
    geofabrikPath = country.geofabrikPath;
    pbfUrl =
      if country.pbfUrl != null
      then country.pbfUrl
      else "${geofabrikBase}/${geofabrikPath}-latest.osm.pbf";
    replicationUrl =
      if country.replicationUrl != null
      then country.replicationUrl
      else "${geofabrikBase}/${geofabrikPath}-updates";
  in
    country
    // {
      inherit
        geofabrikPath
        pbfUrl
        replicationUrl
        ;
      unitName = sanitizeUnit country.name;
    })
  enabledCountries;

  countriesWithUpdates =
    map (country: country // {unitName = sanitizeUnit country.name;})
    (lib.filter (country: country.updatesEnable) countrySpecs);

  countryCount = builtins.length countrySpecs;

  dbHost =
    if cfg.database.mode == "managed"
    then "127.0.0.1"
    else cfg.database.host;

  dbSocketDir = cfg.database.socketDir;

  psqlHostArgs =
    if dbSocketDir != null
    then ["-h" dbSocketDir]
    else if dbHost != null
    then ["-h" dbHost]
    else [];

  psqlArgsBase = [
    "-v"
    "ON_ERROR_STOP=1"
    "-U"
    cfg.database.user
    "-p"
    (toString cfg.database.port)
    "-d"
    cfg.database.name
  ];

  psqlUserArgs = psqlArgsBase ++ psqlHostArgs;

  adminPsqlArgs = dbName:
    [
      "-v"
      "ON_ERROR_STOP=1"
      "-U"
      cfg.database.adminUser
      "-p"
      (toString cfg.database.port)
      "-d"
      dbName
    ]
    ++ psqlHostArgs;

  div = a: b: builtins.floor (a / b);

  ramMB = cfg.database.managed.ramMB;
  sharedBuffersMB = lib.max 256 ramMB;
  effectiveCacheMB = lib.max 512 (sharedBuffersMB * 2);
  maintenanceWorkMemMB = lib.max 256 (div ramMB 8);
  autovacuumWorkMemMB = lib.max 128 (div ramMB 16);
  workMemMB = lib.max 8 (div ramMB 256);

  toMB = mb: "${toString mb}MB";

  managedPostgresqlSettings = {
    jit = "off";
    shared_buffers = toMB sharedBuffersMB;
    effective_cache_size = toMB effectiveCacheMB;
    work_mem = toMB workMemMB;
    maintenance_work_mem = toMB maintenanceWorkMemMB;
    autovacuum_work_mem = toMB autovacuumWorkMemMB;
    wal_buffers = "16MB";
    wal_compression = "on";
    min_wal_size = "512MB";
    max_wal_size = "4GB";
    checkpoint_timeout = "15min";
    checkpoint_completion_target = "0.9";
    random_page_cost = "1.3";
    effective_io_concurrency = "64";
  };

  postgresqlPackage =
    if config.services.postgresql.enable
    then config.services.postgresql.package
    else pkgs.postgresql;

  martinConnectionString =
    if cfg.database.connectionString != null
    then cfg.database.connectionString
    else if dbSocketDir != null
    then "postgresql://${cfg.database.user}@/${cfg.database.name}?host=${dbSocketDir}&port=${toString cfg.database.port}&sslmode=disable"
    else "postgresql://${cfg.database.user}@${dbHost}:${toString cfg.database.port}/${cfg.database.name}?sslmode=disable";

  openmaptilesTools = pkgs.callPackage ../../pkgs/openmaptiles-tools {};
  openmaptilesSource = pkgs.fetchgit {
    url = "https://github.com/openmaptiles/openmaptiles.git";
    rev = "672980fcd3b0b2c499a3aa3e9ce576af29ce2f15";
    hash = "sha256-O1cYB8q9ZWPLF9p/Klvxy4go025U4QvFO/ySAFjtER8=";
  };

  martinPackage = pkgs.callPackage ../../pkgs/martin {
    withWebUi = cfg.martin.withWebUi;
  };

  tilesetYaml = pkgs.writeText "osm-tiles-openmaptiles.yaml" (
    import ./generators/mk-openmaptiles-tileset.nix {
      inherit
        lib
        ;
      locales = cfg.data.locales;
    }
  );

  generatedArtifacts =
    pkgs.runCommand "osm-tiles-openmaptiles-artifacts" {
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

  martinConfigFile = pkgs.writeText "osm-tiles-martin.yaml" (
    import ./generators/mk-martin-yaml.nix {
      inherit lib;
      routePrefix = cfg.martin.routePrefix;
      connectionString = martinConnectionString;
      poolSize = cfg.martin.poolSize;
      workerProcesses = cfg.martin.workerProcesses;
      schema = cfg.serving.schema;
    }
  );

  sampleClientRoot = import ./generators/mk-sample-client.nix {
    inherit pkgs;
    title = cfg.sampleClient.title;
    maptilesPath = cfg.martin.routePrefix;
    maplibreCssUrl = cfg.sampleClient.maplibreCssUrl;
    maplibreJsUrl = cfg.sampleClient.maplibreJsUrl;
  };

  normalizePath = path: let
    withPrefix =
      if lib.hasPrefix "/" path
      then path
      else "/${path}";
  in
    if withPrefix != "/" && lib.hasSuffix "/" withPrefix
    then lib.removeSuffix "/" withPrefix
    else withPrefix;

  maptilesPath = normalizePath cfg.martin.routePrefix;
  maptilesPathWithSlash = "${maptilesPath}/";

  martinUpstream =
    if cfg.nginx.martinUpstream != null
    then cfg.nginx.martinUpstream
    else if cfg.martin.listenAddresses != []
    then builtins.head cfg.martin.listenAddresses
    else null;

  pbfDownloadSnippet =
    lib.concatMapStringsSep "\n" (country: ''
      download_country ${lib.escapeShellArg country.unitName} ${lib.escapeShellArg country.pbfUrl} ${lib.escapeShellArg country.replicationUrl}
    '')
    countrySpecs;

  osmUpdateSnippet =
    lib.concatMapStringsSep "\n" (country: ''
      update_country ${lib.escapeShellArg country.unitName} ${lib.escapeShellArg country.replicationUrl}
    '')
    countriesWithUpdates;

  osmPipelineEnabled = cfg.components.osmImport.enable || cfg.components.osmUpdate.enable;
in {
  options.services.osmTiles = {
    enable = lib.mkEnableOption "OpenMapTiles + imposm + Natural Earth + Martin stack";

    createSystemUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create a local system user/group for import and serving jobs.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "osm_maps";
      description = "Runtime user/group for import and service jobs.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/osm-tiles";
      description = "State directory for downloaded sources, imposm cache/diffs, and markers.";
    };

    components = {
      osmImport.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable initial OSM import pipeline.";
      };

      osmUpdate.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable OSM replication update job and timer.";
      };

      martin.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Martin vector tile server.";
      };

      nginx.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable nginx reverse proxy and cache.";
      };

      sampleClient.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable sample MapLibre website served by nginx.";
      };
    };

    source = {
      geofabrikBaseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://download.geofabrik.de";
        description = "Base URL for Geofabrik snapshots and replication URLs.";
      };

      naturalEarthSqliteUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://dev.maptiler.download/geodata/omt/natural_earth_vector.sqlite_v5.1.2.zip";
        description = "Natural Earth SQLite bundle URL used by OpenMapTiles import-data pipeline.";
      };

      waterPolygonsUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://osmdata.openstreetmap.de/download/water-polygons-split-3857.zip";
        description = "OpenStreetMapData water polygons source URL.";
      };
    };

    data = {
      locales = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["en"];
        description = "Locales exposed in generated OpenMapTiles SQL (`name:<locale>` fields).";
      };

      countries = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable this country import/update definition.";
            };

            geofabrikPath = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Geofabrik path suffix, for example `europe/germany`.";
            };

            pbfUrl = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional direct URL override for initial `.osm.pbf` snapshot.";
            };

            replicationUrl = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional direct replication URL override for imposm updates.";
            };

            updatesEnable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Include this country in periodic OSM update job runs.";
            };
          };
        }));
        default = {};
        description = "Country extracts to import/update. Empty keeps NE-only dataset.";
      };
    };

    database = {
      mode = lib.mkOption {
        type = lib.types.enum ["managed" "external"];
        default = "managed";
        description = "Use managed local PostgreSQL or external PostgreSQL.";
      };

      prepareDb = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Prepare DB/role/extensions with `database.adminUser` before imports.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "osm_maps";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "osm_maps";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PostgreSQL host for external mode or imposm TCP access.";
      };

      socketDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "/run/postgresql";
        description = "Optional PostgreSQL socket directory used by psql-based steps.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
      };

      adminUser = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
      };

      adminPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
      };

      connectionString = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      managed = {
        ramMB = lib.mkOption {
          type = lib.types.int;
          default = 4096;
          description = "Managed PostgreSQL memory target in MB. `shared_buffers=ramMB` and `effective_cache_size=2x`.";
        };

        enableTCPIP = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable managed PostgreSQL TCP listener (required for imposm).";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default =
            if pkgs ? postgresql_18
            then pkgs.postgresql_18.withPackages (ps: [ps.postgis])
            else pkgs.postgresql.withPackages (ps: [ps.postgis]);
        };
      };
    };

    martin = {
      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["127.0.0.1:3000"];
      };

      routePrefix = lib.mkOption {
        type = lib.types.str;
        default = "/maptiles";
      };

      poolSize = lib.mkOption {
        type = lib.types.int;
        default = 20;
      };

      workerProcesses = lib.mkOption {
        type = lib.types.int;
        default = 2;
      };

      withWebUi = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
      };
    };

    nginx = {
      serverName = lib.mkOption {
        type = lib.types.str;
        default = "_";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
      };

      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
      };

      martinUpstream = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      cache = {
        path = lib.mkOption {
          type = lib.types.str;
          default = "/var/cache/nginx/maptiles";
        };

        maxSize = lib.mkOption {
          type = lib.types.str;
          default = "10g";
        };

        inactive = lib.mkOption {
          type = lib.types.str;
          default = "60d";
        };
      };

      corsAllowOrigin = lib.mkOption {
        type = lib.types.str;
        default = "*";
      };
    };

    sampleClient = {
      title = lib.mkOption {
        type = lib.types.str;
        default = "OSM Tiles Demo";
      };

      maplibreCssUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.css";
      };

      maplibreJsUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://unpkg.com/maplibre-gl@5.2.0/dist/maplibre-gl.js";
      };
    };

    serving = {
      schema = lib.mkOption {
        type = lib.types.str;
        default = "public";
      };
    };

    jobs = {
      osmUpdate = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*:0/15";
        };

        randomizedDelaySec = lib.mkOption {
          type = lib.types.str;
          default = "30s";
        };
      };

      neUpdate = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "monthly";
        };

        randomizedDelaySec = lib.mkOption {
          type = lib.types.str;
          default = "2h";
        };
      };

      servingRefresh = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable periodic materialized-view refresh timer.";
        };

        onBootSec = lib.mkOption {
          type = lib.types.str;
          default = "45s";
        };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 08:11:00 UTC";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.database.host != null && cfg.database.socketDir != null);
        message = "services.osmTiles.database.host and .socketDir are mutually exclusive.";
      }
      {
        assertion = cfg.data.locales != [];
        message = "services.osmTiles.data.locales must not be empty.";
      }
      {
        assertion = !(cfg.components.sampleClient.enable && !cfg.components.nginx.enable);
        message = "services.osmTiles.components.sampleClient requires services.osmTiles.components.nginx.";
      }
      {
        assertion = !(cfg.components.nginx.enable && martinUpstream == null);
        message = "services.osmTiles.components.nginx requires martinUpstream or martin.listenAddresses.";
      }
      {
        assertion = cfg.martin.listenAddresses != [];
        message = "services.osmTiles.martin.listenAddresses must not be empty.";
      }
      {
        assertion = !(cfg.database.mode == "managed" && cfg.database.host != null);
        message = "services.osmTiles.database.host cannot be set in managed mode.";
      }
    ];

    users.users = lib.mkIf cfg.createSystemUser {
      ${cfg.user} = {
        isSystemUser = true;
        group = cfg.user;
        home = cfg.stateDir;
        createHome = true;
      };
    };

    users.groups = lib.mkIf cfg.createSystemUser {
      ${cfg.user} = {};
    };

    services.postgresql = lib.mkIf (cfg.database.mode == "managed") {
      enable = true;
      package = cfg.database.managed.package;
      enableTCPIP = cfg.database.managed.enableTCPIP;
      ensureDatabases = [cfg.database.name];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
      settings = managedPostgresqlSettings;
      authentication = ''
        local all all trust
        host all all 127.0.0.1/32 trust
        host all all ::1/128 trust
      '';
    };

    environment.systemPackages = [
      martinPackage
      openmaptilesTools
      pkgs.imposm
      pkgs.osmium-tool
    ];

    systemd.tmpfiles.rules =
      [
        "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.user} -"
        "d ${cfg.stateDir}/external 0750 ${cfg.user} ${cfg.user} -"
        "d ${cfg.stateDir}/pbf 0750 ${cfg.user} ${cfg.user} -"
        "d ${cfg.stateDir}/imposm 0750 ${cfg.user} ${cfg.user} -"
        "d ${cfg.stateDir}/imposm/expire 0750 ${cfg.user} ${cfg.user} -"
        "d ${cfg.stateDir}/imposm/config 0750 ${cfg.user} ${cfg.user} -"
        "d ${cfg.stateDir}/imposm/cache 0750 ${cfg.user} ${cfg.user} -"
        "d ${cfg.stateDir}/imposm/diff 0750 ${cfg.user} ${cfg.user} -"
      ]
      ++ lib.optional cfg.components.nginx.enable "d /var/cache/nginx 0750 nginx nginx -"
      ++ lib.optional cfg.components.nginx.enable "d ${cfg.nginx.cache.path} 0750 nginx nginx -";

    systemd.services = lib.mkMerge [
      (lib.mkIf cfg.database.prepareDb {
        osm-tiles-prepare-db = {
          description = "Prepare PostgreSQL role/database/extensions for osmTiles";
          after =
            lib.optional (cfg.database.mode == "managed") "postgresql.service"
            ++ lib.optional (cfg.database.mode == "managed") "postgresql-setup.service";
          wants =
            lib.optional (cfg.database.mode == "managed") "postgresql.service"
            ++ lib.optional (cfg.database.mode == "managed") "postgresql-setup.service";
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = cfg.database.adminUser;
            Group = cfg.database.adminUser;
            LoadCredential =
              lib.optional (cfg.database.adminPasswordFile != null) "pg_admin_password:${cfg.database.adminPasswordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            ${lib.optionalString (cfg.database.adminPasswordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_admin_password")"
            ''}

            role_exists="$(${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs "postgres")} -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${cfg.database.user}'")"
            if [ "$role_exists" != "1" ]; then
              ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs "postgres")} -c "CREATE ROLE \"${cfg.database.user}\" LOGIN"
            fi

            db_exists="$(${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs "postgres")} -tAc "SELECT 1 FROM pg_database WHERE datname = '${cfg.database.name}'")"
            if [ "$db_exists" != "1" ]; then
              ${postgresqlPackage}/bin/createdb ${lib.escapeShellArgs psqlHostArgs} -p ${lib.escapeShellArg (toString cfg.database.port)} -O ${lib.escapeShellArg cfg.database.user} ${lib.escapeShellArg cfg.database.name}
            fi

            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs cfg.database.name)} -c "CREATE EXTENSION IF NOT EXISTS postgis"
            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs cfg.database.name)} -c "CREATE EXTENSION IF NOT EXISTS hstore"
            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs cfg.database.name)} -c "ALTER DATABASE \"${cfg.database.name}\" OWNER TO \"${cfg.database.user}\""
            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs cfg.database.name)} -c "GRANT CONNECT, TEMP ON DATABASE \"${cfg.database.name}\" TO \"${cfg.database.user}\""
          '';
        };
      })

      (lib.mkIf osmPipelineEnabled {
        osm-tiles-import-external = {
          description = "Import external Natural Earth and water polygon datasets";
          after =
            ["network-online.target"]
            ++ lib.optional cfg.database.prepareDb "osm-tiles-prepare-db.service"
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wants =
            ["network-online.target"]
            ++ lib.optional cfg.database.prepareDb "osm-tiles-prepare-db.service"
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.user;
            LoadCredential =
              lib.optional (cfg.database.passwordFile != null) "pg_password:${cfg.database.passwordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            export PATH=${lib.makeBinPath [
              pkgs.coreutils
              pkgs.curl
              pkgs.unzip
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gdal
              postgresqlPackage
            ]}

            marker=${lib.escapeShellArg "${cfg.stateDir}/.external-imported"}
            if [ "''${OSM_TILES_FORCE_EXTERNAL_IMPORT:-0}" != "1" ] && [ -f "$marker" ]; then
              echo "External datasets already imported."
              exit 0
            fi

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}
            : "''${PGPASSWORD:=x}"

            external_dir=${lib.escapeShellArg "${cfg.stateDir}/external"}
            mkdir -p "$external_dir/natural_earth" "$external_dir/water_polygons"

            ne_zip="$external_dir/natural_earth/natural_earth_vector.sqlite_v5.1.2.zip"
            ne_sqlite="$external_dir/natural_earth/natural_earth_vector.sqlite"

            curl --fail --location --retry 5 --output "$ne_zip.tmp" ${lib.escapeShellArg cfg.source.naturalEarthSqliteUrl}
            mv "$ne_zip.tmp" "$ne_zip"
            unzip -oj "$ne_zip" -d "$external_dir/natural_earth"

            OGR_PG_ENABLE_METADATA=NO ogr2ogr \
              -progress \
              -f PostgreSQL \
              -s_srs EPSG:4326 \
              -t_srs EPSG:3857 \
              -clipsrc -180.1 -85.0511 180.1 85.0511 \
              "PG:dbname=${cfg.database.name} user=${cfg.database.user} host=${
              if dbSocketDir != null
              then dbSocketDir
              else dbHost
            } port=${toString cfg.database.port} password=''${PGPASSWORD}" \
              -lco GEOMETRY_NAME=geometry \
              -lco OVERWRITE=YES \
              -lco DIM=2 \
              -nlt GEOMETRY \
              -overwrite \
              "$ne_sqlite"

            water_zip="$external_dir/water_polygons/water-polygons-split-3857.zip"
            curl --fail --location --retry 5 --output "$water_zip.tmp" ${lib.escapeShellArg cfg.source.waterPolygonsUrl}
            mv "$water_zip.tmp" "$water_zip"
            unzip -oj "$water_zip" -d "$external_dir/water_polygons"

            OGR_PG_ENABLE_METADATA=NO ogr2ogr \
              -progress \
              -f PostgreSQL \
              -s_srs EPSG:3857 \
              -t_srs EPSG:3857 \
              -lco OVERWRITE=YES \
              -lco GEOMETRY_NAME=geometry \
              -overwrite \
              -nln "osm_ocean_polygon" \
              -nlt geometry \
              --config PG_USE_COPY YES \
              "PG:dbname=${cfg.database.name} user=${cfg.database.user} host=${
              if dbSocketDir != null
              then dbSocketDir
              else dbHost
            } port=${toString cfg.database.port} password=''${PGPASSWORD}" \
              "$external_dir/water_polygons/water_polygons.shp"

            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs psqlUserArgs} -c "ANALYZE osm_ocean_polygon"
            touch "$marker"
          '';
        };
      })

      (lib.mkIf osmPipelineEnabled {
        osm-tiles-osm-import = {
          description = "Import initial OSM snapshots using imposm";
          after =
            ["network-online.target" "osm-tiles-import-external.service"]
            ++ lib.optional cfg.database.prepareDb "osm-tiles-prepare-db.service"
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wants =
            ["network-online.target" "osm-tiles-import-external.service"]
            ++ lib.optional cfg.database.prepareDb "osm-tiles-prepare-db.service"
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.user;
            LoadCredential =
              lib.optional (cfg.database.passwordFile != null) "pg_password:${cfg.database.passwordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            export PATH=${lib.makeBinPath [
              pkgs.coreutils
              pkgs.curl
              pkgs.gnused
              pkgs.imposm
              pkgs.osmium-tool
              postgresqlPackage
              openmaptilesTools
            ]}

            marker=${lib.escapeShellArg "${cfg.stateDir}/.osm-imported"}
            if [ "''${OSM_TILES_FORCE_OSM_IMPORT:-0}" != "1" ] && [ -f "$marker" ]; then
              echo "OSM snapshots already imported."
              exit 0
            fi

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}
            : "''${PGPASSWORD:=x}"

            export POSTGRES_HOST=${lib.escapeShellArg (
              if dbHost != null
              then dbHost
              else "127.0.0.1"
            )}
            export POSTGRES_PORT=${lib.escapeShellArg (toString cfg.database.port)}
            export POSTGRES_DB=${lib.escapeShellArg cfg.database.name}
            export POSTGRES_USER=${lib.escapeShellArg cfg.database.user}
            export POSTGRES_PASSWORD="$PGPASSWORD"
            export IMPOSM_MAPPING_FILE=${lib.escapeShellArg "${generatedArtifacts}/mapping.yaml"}
            export SQL_TOOLS_DIR=${lib.escapeShellArg "${openmaptilesTools}/sql"}

            base_dir=${lib.escapeShellArg "${cfg.stateDir}/imposm"}
            pbf_dir=${lib.escapeShellArg "${cfg.stateDir}/pbf"}
            cfg_dir="$base_dir/config"
            cache_root="$base_dir/cache"
            diff_root="$base_dir/diff"
            expire_root="$base_dir/expire"

            mkdir -p "$cfg_dir" "$cache_root" "$diff_root" "$expire_root" "$pbf_dir"

            write_cfg() {
              local unit="$1"
              local repl_url="$2"
              local out="$cfg_dir/$unit.json"
              local norm="$repl_url"
              norm="''${norm%/}"
              printf '{\n  "replication_url": "%s/",\n  "replication_interval": "1m"\n}\n' "$norm" > "$out"
              echo "$out"
            }

            run_import() {
              local unit="$1"
              local repl_url="$2"
              local pbf_file="$3"
              local append="$4"

              export IMPOSM_CONFIG_FILE="$(write_cfg "$unit" "$repl_url")"
              export IMPOSM_CACHE_DIR="$cache_root/$unit"
              export IMPOSM_DIFF_DIR="$diff_root/$unit"
              export EXPIRETILES_DIR="$expire_root/$unit"
              mkdir -p "$IMPOSM_CACHE_DIR" "$IMPOSM_DIFF_DIR" "$EXPIRETILES_DIR"

              if [ "$append" = "1" ]; then
                APPEND_MODE=true DIFF_MODE=true import-osm "$pbf_file"
              else
                APPEND_MODE=false DIFF_MODE=true import-osm "$pbf_file"
              fi
            }

            download_country() {
              local unit="$1"
              local pbf_url="$2"
              local repl_url="$3"

              local pbf_file="$pbf_dir/$unit.osm.pbf"
              curl --fail --location --retry 5 --output "$pbf_file.tmp" "$pbf_url"
              mv "$pbf_file.tmp" "$pbf_file"

              if [ "''${append_mode:-0}" = "0" ]; then
                run_import "$unit" "$repl_url" "$pbf_file" 0
                append_mode=1
              else
                run_import "$unit" "$repl_url" "$pbf_file" 1
              fi
            }

            append_mode=0
            ${lib.optionalString (countryCount > 0) pbfDownloadSnippet}

            if [ ${toString countryCount} -eq 0 ]; then
              tmp_empty="$pbf_dir/empty.osm"
              tmp_pbf="$pbf_dir/empty.osm.pbf"
              printf "%s\n" "<?xml version='1.0' encoding='UTF-8'?>" "<osm version='0.6' generator='osm-tiles'/>" > "$tmp_empty"
              osmium cat "$tmp_empty" -o "$tmp_pbf"
              run_import "ne-only" "http://planet.openstreetmap.org/replication/day/" "$tmp_pbf" 0
            fi

            touch "$marker"
          '';
        };
      })

      (lib.mkIf (osmPipelineEnabled || cfg.components.osmUpdate.enable) {
        osm-tiles-sql-import = {
          description = "Import generated OpenMapTiles SQL tools and layer SQL";
          after =
            ["osm-tiles-osm-import.service"]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wants =
            ["osm-tiles-osm-import.service"]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.user;
            LoadCredential =
              lib.optional (cfg.database.passwordFile != null) "pg_password:${cfg.database.passwordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            export PATH=${lib.makeBinPath [
              postgresqlPackage
              openmaptilesTools
            ]}

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}
            : "''${PGPASSWORD:=x}"

            export POSTGRES_HOST=${lib.escapeShellArg (
              if dbHost != null
              then dbHost
              else "127.0.0.1"
            )}
            export POSTGRES_PORT=${lib.escapeShellArg (toString cfg.database.port)}
            export POSTGRES_DB=${lib.escapeShellArg cfg.database.name}
            export POSTGRES_USER=${lib.escapeShellArg cfg.database.user}
            export POSTGRES_PASSWORD="$PGPASSWORD"
            export SQL_TOOLS_DIR=${lib.escapeShellArg "${openmaptilesTools}/sql"}
            export SQL_DIR=${lib.escapeShellArg "${generatedArtifacts}/sql"}

            import-sql
          '';
        };
      })

      {
        osm-tiles-serving-refresh = {
          description = "Refresh OpenMapTiles materialized views";
          after =
            ["osm-tiles-sql-import.service"]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wants =
            ["osm-tiles-sql-import.service"]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.user;
            LoadCredential =
              lib.optional (cfg.database.passwordFile != null) "pg_password:${cfg.database.passwordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            export PATH=${lib.makeBinPath [openmaptilesTools]}

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}
            : "''${PGPASSWORD:=x}"

            refresh-views --schema ${lib.escapeShellArg cfg.serving.schema} \
              --pghost ${lib.escapeShellArg (
              if dbHost != null
              then dbHost
              else "127.0.0.1"
            )} \
              --pgport ${lib.escapeShellArg (toString cfg.database.port)} \
              --dbname ${lib.escapeShellArg cfg.database.name} \
              --user ${lib.escapeShellArg cfg.database.user} \
              --password "$PGPASSWORD"
          '';
        };
      }

      (lib.mkIf cfg.components.martin.enable {
        martin = {
          description = "Martin vector tile server";
          after =
            [
              "network.target"
              "osm-tiles-sql-import.service"
            ]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wants =
            ["osm-tiles-sql-import.service"]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          requires = ["osm-tiles-sql-import.service"];
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            Group = cfg.user;
            ExecStart =
              "${martinPackage}/bin/martin --config ${martinConfigFile} --listen-addresses ${lib.escapeShellArg (lib.concatStringsSep "," cfg.martin.listenAddresses)}"
              + lib.optionalString cfg.martin.withWebUi " --webui enable-for-all"
              + lib.optionalString (cfg.martin.extraArgs != []) " ${lib.escapeShellArgs cfg.martin.extraArgs}";
            Restart = "on-failure";
            RestartSec = "5s";
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ProtectHome = true;
          };
        };
      })

      (lib.mkIf cfg.components.osmUpdate.enable {
        osm-tiles-osm-update = {
          description = "Single OSM replication update job";
          after = ["network-online.target" "osm-tiles-osm-import.service"];
          wants = ["network-online.target" "osm-tiles-osm-import.service"];
          unitConfig = lib.optionalAttrs cfg.jobs.servingRefresh.enable {
            OnSuccess = "osm-tiles-serving-refresh.service";
          };

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.user;
            LoadCredential =
              lib.optional (cfg.database.passwordFile != null) "pg_password:${cfg.database.passwordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            export PATH=${lib.makeBinPath [
              pkgs.coreutils
              pkgs.imposm
              openmaptilesTools
            ]}

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}
            : "''${PGPASSWORD:=x}"

            export POSTGRES_HOST=${lib.escapeShellArg (
              if dbHost != null
              then dbHost
              else "127.0.0.1"
            )}
            export POSTGRES_PORT=${lib.escapeShellArg (toString cfg.database.port)}
            export POSTGRES_DB=${lib.escapeShellArg cfg.database.name}
            export POSTGRES_USER=${lib.escapeShellArg cfg.database.user}
            export POSTGRES_PASSWORD="$PGPASSWORD"
            export IMPOSM_MAPPING_FILE=${lib.escapeShellArg "${generatedArtifacts}/mapping.yaml"}

            base_dir=${lib.escapeShellArg "${cfg.stateDir}/imposm"}
            cfg_dir="$base_dir/config"
            cache_root="$base_dir/cache"
            diff_root="$base_dir/diff"
            expire_root="$base_dir/expire"

            mkdir -p "$cfg_dir" "$cache_root" "$diff_root" "$expire_root"

            write_cfg() {
              local unit="$1"
              local repl_url="$2"
              local out="$cfg_dir/$unit.json"
              local norm="$repl_url"
              norm="''${norm%/}"
              printf '{\n  "replication_url": "%s/",\n  "replication_interval": "1m"\n}\n' "$norm" > "$out"
              echo "$out"
            }

            update_country() {
              local unit="$1"
              local repl_url="$2"
              export IMPOSM_CONFIG_FILE="$(write_cfg "$unit" "$repl_url")"
              export IMPOSM_CACHE_DIR="$cache_root/$unit"
              export IMPOSM_DIFF_DIR="$diff_root/$unit"
              export EXPIRETILES_DIR="$expire_root/$unit"
              mkdir -p "$IMPOSM_CACHE_DIR" "$IMPOSM_DIFF_DIR" "$EXPIRETILES_DIR"
              import-update
            }

            ${lib.optionalString (builtins.length countriesWithUpdates == 0) ''
              echo "No countries with updates enabled; nothing to update."
              exit 0
            ''}

            ${osmUpdateSnippet}
          '';
        };
      })

      (lib.mkIf osmPipelineEnabled {
        osm-tiles-ne-update = {
          description = "Single Natural Earth update job";
          after = ["network-online.target"];
          wants = ["network-online.target"];

          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Group = "root";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail
            OSM_TILES_FORCE_EXTERNAL_IMPORT=1 ${pkgs.systemd}/bin/systemctl start --wait osm-tiles-import-external.service
          '';
        };
      })
    ];

    systemd.timers = lib.mkMerge [
      (lib.mkIf (cfg.components.osmUpdate.enable && cfg.jobs.osmUpdate.enable) {
        osm-tiles-osm-update = {
          description = "Timer for OSM replication updates";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.jobs.osmUpdate.onCalendar;
            Persistent = true;
            RandomizedDelaySec = cfg.jobs.osmUpdate.randomizedDelaySec;
            Unit = "osm-tiles-osm-update.service";
          };
        };
      })

      (lib.mkIf (osmPipelineEnabled && cfg.jobs.neUpdate.enable) {
        osm-tiles-ne-update = {
          description = "Timer for Natural Earth refresh imports";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.jobs.neUpdate.onCalendar;
            Persistent = true;
            RandomizedDelaySec = cfg.jobs.neUpdate.randomizedDelaySec;
            Unit = "osm-tiles-ne-update.service";
          };
        };
      })

      (lib.mkIf cfg.jobs.servingRefresh.enable {
        osm-tiles-serving-refresh = {
          description = "Timer for OpenMapTiles materialized-view refresh";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = cfg.jobs.servingRefresh.onBootSec;
            OnCalendar = cfg.jobs.servingRefresh.onCalendar;
            Persistent = true;
            Unit = "osm-tiles-serving-refresh.service";
          };
        };
      })
    ];

    services.nginx = lib.mkIf cfg.components.nginx.enable {
      enable = true;
      appendHttpConfig = ''
        proxy_cache_path ${cfg.nginx.cache.path} levels=1:2 keys_zone=osm_tiles_cache:200m max_size=${cfg.nginx.cache.maxSize} inactive=${cfg.nginx.cache.inactive} use_temp_path=off;
      '';

      upstreams.osm_tiles_martin = {
        extraConfig = ''
          keepalive 32;
        '';
        servers."${martinUpstream}" = {};
      };

      virtualHosts.${cfg.nginx.serverName} = {
        listen = [
          {
            addr = cfg.nginx.listenAddress;
            port = cfg.nginx.listenPort;
          }
        ];

        locations =
          {
            "= ${maptilesPath}" = {
              extraConfig = "return 400;";
            };

            "= ${maptilesPathWithSlash}" = {
              extraConfig = "return 400;";
            };

            "^~ ${maptilesPathWithSlash}" = {
              proxyPass = "http://osm_tiles_martin";
              extraConfig = ''
                proxy_cache osm_tiles_cache;
                proxy_cache_key "$scheme|$host|$request_uri";
                proxy_cache_methods GET HEAD;
                proxy_cache_valid 200 206 60d;
                proxy_cache_lock on;
                proxy_cache_background_update on;
                proxy_cache_use_stale updating error timeout http_500 http_502 http_503 http_504;

                proxy_read_timeout 2m;
                proxy_send_timeout 2m;

                proxy_hide_header Access-Control-Allow-Origin;
                add_header Access-Control-Allow-Origin "${cfg.nginx.corsAllowOrigin}" always;
                add_header Access-Control-Allow-Methods "GET, OPTIONS" always;
                add_header Access-Control-Allow-Headers "Origin, Accept, Range, Content-Type" always;
                add_header Access-Control-Max-Age "86400" always;

                if ($request_method = OPTIONS) { return 204; }
              '';
            };
          }
          // lib.optionalAttrs cfg.components.sampleClient.enable {
            "/" = {
              root = sampleClientRoot;
              index = "index.html";
              extraConfig = ''
                try_files $uri $uri/ /index.html;
              '';
            };
          };
      };
    };
  };

  meta = {
    maintainers = with lib.maintainers; [serpent213];
    doc = ./osm-tiles.md;
  };
}
