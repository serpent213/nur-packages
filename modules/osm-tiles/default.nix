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

  osmPipelineEnabled = cfg.components.osm2pgsqlImport.enable || cfg.components.osm2pgsqlUpdate.enable;
  naturalEarthEnabled = osmPipelineEnabled;

  dbHost =
    if cfg.database.mode == "managed"
    then null
    else cfg.database.host;
  dbSocketDir = cfg.database.socketDir;

  psqlHostArgs =
    if dbSocketDir != null
    then ["-h" dbSocketDir]
    else if dbHost != null
    then ["-h" dbHost]
    else [];

  psqlUserArgs =
    [
      "-v"
      "ON_ERROR_STOP=1"
      "-U"
      cfg.database.user
      "-p"
      (toString cfg.database.port)
      "-d"
      cfg.database.name
    ]
    ++ psqlHostArgs;

  postgresqlPackage =
    if config.services.postgresql.enable
    then config.services.postgresql.package
    else pkgs.postgresql;

  enabledCountries = lib.mapAttrsToList (name: ccfg: ccfg // {inherit name;}) (
    lib.filterAttrs (_: ccfg: ccfg.enable) cfg.data.countries
  );

  countrySchemas = map (country: country.schema) enabledCountries;

  mirrorRegions =
    lib.mapAttrs (_: ccfg: {
      inherit
        (ccfg)
        enable
        geofabrikPath
        pbfUrl
        replicationUrl
        schema
        initOnBoot
        updatesEnable
        updateOnCalendar
        extraImportArgs
        extraUpdateArgs
        ;
    })
    cfg.data.countries;

  regionUpdateUnits = map (country: "osm-mirror-update-${sanitizeUnit country.name}.service") enabledCountries;

  div = a: b: builtins.floor (a / b);

  ramMB = cfg.database.managed.ramMB;
  sharedBuffersMB = lib.max 256 (div ramMB 4);
  effectiveCacheMB = lib.max 1024 (div (ramMB * 3) 4);
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

  martinConnectionString =
    if cfg.database.connectionString != null
    then cfg.database.connectionString
    else if dbSocketDir != null
    then "postgresql://${cfg.database.user}@/${cfg.database.name}?host=${dbSocketDir}&port=${toString cfg.database.port}&sslmode=disable"
    else "postgresql://${cfg.database.user}@${dbHost}:${toString cfg.database.port}/${cfg.database.name}?sslmode=disable";

  martinPackage = pkgs.callPackage ../../pkgs/martin {
    withWebUi = cfg.martin.withWebUi;
  };

  flexStyleFile = import ./generators/mk-flex-lua.nix {
    inherit
      lib
      pkgs
      ;
    locales = cfg.data.locales;
  };

  servingSetupSql = import ./generators/mk-serving-setup-sql.nix {
    inherit
      countrySchemas
      lib
      ;
    locales = cfg.data.locales;
    dbUser = cfg.database.user;
    servingSchema = cfg.serving.schema;
    lowresSchema = cfg.naturalEarth.schema;
  };

  servingRefreshSql = import ./generators/mk-serving-refresh-sql.nix {
    inherit lib;
    servingSchema = cfg.serving.schema;
  };

  servingSetupSqlFile = pkgs.writeText "osm-tiles-serving-setup.sql" servingSetupSql;
  servingRefreshSqlFile = pkgs.writeText "osm-tiles-serving-refresh.sql" servingRefreshSql;

  martinConfigFile = pkgs.writeText "osm-tiles-martin.yaml" (
    import ./generators/mk-martin-yaml.nix {
      inherit lib;
      routePrefix = cfg.martin.routePrefix;
      connectionString = martinConnectionString;
      poolSize = cfg.martin.poolSize;
      workerProcesses = cfg.martin.workerProcesses;
      servingSchema = cfg.serving.schema;
    }
  );

  sampleClientRoot = import ./generators/mk-sample-client.nix {
    inherit pkgs;
    title = cfg.sampleClient.title;
    maptilesPath = cfg.martin.routePrefix;
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
in {
  imports = [
    ./internal/osm-mirror.nix
    ./internal/natural-earth.nix
  ];

  options.services.osmTiles = {
    enable = lib.mkEnableOption "OSM + Natural Earth + Martin + optional nginx map tiles stack";

    createSystemUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create a local system user/group for osm2pgsql and Martin jobs.";
    };

    components = {
      osm2pgsqlImport.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable osm2pgsql initial import pipeline services.";
      };

      osm2pgsqlUpdate.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the single OSM replication update job/timer.";
      };

      martin.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Martin vector tile server.";
      };

      nginx.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable nginx reverse proxy with cache in front of Martin.";
      };

      sampleClient.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable a sample MapLibre JS website served by nginx.";
      };
    };

    source = {
      geofabrikBaseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://download.geofabrik.de";
        description = "Base URL for Geofabrik downloads and replication.";
      };
    };

    data = {
      locales = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["en"];
        example = ["en" "de" "fr"];
        description = "Locales imported from OSM `name:<locale>` tags.";
      };

      countries = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable country import/update for this entry.";
            };

            geofabrikPath = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Geofabrik path suffix, for example `europe/germany`.";
            };

            pbfUrl = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Direct PBF URL override for initial import.";
            };

            replicationUrl = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Direct replication URL override for updates.";
            };

            schema = lib.mkOption {
              type = lib.types.str;
              default = "osm_${sanitizeSchema name}";
              description = "Target PostgreSQL schema for this country.";
            };

            initOnBoot = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Run initial import automatically on boot for this country.";
            };

            updatesEnable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Include this country in replication update runs.";
            };

            updateOnCalendar = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Unused by this module (single global OSM job), kept for compatibility.";
            };

            extraImportArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Extra osm2pgsql args for initial import.";
            };

            extraUpdateArgs = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [];
              description = "Extra osm2pgsql args for replication updates.";
            };
          };
        }));
        default = {};
        description = "Country extracts to import. Empty means NE-only mode.";
      };
    };

    database = {
      mode = lib.mkOption {
        type = lib.types.enum ["managed" "external"];
        default = "managed";
        description = "Use internal managed PostgreSQL or external PostgreSQL.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "osm_maps";
        description = "PostgreSQL database name used by the stack.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "osm_maps";
        description = "PostgreSQL user and runtime service user for jobs.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Password file for `database.user`.";
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PostgreSQL host (external mode). Mutually exclusive with socketDir.";
      };

      socketDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "/run/postgresql";
        description = "PostgreSQL socket directory. Mutually exclusive with host.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port.";
      };

      adminUser = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
        description = "Admin PostgreSQL user for bootstrap operations.";
      };

      adminPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Password file for `database.adminUser`.";
      };

      connectionString = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional explicit PostgreSQL connection string for Martin.";
      };

      managed = {
        ramMB = lib.mkOption {
          type = lib.types.int;
          default = 4096;
          description = "Roundabout max RAM budget for managed PostgreSQL tuning (MB).";
        };

        enableTCPIP = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable managed PostgreSQL TCP listener.";
        };

        package = lib.mkOption {
          type = lib.types.package;
          default =
            if pkgs ? postgresql_18
            then pkgs.postgresql_18.withPackages (ps: [ps.postgis])
            else pkgs.postgresql.withPackages (ps: [ps.postgis]);
          description = "Managed PostgreSQL package.";
        };
      };
    };

    osm2pgsql = {
      import = {
        cacheMB = lib.mkOption {
          type = lib.types.int;
          default = 4096;
          description = "osm2pgsql cache for initial imports.";
        };

        numberProcesses = lib.mkOption {
          type = lib.types.int;
          default = 4;
          description = "osm2pgsql worker processes.";
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Extra global args passed to osm2pgsql imports.";
        };
      };

      update = {
        maxDiffSizeMB = lib.mkOption {
          type = lib.types.int;
          default = 500;
          description = "Maximum diff size in MB for osm2pgsql-replication update runs.";
        };

        extraOsm2pgsqlArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "Extra osm2pgsql args for replication updates.";
        };
      };
    };

    martin = {
      listenAddresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["127.0.0.1:3000"];
        description = "Martin listen addresses passed to `--listen-addresses`.";
      };

      routePrefix = lib.mkOption {
        type = lib.types.str;
        default = "/maptiles";
        description = "Martin route prefix for tile endpoints.";
      };

      poolSize = lib.mkOption {
        type = lib.types.int;
        default = 40;
        description = "Martin PostgreSQL pool size.";
      };

      workerProcesses = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Martin worker process count.";
      };

      withWebUi = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Build Martin with bundled WebUI.";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional Martin CLI arguments.";
      };
    };

    nginx = {
      serverName = lib.mkOption {
        type = lib.types.str;
        default = "_";
        description = "nginx server_name for the map vhost.";
      };

      listenAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Address for the map vhost.";
      };

      listenPort = lib.mkOption {
        type = lib.types.port;
        default = 8080;
        description = "Port for the map vhost.";
      };

      martinUpstream = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Upstream address for Martin (defaults to first martin.listenAddresses entry).";
      };

      cache = {
        path = lib.mkOption {
          type = lib.types.str;
          default = "/var/cache/nginx/maptiles";
          description = "nginx cache path for vector tiles.";
        };

        maxSize = lib.mkOption {
          type = lib.types.str;
          default = "10g";
          description = "Maximum nginx cache size.";
        };

        inactive = lib.mkOption {
          type = lib.types.str;
          default = "60d";
          description = "nginx cache inactive TTL.";
        };
      };

      corsAllowOrigin = lib.mkOption {
        type = lib.types.str;
        default = "*";
        description = "Access-Control-Allow-Origin value for tile responses.";
      };
    };

    sampleClient = {
      title = lib.mkOption {
        type = lib.types.str;
        default = "OSM Tiles Demo";
        description = "Page title for the sample MapLibre website.";
      };
    };

    naturalEarth = {
      schema = lib.mkOption {
        type = lib.types.str;
        default = "osm_lowres";
        description = "Schema where Natural Earth datasets are imported.";
      };
    };

    serving = {
      schema = lib.mkOption {
        type = lib.types.str;
        default = "osm_serving";
        description = "Schema for generated serving views/functions/materialized views.";
      };
    };

    jobs = {
      osmUpdate = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable the single OSM update job timer.";
        };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*:0/15";
          description = "systemd timer OnCalendar for OSM updates.";
        };

        randomizedDelaySec = lib.mkOption {
          type = lib.types.str;
          default = "30s";
          description = "Randomized delay for OSM update timer.";
        };
      };

      neUpdate = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable the single Natural Earth update job timer.";
        };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "monthly";
          description = "systemd timer OnCalendar for Natural Earth imports.";
        };

        randomizedDelaySec = lib.mkOption {
          type = lib.types.str;
          default = "2h";
          description = "Randomized delay for Natural Earth update timer.";
        };
      };

      servingRefresh = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable periodic serving materialized-view refresh timer.";
        };

        onBootSec = lib.mkOption {
          type = lib.types.str;
          default = "45s";
          description = "Refresh timer delay after boot.";
        };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 08:11:00 UTC";
          description = "Periodic schedule for serving refresh timer.";
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
        assertion = !(cfg.database.mode == "managed" && cfg.database.host != null);
        message = "services.osmTiles.database.host cannot be set in managed mode.";
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
    ];

    users.users = lib.mkIf (cfg.createSystemUser && cfg.database.user != "postgres") {
      ${cfg.database.user} = {
        isSystemUser = true;
        group = cfg.database.user;
        home = "/var/lib/${cfg.database.user}";
        createHome = true;
      };
    };

    users.groups = lib.mkIf (cfg.createSystemUser && cfg.database.user != "postgres") {
      ${cfg.database.user} = {};
    };

    services.postgresql = lib.mkIf (cfg.database.mode == "managed") {
      enable = true;
      package = cfg.database.managed.package;
      enableTCPIP = cfg.database.managed.enableTCPIP;
      settings = managedPostgresqlSettings;
    };

    services.osmMirror = lib.mkIf osmPipelineEnabled {
      enable = true;
      geofabrikBaseUrl = cfg.source.geofabrikBaseUrl;
      styleFile = flexStyleFile;
      user = cfg.database.user;
      group = cfg.database.user;
      createSystemUser = false;

      database = {
        name = cfg.database.name;
        user = cfg.database.user;
        passwordFile = cfg.database.passwordFile;
        host = dbHost;
        socketDir = dbSocketDir;
        port = cfg.database.port;
        createIfMissing = cfg.database.mode == "managed";
        adminUser = cfg.database.adminUser;
        adminPasswordFile = cfg.database.adminPasswordFile;
        createExtensions = true;
      };

      import = {
        cacheMB = cfg.osm2pgsql.import.cacheMB;
        numberProcesses = cfg.osm2pgsql.import.numberProcesses;
        extraArgs = cfg.osm2pgsql.import.extraArgs;
      };

      updates = {
        enable = false;
        maxDiffSizeMB = cfg.osm2pgsql.update.maxDiffSizeMB;
        extraOsm2pgsqlArgs = cfg.osm2pgsql.update.extraOsm2pgsqlArgs;
      };

      regions = mirrorRegions;
    };

    services.naturalEarth = lib.mkIf naturalEarthEnabled {
      enable = true;
      user = cfg.database.user;
      group = cfg.database.user;
      createSystemUser = false;
      schema = cfg.naturalEarth.schema;
      importOnBoot = cfg.components.osm2pgsqlImport.enable || cfg.components.osm2pgsqlUpdate.enable;

      database = {
        name = cfg.database.name;
        user = cfg.database.user;
        passwordFile = cfg.database.passwordFile;
        host = dbHost;
        socketDir = dbSocketDir;
        port = cfg.database.port;
        adminUser = cfg.database.adminUser;
        adminPasswordFile = cfg.database.adminPasswordFile;
        prepareSchema = true;
        createExtensions = true;
      };

      refresh.enable = false;
    };

    environment.systemPackages = lib.mkIf cfg.components.martin.enable [martinPackage];

    systemd.tmpfiles.rules = lib.mkIf cfg.components.nginx.enable [
      "d /var/cache/nginx 0750 nginx nginx -"
      "d ${cfg.nginx.cache.path} 0750 nginx nginx -"
    ];

    systemd.services = lib.mkMerge [
      {
        osm-tiles-serving-setup = {
          description = "Prepare OSM tile serving views/functions";
          after =
            lib.optional (cfg.database.mode == "managed") "postgresql.service"
            ++ lib.optional (osmPipelineEnabled && cfg.database.mode == "managed") "osm-mirror-prepare-db.service"
            ++ lib.optional naturalEarthEnabled "natural-earth-prepare-db.service";
          wants =
            lib.optional (cfg.database.mode == "managed") "postgresql.service"
            ++ lib.optional (osmPipelineEnabled && cfg.database.mode == "managed") "osm-mirror-prepare-db.service"
            ++ lib.optional naturalEarthEnabled "natural-earth-prepare-db.service";
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "oneshot";
            User = cfg.database.user;
            Group = cfg.database.user;
            LoadCredential =
              lib.optional
              (cfg.database.passwordFile != null)
              "pg_password:${cfg.database.passwordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}

            ${postgresqlPackage}/bin/psql \
              ${lib.escapeShellArgs psqlUserArgs} \
              -f ${servingSetupSqlFile}
          '';
        };

        osm-tiles-serving-refresh = {
          description = "Refresh serving materialized views";
          after =
            ["osm-tiles-serving-setup.service"]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wants =
            ["osm-tiles-serving-setup.service"]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wantedBy = [];

          serviceConfig = {
            Type = "oneshot";
            User = cfg.database.user;
            Group = cfg.database.user;
            LoadCredential =
              lib.optional
              (cfg.database.passwordFile != null)
              "pg_password:${cfg.database.passwordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}

            has_lowzoom_views="$(${postgresqlPackage}/bin/psql -X -A -t \
              ${lib.escapeShellArgs psqlUserArgs} \
              -c "SELECT to_regclass('${cfg.serving.schema}.landcover_low_z5') IS NOT NULL")"

            if [ "$has_lowzoom_views" != "t" ]; then
              ${postgresqlPackage}/bin/psql \
                ${lib.escapeShellArgs psqlUserArgs} \
                -f ${servingSetupSqlFile}
            fi

            ${postgresqlPackage}/bin/psql \
              ${lib.escapeShellArgs psqlUserArgs} \
              -f ${servingRefreshSqlFile}
          '';
        };
      }

      (lib.mkIf cfg.components.martin.enable {
        martin = {
          description = "Martin vector tile server";
          after =
            [
              "network.target"
              "osm-tiles-serving-setup.service"
            ]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          wants =
            ["osm-tiles-serving-setup.service"]
            ++ lib.optional (cfg.database.mode == "managed") "postgresql.service";
          requires = ["osm-tiles-serving-setup.service"];
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "simple";
            User = cfg.database.user;
            Group = cfg.database.user;
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

      (lib.mkIf cfg.components.osm2pgsqlUpdate.enable {
        osm-tiles-osm-update = {
          description = "Single OSM replication update job across all configured countries";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          unitConfig = lib.optionalAttrs cfg.jobs.servingRefresh.enable {
            OnSuccess = "osm-tiles-serving-refresh.service";
          };

          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Group = "root";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            ${lib.optionalString (regionUpdateUnits == []) ''
              echo "No countries configured; OSM update job has nothing to do."
              exit 0
            ''}

            for unit in ${lib.concatStringsSep " " (map lib.escapeShellArg regionUpdateUnits)}; do
              ${pkgs.systemd}/bin/systemctl start --wait "$unit"
            done
          '';
        };
      })

      (lib.mkIf naturalEarthEnabled {
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
            ${pkgs.systemd}/bin/systemctl start --wait natural-earth-import.service
          '';
        };
      })
    ];

    systemd.timers = lib.mkMerge [
      (lib.mkIf (cfg.components.osm2pgsqlUpdate.enable && cfg.jobs.osmUpdate.enable) {
        osm-tiles-osm-update = {
          description = "Timer for single OSM replication update job";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = cfg.jobs.osmUpdate.onCalendar;
            Persistent = true;
            RandomizedDelaySec = cfg.jobs.osmUpdate.randomizedDelaySec;
            Unit = "osm-tiles-osm-update.service";
          };
        };
      })

      (lib.mkIf (naturalEarthEnabled && cfg.jobs.neUpdate.enable) {
        osm-tiles-ne-update = {
          description = "Timer for single Natural Earth import refresh";
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
          description = "Timer for serving materialized-view refresh";
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
