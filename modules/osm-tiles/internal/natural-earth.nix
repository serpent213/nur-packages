{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.naturalEarth;

  postgresqlPackage =
    if config.services.postgresql.enable
    then config.services.postgresql.package
    else pkgs.postgresql;

  psqlHostArgs =
    if cfg.database.socketDir != null
    then ["-h" cfg.database.socketDir]
    else if cfg.database.host != null
    then ["-h" cfg.database.host]
    else [];

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

  userPsqlArgs =
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

  ogrConnString =
    lib.concatStringsSep " "
    ([
        "dbname=${cfg.database.name}"
        "user=${cfg.database.user}"
        "port=${toString cfg.database.port}"
      ]
      ++ lib.optional (cfg.database.socketDir != null) "host=${cfg.database.socketDir}"
      ++ lib.optional (cfg.database.host != null) "host=${cfg.database.host}");

  enabledDatasets = lib.mapAttrsToList (name: dataset: dataset // {inherit name;}) (
    lib.filterAttrs (_: dataset: dataset.enable) cfg.datasets
  );

  importSnippet = dataset: ''
    echo "Importing dataset ${dataset.name} (${dataset.url})"
    zip_file="$tmp_dir/${dataset.table}.zip"
    unzip_dir="$tmp_dir/${dataset.table}"

    ${pkgs.curl}/bin/curl --fail --location --retry 5 --output "$zip_file.tmp" ${lib.escapeShellArg dataset.url}
    mv "$zip_file.tmp" "$zip_file"
    mkdir -p "$unzip_dir"
    ${pkgs.unzip}/bin/unzip -q "$zip_file" -d "$unzip_dir"

    shp_file="$(${pkgs.findutils}/bin/find "$unzip_dir" -type f -name '*.shp' | ${pkgs.coreutils}/bin/head -n1 || true)"
    if [ -z "$shp_file" ]; then
      echo "No shapefile found in $zip_file"
      exit 1
    fi

    OGR_PG_ENABLE_METADATA=NO ${cfg.gdalPackage}/bin/ogr2ogr \
      -makevalid \
      -f PostgreSQL \
      "PG:${ogrConnString}" \
      "$shp_file" \
      -overwrite \
      -nlt PROMOTE_TO_MULTI \
      -nln ${lib.escapeShellArg "${cfg.schema}.${dataset.table}"} \
      -lco GEOMETRY_NAME=geom \
      -lco FID=id \
      -lco PRECISION=NO \
      -lco SPATIAL_INDEX=GIST

    ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs userPsqlArgs} \
      -c "ALTER TABLE \"${cfg.schema}\".\"${dataset.table}\" OWNER TO \"${cfg.database.user}\""
    ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs userPsqlArgs} \
      -c "ANALYZE \"${cfg.schema}\".\"${dataset.table}\""
  '';
in {
  options.services.naturalEarth = {
    enable = lib.mkEnableOption "Natural Earth low-resolution basemap imports";

    gdalPackage = lib.mkPackageOption pkgs "gdal" {};

    user = lib.mkOption {
      type = lib.types.str;
      default = "osm_maps";
      description = "System user running Natural Earth import jobs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "osm_maps";
      description = "System group running Natural Earth import jobs.";
    };

    createSystemUser = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Create the system user/group used for Natural Earth imports.";
    };

    schema = lib.mkOption {
      type = lib.types.str;
      default = "osm_lowres";
      description = "Target PostgreSQL schema for Natural Earth tables.";
    };

    importOnBoot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run the Natural Earth import service automatically at boot.";
    };

    refresh = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable recurring Natural Earth re-import.";
      };

      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "monthly";
        description = "systemd timer schedule for Natural Earth refresh.";
      };

      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "2h";
        description = "Randomized timer delay for refresh runs.";
      };
    };

    database = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "osm_maps";
        description = "Target PostgreSQL database.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "osm_maps";
        description = "PostgreSQL user for imports.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing password for database.user.";
      };

      host = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "PostgreSQL host. Mutually exclusive with socketDir.";
      };

      socketDir = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "/run/postgresql";
        description = "PostgreSQL unix socket directory. Mutually exclusive with host.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port.";
      };

      adminUser = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
        description = "Admin user for schema preparation.";
      };

      adminPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing password for database.adminUser.";
      };

      prepareSchema = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create/own/grant target schema before imports.";
      };

      createExtensions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Ensure required extension `postgis` exists.";
      };
    };

    datasets = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable this dataset.";
          };

          url = lib.mkOption {
            type = lib.types.str;
            description = "Download URL for the zipped shapefile.";
          };

          table = lib.mkOption {
            type = lib.types.str;
            default = lib.replaceStrings [" " "." "-"] ["_" "_" "_"] name;
            description = "Destination table name in schema.";
          };
        };
      }));
      default = {
        land_110m = {
          url = "https://naciscdn.org/naturalearth/110m/physical/ne_110m_land.zip";
          table = "lowres_landcover";
        };
        ocean_110m = {
          url = "https://naciscdn.org/naturalearth/110m/physical/ne_110m_ocean.zip";
          table = "lowres_ocean";
        };
        countries_110m = {
          url = "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_admin_0_countries.zip";
          table = "lowres_boundary";
        };
        places_110m = {
          url = "https://naciscdn.org/naturalearth/110m/cultural/ne_110m_populated_places_simple.zip";
          table = "lowres_place";
        };
      };
      description = "Natural Earth datasets to import.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.database.host != null && cfg.database.socketDir != null);
        message = "services.naturalEarth.database.host and .socketDir are mutually exclusive.";
      }
      {
        assertion = enabledDatasets != [];
        message = "services.naturalEarth.datasets must contain at least one enabled dataset.";
      }
    ];

    users.users = lib.mkIf (cfg.createSystemUser && cfg.user != "postgres") {
      ${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
      };
    };

    users.groups = lib.mkIf (cfg.createSystemUser && cfg.group != "postgres") {
      ${cfg.group} = {};
    };

    systemd.services = lib.mkMerge [
      (lib.mkIf cfg.database.prepareSchema {
        natural-earth-prepare-db = {
          description = "Prepare PostgreSQL schema for Natural Earth imports";
          after = ["postgresql.service"];
          wants = ["postgresql.service"];

          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            Group = "postgres";
            LoadCredential =
              lib.optional
              (cfg.database.adminPasswordFile != null)
              "pg_admin_password:${cfg.database.adminPasswordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            ${lib.optionalString (cfg.database.adminPasswordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_admin_password")"
            ''}

            db_exists="$(${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs "postgres")} -tAc "SELECT 1 FROM pg_database WHERE datname = '${cfg.database.name}'")"
            if [ "$db_exists" != "1" ]; then
              echo "Database ${cfg.database.name} does not exist."
              exit 1
            fi

            ${lib.optionalString cfg.database.createExtensions ''
              ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs cfg.database.name)} -c "CREATE EXTENSION IF NOT EXISTS postgis"
            ''}

            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs cfg.database.name)} -c "CREATE SCHEMA IF NOT EXISTS \"${cfg.schema}\" AUTHORIZATION \"${cfg.database.user}\""
            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs cfg.database.name)} -c "ALTER SCHEMA \"${cfg.schema}\" OWNER TO \"${cfg.database.user}\""
            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminPsqlArgs cfg.database.name)} -c "GRANT USAGE, CREATE ON SCHEMA \"${cfg.schema}\" TO \"${cfg.database.user}\""
          '';
        };
      })

      {
        natural-earth-import = {
          description = "Import Natural Earth low-resolution datasets into PostgreSQL";
          after =
            [
              "network-online.target"
              "postgresql.service"
            ]
            ++ lib.optional cfg.database.prepareSchema "natural-earth-prepare-db.service";
          wants =
            [
              "network-online.target"
              "postgresql.service"
            ]
            ++ lib.optional cfg.database.prepareSchema "natural-earth-prepare-db.service";
          wantedBy = lib.optional cfg.importOnBoot "multi-user.target";

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = "/tmp";
            LoadCredential =
              lib.optional
              (cfg.database.passwordFile != null)
              "pg_password:${cfg.database.passwordFile}";
            NoNewPrivileges = true;
            PrivateTmp = true;
            UMask = "0027";
          };

          script = ''
            set -euo pipefail

            tmp_dir="$(mktemp -d)"
            cleanup() {
              rm -rf "$tmp_dir"
            }
            trap cleanup EXIT

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}

            ${lib.concatMapStringsSep "\n" importSnippet enabledDatasets}
          '';
        };
      }
    ];

    systemd.timers = lib.mkIf cfg.refresh.enable {
      natural-earth-import = {
        description = "Timer for Natural Earth import refresh";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = cfg.refresh.onCalendar;
          Persistent = true;
          RandomizedDelaySec = cfg.refresh.randomizedDelaySec;
          Unit = "natural-earth-import.service";
        };
      };
    };
  };
}
