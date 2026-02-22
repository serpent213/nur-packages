{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.osmMirror;

  postgresqlPackage =
    if config.services.postgresql.enable
    then config.services.postgresql.package
    else pkgs.postgresql;

  sanitizeUnit = name:
    lib.replaceStrings ["/" " " "." "_"] ["-" "-" "-" "-"] name;

  sanitizeSchema = name:
    lib.replaceStrings ["/" " " "." "-"] ["_" "_" "_" "_"] name;

  defaultStyle = pkgs.writeText "osm-mirror-default-flex.lua" ''
    local srid = 3857
    local tables = {}

    tables.landcover = osm2pgsql.define_area_table('landcover', {
        { column = 'class', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'geometry', projection = srid, not_null = true },
    })

    tables.landuse = osm2pgsql.define_area_table('landuse', {
        { column = 'class', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'geometry', projection = srid, not_null = true },
    })

    tables.park = osm2pgsql.define_area_table('park', {
        { column = 'class', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'geometry', projection = srid, not_null = true },
    })

    tables.water = osm2pgsql.define_area_table('water', {
        { column = 'class', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'geometry', projection = srid, not_null = true },
    })

    tables.waterway = osm2pgsql.define_way_table('waterway', {
        { column = 'class', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'linestring', projection = srid, not_null = true },
    })

    tables.boundary = osm2pgsql.define_way_table('boundary', {
        { column = 'class', type = 'text' },
        { column = 'admin_level', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'linestring', projection = srid, not_null = true },
    })

    tables.transportation = osm2pgsql.define_way_table('transportation', {
        { column = 'class', type = 'text' },
        { column = 'brunnel', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'ref', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'linestring', projection = srid, not_null = true },
    })

    tables.transportation_name = osm2pgsql.define_way_table('transportation_name', {
        { column = 'class', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'ref', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'linestring', projection = srid, not_null = true },
    })

    tables.building = osm2pgsql.define_area_table('building', {
        { column = 'class', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'geometry', projection = srid, not_null = true },
    })

    tables.water_name = osm2pgsql.define_way_table('water_name', {
        { column = 'class', type = 'text' },
        { column = 'name', type = 'text' },
        { column = 'name_en', type = 'text' },
        { column = 'tags', type = 'jsonb' },
        { column = 'geom', type = 'linestring', projection = srid, not_null = true },
    })

    tables.place = osm2pgsql.define_table({
        name = 'place',
        ids = { type = 'any', id_column = 'osm_id', type_column = 'osm_type' },
        columns = {
            { column = 'class', type = 'text' },
            { column = 'name', type = 'text' },
            { column = 'name_en', type = 'text' },
            { column = 'population', type = 'int8' },
            { column = 'tags', type = 'jsonb' },
            { column = 'geom', type = 'point', projection = 4326, not_null = true },
        },
        indexes = {
            { column = 'geom', method = 'gist' },
            { column = { 'class', 'name' }, method = 'btree' },
            { column = 'population', method = 'btree' },
        }
    })

    local function has_area_tags(tags)
        if tags.area == 'yes' then
            return true
        end
        if tags.area == 'no' then
            return false
        end

        return tags.aeroway
            or tags.amenity
            or tags.building
            or tags.harbour
            or tags.historic
            or tags.landuse
            or tags.landcover
            or tags.leisure
            or tags.man_made
            or tags.natural
            or tags.office
            or tags.place
            or tags.power
            or tags.public_transport
            or tags.shop
            or tags.sport
            or tags.tourism
            or tags.water
            or tags.waterway
            or tags.wetland
            or tags['area:highway']
    end

    local function is_truthy(value)
        return value and value ~= 'no' and value ~= 'false' and value ~= '0'
    end

    local function name_en(tags)
        return tags['name:en']
    end

    local function insert_place(tags, geom)
        if not tags.place then
            return
        end

        tables.place:insert({
            class = tags.place,
            name = tags.name,
            name_en = name_en(tags),
            population = tonumber(tags.population),
            tags = tags,
            geom = geom
        })
    end

    local function landcover_class(tags)
        if tags.natural then
            return tags.natural
        end
        if tags.landcover then
            return tags.landcover
        end
        if tags.wetland then
            return 'wetland'
        end
        return nil
    end

    local function landuse_class(tags)
        if tags.landuse then
            return tags.landuse
        end
        if tags.amenity then
            return tags.amenity
        end
        if tags.man_made then
            return tags.man_made
        end
        return nil
    end

    local function park_class(tags)
        if tags.leisure == 'park' or tags.leisure == 'nature_reserve' or tags.boundary == 'national_park' then
            return tags.leisure or tags.boundary
        end
        return nil
    end

    local function water_class(tags)
        if tags.natural == 'water' then
            return tags.water or 'water'
        end
        if tags.water then
            return tags.water
        end
        if tags.landuse == 'reservoir' then
            return 'reservoir'
        end
        if tags.waterway == 'riverbank' then
            return 'riverbank'
        end
        return nil
    end

    local function waterway_class(tags)
        return tags.waterway
    end

    local function boundary_class(tags)
        if tags.boundary then
            return tags.boundary
        end
        if tags.admin_level then
            return 'administrative'
        end
        return nil
    end

    local function transportation_class(tags)
        if tags.highway then
            return tags.highway
        end
        if tags.railway then
            return 'rail'
        end
        if tags.aeroway then
            return tags.aeroway
        end
        return nil
    end

    local function insert_polygon_features(tags, geom)
        local lc = landcover_class(tags)
        if lc then
            tables.landcover:insert({ class = lc, name = tags.name, name_en = name_en(tags), tags = tags, geom = geom })
        end

        local lu = landuse_class(tags)
        if lu then
            tables.landuse:insert({ class = lu, name = tags.name, name_en = name_en(tags), tags = tags, geom = geom })
        end

        local pk = park_class(tags)
        if pk then
            tables.park:insert({ class = pk, name = tags.name, name_en = name_en(tags), tags = tags, geom = geom })
        end

        local w = water_class(tags)
        if w then
            tables.water:insert({ class = w, name = tags.name, name_en = name_en(tags), tags = tags, geom = geom })
        end

        if tags.building then
            tables.building:insert({
                class = tags.building == 'yes' and 'building' or tags.building,
                name = tags.name,
                name_en = name_en(tags),
                tags = tags,
                geom = geom
            })
        end
    end

    local function insert_boundary(tags, geom)
        local class = boundary_class(tags)
        if not class then
            return
        end

        tables.boundary:insert({
            class = class,
            admin_level = tags.admin_level,
            name = tags.name,
            name_en = name_en(tags),
            tags = tags,
            geom = geom
        })
    end

    local function insert_transportation(tags, geom)
        local class = transportation_class(tags)
        if not class then
            return
        end

        local brunnel = nil
        if is_truthy(tags.tunnel) then
            brunnel = 'tunnel'
        elseif is_truthy(tags.bridge) then
            brunnel = 'bridge'
        end

        tables.transportation:insert({
            class = class,
            brunnel = brunnel,
            name = tags.name,
            name_en = name_en(tags),
            ref = tags.ref,
            tags = tags,
            geom = geom
        })

        if tags.name or name_en(tags) or tags.ref then
            tables.transportation_name:insert({
                class = class,
                name = tags.name,
                name_en = name_en(tags),
                ref = tags.ref,
                tags = tags,
                geom = geom
            })
        end
    end

    local function insert_waterway(tags, geom)
        local class = waterway_class(tags)
        if not class then
            return
        end

        tables.waterway:insert({
            class = class,
            name = tags.name,
            name_en = name_en(tags),
            tags = tags,
            geom = geom
        })

        if tags.name or name_en(tags) then
            tables.water_name:insert({
                class = class,
                name = tags.name,
                name_en = name_en(tags),
                tags = tags,
                geom = geom
            })
        end
    end

    function osm2pgsql.process_node(object)
        local point = object:as_point()
        insert_place(object.tags, point)
    end

    function osm2pgsql.process_way(object)
        if object.is_closed and has_area_tags(object.tags) then
            local polygon = object:as_polygon()
            insert_polygon_features(object.tags, polygon)
            insert_place(object.tags, polygon:centroid())
            return
        end

        local line = object:as_linestring()
        insert_waterway(object.tags, line)
        insert_boundary(object.tags, line)
        insert_transportation(object.tags, line)
    end

    function osm2pgsql.process_relation(object)
        if object.tags.type == 'multipolygon' then
            local mp = object:as_multipolygon()
            insert_polygon_features(object.tags, mp)
            insert_place(object.tags, mp:centroid())
        end
    end
  '';

  hostArgs =
    if cfg.database.socketDir != null
    then ["-H" cfg.database.socketDir]
    else if cfg.database.host != null
    then ["-H" cfg.database.host]
    else [];

  psqlHostArgs =
    if cfg.database.socketDir != null
    then ["-h" cfg.database.socketDir]
    else if cfg.database.host != null
    then ["-h" cfg.database.host]
    else [];

  dbArgs = region:
    [
      "-d"
      cfg.database.name
      "-U"
      cfg.database.user
      "-P"
      (toString cfg.database.port)
      "--schema"
      region.schema
      "-p"
      region.prefix
    ]
    ++ hostArgs;

  adminArgs = dbName:
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

  createdbArgs =
    [
      "-U"
      cfg.database.adminUser
      "-p"
      (toString cfg.database.port)
    ]
    ++ psqlHostArgs;

  enabledRegions = lib.mapAttrsToList (name: rcfg: let
    unit = sanitizeUnit name;
    schema = rcfg.schema;
    pbfUrl =
      if rcfg.pbfUrl != null
      then rcfg.pbfUrl
      else if rcfg.geofabrikPath != null
      then "${cfg.geofabrikBaseUrl}/${rcfg.geofabrikPath}-latest.osm.pbf"
      else null;
    replicationUrl =
      if rcfg.replicationUrl != null
      then rcfg.replicationUrl
      else if rcfg.geofabrikPath == null
      then null
      else "${cfg.geofabrikBaseUrl}/${rcfg.geofabrikPath}-updates";
    styleFileSource =
      if rcfg.styleFile != null
      then rcfg.styleFile
      else cfg.styleFile;
    styleFile = pkgs.writeText "osm-mirror-style-${unit}.lua" (builtins.readFile styleFileSource);
    stateDir = "${cfg.stateDir}/${unit}";
  in
    rcfg
    // {
      inherit
        name
        unit
        schema
        pbfUrl
        replicationUrl
        styleFile
        stateDir
        ;
    })
  (lib.filterAttrs (_: rcfg: rcfg.enable) cfg.regions);
in {
  options.services.osmMirror = {
    enable = lib.mkEnableOption "OSM mirror with osm2pgsql + Geofabrik replication";

    package = lib.mkPackageOption pkgs "osm2pgsql" {};

    geofabrikBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://download.geofabrik.de";
      description = "Base URL used for derived Geofabrik extract and replication URLs.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "osm_maps";
      description = "System user running import/update jobs.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "osm_maps";
      description = "System group running import/update jobs.";
    };

    createSystemUser = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Create the system user/group used for import and update jobs.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/osm-mirror";
      description = "Base directory for temporary per-region import files.";
    };

    styleFile = lib.mkOption {
      type = lib.types.path;
      default = defaultStyle;
      description = "Default osm2pgsql flex style file used when a region has no override.";
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
        description = "Dedicated PostgreSQL user for imports and replication updates.";
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

      createIfMissing = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Create the target database automatically if missing.";
      };

      adminUser = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
        description = "Administrative PostgreSQL user for bootstrap operations.";
      };

      adminPasswordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "File containing password for database.adminUser.";
      };

      createExtensions = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Ensure required extensions (`postgis`, `hstore`) exist in target DB.";
      };
    };

    import = {
      cacheMB = lib.mkOption {
        type = lib.types.int;
        default = 4096;
        description = "osm2pgsql cache size for initial imports.";
      };

      numberProcesses = lib.mkOption {
        type = lib.types.int;
        default = 4;
        description = "Number of osm2pgsql worker processes.";
      };

      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional global arguments passed to osm2pgsql initial imports.";
      };
    };

    updates = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable recurring replication updates.";
      };

      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*:0/15";
        description = "Default timer schedule for update jobs.";
      };

      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        description = "Randomized timer delay.";
      };

      maxDiffSizeMB = lib.mkOption {
        type = lib.types.int;
        default = 500;
        description = "Maximum diff batch size for osm2pgsql-replication.";
      };

      restartMartinOnSuccess = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Restart martin.service after successful update runs.";
      };

      extraOsm2pgsqlArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Additional osm2pgsql args passed during replication updates.";
      };
    };

    regions = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable this region.";
          };

          geofabrikPath = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Path suffix below download.geofabrik.de, e.g. `europe/germany`.";
          };

          pbfUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Direct URL to initial PBF extract. Overrides geofabrikPath-derived URL.";
          };

          replicationUrl = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Replication server base URL. Overrides geofabrikPath-derived URL.";
          };

          schema = lib.mkOption {
            type = lib.types.str;
            default = "osm_${sanitizeSchema name}";
            description = "Target PostgreSQL schema for this region.";
          };

          prefix = lib.mkOption {
            type = lib.types.str;
            default = "planet_osm";
            description = "osm2pgsql table prefix.";
          };

          styleFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Optional region-specific flex style override.";
          };

          initOnBoot = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Run initial import automatically during boot until initialized.";
          };

          updatesEnable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable replication updates for this region.";
          };

          updateOnCalendar = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Region-specific timer schedule override.";
          };

          extraImportArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional osm2pgsql args for initial import of this region.";
          };

          extraUpdateArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional osm2pgsql args for updates of this region.";
          };
        };
      }));
      default = {};
      description = "Region definitions to mirror into PostgreSQL.";
    };
  };

  config = lib.mkIf cfg.enable {
    warnings =
      lib.optional (
        cfg.database.socketDir != null && cfg.user != cfg.database.user
      ) ''
        services.osmMirror uses socket auth via `${cfg.database.socketDir}` with service user
        `${cfg.user}` and database user `${cfg.database.user}`. With default peer auth this can
        fail. Set services.osmMirror.user = services.osmMirror.database.user, or use password auth.
      '';

    assertions =
      [
        {
          assertion = !(cfg.database.host != null && cfg.database.socketDir != null);
          message = "services.osmMirror.database.host and .socketDir are mutually exclusive.";
        }
      ]
      ++ map (region: {
        assertion = region.pbfUrl != null;
        message = "services.osmMirror region `${region.name}` requires either geofabrikPath or pbfUrl.";
      })
      enabledRegions
      ++ map (region: {
        assertion = !(cfg.updates.enable && region.updatesEnable) || region.replicationUrl != null;
        message = "services.osmMirror region `${region.name}` has updates enabled but no replication URL (set replicationUrl or geofabrikPath).";
      })
      enabledRegions;

    users.users = lib.mkIf (cfg.createSystemUser && cfg.user != "postgres") {
      ${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        createHome = true;
      };
    };

    users.groups = lib.mkIf (cfg.createSystemUser && cfg.group != "postgres") {
      ${cfg.group} = {};
    };

    systemd.tmpfiles.rules =
      [
        "d ${cfg.stateDir} 0750 ${cfg.user} ${cfg.group} -"
      ]
      ++ map (region: "d ${region.stateDir} 0750 ${cfg.user} ${cfg.group} -") enabledRegions;

    systemd.services = lib.mkMerge (
      (lib.optional cfg.database.createIfMissing {
        osm-mirror-prepare-db = {
          description = "Prepare PostgreSQL for OSM mirror imports";
          after = ["postgresql.service"];
          wants = ["postgresql.service"];
          wantedBy = ["multi-user.target"];

          serviceConfig = {
            Type = "oneshot";
            User = "postgres";
            Group = "postgres";
            LoadCredential =
              (lib.optional
                (cfg.database.adminPasswordFile != null)
                "pg_admin_password:${cfg.database.adminPasswordFile}")
              ++ (lib.optional
                (cfg.database.passwordFile != null)
                "pg_user_password:${cfg.database.passwordFile}");
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail

            ${lib.optionalString (cfg.database.adminPasswordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_admin_password")"
            ''}

            role_exists="$(${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs "postgres")} -tAc "SELECT 1 FROM pg_roles WHERE rolname = '${cfg.database.user}'")"
            if [ "$role_exists" != "1" ]; then
              ${lib.optionalString (cfg.database.passwordFile != null) ''
              ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs "postgres")} \
                --set=role_pwd="$(< "$CREDENTIALS_DIRECTORY/pg_user_password")" \
                -c "CREATE ROLE \"${cfg.database.user}\" LOGIN PASSWORD :'role_pwd'"
            ''}
              ${lib.optionalString (cfg.database.passwordFile == null) ''
              ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs "postgres")} -c "CREATE ROLE \"${cfg.database.user}\" LOGIN"
            ''}
            fi
            ${lib.optionalString (cfg.database.passwordFile != null) ''
              if [ "$role_exists" = "1" ]; then
              ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs "postgres")} \
                --set=role_pwd="$(< "$CREDENTIALS_DIRECTORY/pg_user_password")" \
                -c "ALTER ROLE \"${cfg.database.user}\" WITH LOGIN PASSWORD :'role_pwd'"
              fi
            ''}

            db_exists="$(${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs "postgres")} -tAc "SELECT 1 FROM pg_database WHERE datname = '${cfg.database.name}'")"
            if [ "$db_exists" != "1" ]; then
              ${postgresqlPackage}/bin/createdb ${lib.escapeShellArgs createdbArgs} -O ${lib.escapeShellArg cfg.database.user} ${lib.escapeShellArg cfg.database.name}
            fi

            db_owner="$(${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs "postgres")} -tAc "SELECT pg_catalog.pg_get_userbyid(datdba) FROM pg_database WHERE datname = '${cfg.database.name}'")"
            if [ "$db_owner" != "${cfg.database.user}" ]; then
              ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs "postgres")} -c "ALTER DATABASE \"${cfg.database.name}\" OWNER TO \"${cfg.database.user}\""
            fi

            ${lib.optionalString cfg.database.createExtensions ''
              ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs cfg.database.name)} -c "CREATE EXTENSION IF NOT EXISTS postgis"
              ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs cfg.database.name)} -c "CREATE EXTENSION IF NOT EXISTS hstore"
            ''}

            ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs cfg.database.name)} -c "GRANT CONNECT, TEMP ON DATABASE \"${cfg.database.name}\" TO \"${cfg.database.user}\""

            ${lib.concatMapStringsSep "\n" (region: ''
                ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs cfg.database.name)} -c "CREATE SCHEMA IF NOT EXISTS \"${region.schema}\" AUTHORIZATION \"${cfg.database.user}\""
                ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs cfg.database.name)} -c "ALTER SCHEMA \"${region.schema}\" OWNER TO \"${cfg.database.user}\""
                ${postgresqlPackage}/bin/psql ${lib.escapeShellArgs (adminArgs cfg.database.name)} -c "GRANT USAGE, CREATE ON SCHEMA \"${region.schema}\" TO \"${cfg.database.user}\""
              '')
              enabledRegions}
          '';
        };
      })
      ++ (lib.optional cfg.updates.restartMartinOnSuccess {
        osm-mirror-restart-martin = {
          description = "Restart Martin after OSM mirror updates";

          serviceConfig = {
            Type = "oneshot";
            User = "root";
            Group = "root";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          script = ''
            set -euo pipefail
            ${pkgs.systemd}/bin/systemctl try-restart martin.service
          '';
        };
      })
      ++ map (region: {
        "osm-mirror-init-${region.unit}" = {
          description = "Initial OSM import (${region.name})";
          after = ["network-online.target"] ++ lib.optional cfg.database.createIfMissing "osm-mirror-prepare-db.service";
          wants = ["network-online.target"];
          wantedBy = lib.optional region.initOnBoot "multi-user.target";

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = region.stateDir;
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

            pbf_file="${region.stateDir}/region.osm.pbf"
            cleanup() {
              rm -f "$pbf_file" "$pbf_file.tmp"
            }
            trap cleanup EXIT

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}

            has_middle_table="$(${postgresqlPackage}/bin/psql -X -A -t ${lib.escapeShellArgs userPsqlArgs} -c "SELECT to_regclass('${region.schema}.${region.prefix}_ways') IS NOT NULL")"

            if [ "$has_middle_table" = "t" ]; then
              echo "Region ${region.name} already imported (found ${region.schema}.${region.prefix}_ways)."
            else
              ${pkgs.curl}/bin/curl --fail --location --retry 5 --output "$pbf_file.tmp" ${lib.escapeShellArg region.pbfUrl}
              mv "$pbf_file.tmp" "$pbf_file"

              ${cfg.package}/bin/osm2pgsql \
                --create \
                --slim \
                --output=flex \
                --style ${lib.escapeShellArg (toString region.styleFile)} \
                --cache ${toString cfg.import.cacheMB} \
                --number-processes ${toString cfg.import.numberProcesses} \
                ${lib.escapeShellArgs (dbArgs region)} \
                ${lib.escapeShellArgs cfg.import.extraArgs} \
                ${lib.escapeShellArgs region.extraImportArgs} \
                "$pbf_file"
            fi

            ${lib.optionalString (region.replicationUrl != null) ''
              ${cfg.package}/bin/osm2pgsql-replication init \
                ${lib.escapeShellArgs (dbArgs region)} \
                --server ${lib.escapeShellArg region.replicationUrl}
            ''}

          '';
        };

        "osm-mirror-update-${region.unit}" = {
          description = "OSM replication update (${region.name})";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          unitConfig = lib.optionalAttrs cfg.updates.restartMartinOnSuccess {
            OnSuccess = "osm-mirror-restart-martin.service";
          };

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = region.stateDir;
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

            ${lib.optionalString (cfg.database.passwordFile != null) ''
              export PGPASSWORD="$(< "$CREDENTIALS_DIRECTORY/pg_password")"
            ''}

            has_middle_table="$(${postgresqlPackage}/bin/psql -X -A -t ${lib.escapeShellArgs userPsqlArgs} -c "SELECT to_regclass('${region.schema}.${region.prefix}_ways') IS NOT NULL")"
            if [ "$has_middle_table" != "t" ]; then
              echo "Region ${region.name} not imported yet; skipping update."
              exit 0
            fi

            if ! ${cfg.package}/bin/osm2pgsql-replication status ${lib.escapeShellArgs (dbArgs region)} >/dev/null 2>&1; then
              echo "Replication for ${region.name} is not initialized yet; run osm-mirror-init-${region.unit}.service first."
              exit 0
            fi

            ${cfg.package}/bin/osm2pgsql-replication update \
              --once \
              --max-diff-size ${toString cfg.updates.maxDiffSizeMB} \
              --osm2pgsql-cmd ${lib.escapeShellArg "${cfg.package}/bin/osm2pgsql"} \
              ${lib.escapeShellArgs (dbArgs region)} \
              -- \
              --output=flex \
              --style ${lib.escapeShellArg (toString region.styleFile)} \
              --number-processes ${toString cfg.import.numberProcesses} \
              ${lib.escapeShellArgs cfg.updates.extraOsm2pgsqlArgs} \
              ${lib.escapeShellArgs region.extraUpdateArgs}
          '';
        };
      })
      enabledRegions
    );

    systemd.timers = lib.mkMerge (map (region:
      lib.mkIf (cfg.updates.enable && region.updatesEnable && region.replicationUrl != null) {
        "osm-mirror-update-${region.unit}" = {
          description = "Timer for OSM replication update (${region.name})";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar =
              if region.updateOnCalendar != null
              then region.updateOnCalendar
              else cfg.updates.onCalendar;
            Persistent = true;
            RandomizedDelaySec = cfg.updates.randomizedDelaySec;
            Unit = "osm-mirror-update-${region.unit}.service";
          };
        };
      })
    enabledRegions);
  };
}
