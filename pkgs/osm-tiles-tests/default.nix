{
  lib,
  pkgs,
  testers,
}: let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

  flexLua = import ../../modules/osm-tiles/generators/mk-flex-lua.nix {
    inherit
      lib
      pkgs
      ;
    locales = [
      "en"
      "de"
    ];
    profile = "compact";
  };

  flexLuaOpenmaptiles = import ../../modules/osm-tiles/generators/mk-flex-lua.nix {
    inherit
      lib
      pkgs
      ;
    locales = ["en"];
    profile = "openmaptiles";
  };

  setupSqlNoCountries = pkgs.writeText "osm-tiles-test-setup-no-countries.sql" (
    import ../../modules/osm-tiles/generators/mk-serving-setup-sql.nix {
      inherit lib;
      locales = [
        "en"
        "de"
      ];
      countrySchemas = [];
      dbUser = "osm_maps";
      servingSchema = "osm_serving";
      lowresSchema = "osm_lowres";
      profile = "compact";
    }
  );

  setupSqlOneCountry = pkgs.writeText "osm-tiles-test-setup-one-country.sql" (
    import ../../modules/osm-tiles/generators/mk-serving-setup-sql.nix {
      inherit lib;
      locales = [
        "en"
        "de"
      ];
      countrySchemas = ["osm_germany"];
      dbUser = "osm_maps";
      servingSchema = "osm_serving";
      lowresSchema = "osm_lowres";
      profile = "compact";
    }
  );

  setupSqlOpenmaptiles = pkgs.writeText "osm-tiles-test-setup-openmaptiles.sql" (
    import ../../modules/osm-tiles/generators/mk-serving-setup-sql.nix {
      inherit lib;
      locales = ["en"];
      countrySchemas = ["osm_germany"];
      dbUser = "osm_maps";
      servingSchema = "osm_serving";
      lowresSchema = "osm_lowres";
      profile = "openmaptiles";
    }
  );

  martinYaml = pkgs.writeText "osm-tiles-test-martin.yaml" (
    import ../../modules/osm-tiles/generators/mk-martin-yaml.nix {
      inherit lib;
      routePrefix = "/maptiles";
      connectionString = "postgresql://osm_maps@/osm_maps?host=/run/postgresql&sslmode=disable";
      poolSize = 40;
      workerProcesses = 5;
      servingSchema = "osm_serving";
      profile = "compact";
    }
  );

  martinYamlOpenmaptiles = pkgs.writeText "osm-tiles-test-martin-openmaptiles.yaml" (
    import ../../modules/osm-tiles/generators/mk-martin-yaml.nix {
      inherit lib;
      routePrefix = "/maptiles";
      connectionString = "postgresql://osm_maps@/osm_maps?host=/run/postgresql&sslmode=disable";
      poolSize = 40;
      workerProcesses = 5;
      servingSchema = "osm_serving";
      profile = "openmaptiles";
    }
  );

  moduleSmoke =
    if isLinux
    then
      testers.runNixOSTest {
        name = "osm-tiles-module-smoke";

        nodes.machine = {pkgs, ...}: {
          imports = [../../modules/osm-tiles];

          # Keep the VM test deterministic: no external fetches.
          services.osmTiles = {
            enable = true;

            data = {
              locales = ["en"];
              countries = {};
            };

            components = {
              osm2pgsqlImport.enable = false;
              osm2pgsqlUpdate.enable = false;
              martin.enable = true;
              nginx.enable = true;
              sampleClient.enable = true;
            };

            jobs = {
              osmUpdate.enable = false;
              neUpdate.enable = false;
              servingRefresh.enable = false;
            };

            database = {
              mode = "managed";
              managed.ramMB = 1024;
            };

            martin.listenAddresses = ["127.0.0.1:3000"];

            nginx = {
              listenAddress = "127.0.0.1";
              listenPort = 8080;
              serverName = "_";
            };
          };

          documentation.enable = false;
        };

        testScript = ''
          start_all()

          machine.wait_for_unit("postgresql.service")
          machine.wait_for_unit("osm-tiles-serving-setup.service")
          machine.wait_for_unit("martin.service")

          machine.wait_for_open_port(3000)
          machine.wait_for_open_port(8080)

          machine.succeed("${pkgs.curl}/bin/curl -fsS http://127.0.0.1:8080/ | ${pkgs.gnugrep}/bin/grep -F 'Sample MapLibre Client'")
          machine.succeed("${pkgs.curl}/bin/curl -fsS -o /tmp/tile.mvt http://127.0.0.1:8080/maptiles/landcover,water,boundary,place/0/0/0")
        '';
      }
    else
      pkgs.runCommand "osm-tiles-module-smoke-skipped" {} ''
        mkdir -p "$out"
        echo "Skipped on non-Linux host platform: ${pkgs.stdenv.hostPlatform.system}" > "$out/reason"
      '';

  dockerSmoke =
    if isLinux
    then
      testers.runNixOSTest {
        name = "osm-tiles-docker-smoke";

        nodes.docker = {pkgs, ...}: {
          virtualisation = {
            diskSize = 6144;
            docker.enable = true;
          };

          environment.systemPackages = [
            pkgs.curl
            pkgs.gnugrep
          ];
        };

        testScript = ''
          start_all()

          docker.wait_for_unit("docker.service")

          docker.succeed("docker load --input='${pkgs.callPackage ../osm-tiles-demo {}}'")

          docker.succeed("docker run -d --rm --name osmtiles -p 18080:8080 -e OSM_TILES_SKIP_NE_DOWNLOAD=1 osm-tiles-demo:latest")

          docker.wait_until_succeeds("${pkgs.curl}/bin/curl -fsS http://127.0.0.1:18080/ | ${pkgs.gnugrep}/bin/grep -F 'Sample MapLibre Client'", timeout=240)
          docker.succeed("${pkgs.curl}/bin/curl -fsS -o /tmp/tile.mvt http://127.0.0.1:18080/maptiles/landcover,water,boundary,place/0/0/0")

          docker.succeed("docker rm -f osmtiles")
        '';
      }
    else
      pkgs.runCommand "osm-tiles-docker-smoke-skipped" {} ''
        mkdir -p "$out"
        echo "Skipped on non-Linux host platform: ${pkgs.stdenv.hostPlatform.system}" > "$out/reason"
      '';
in
  pkgs.runCommand "osm-tiles-tests-quick"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    passthru.tests = {
      inherit
        dockerSmoke
        moduleSmoke
        ;
    };
    meta = {
      description = "Quick and integration tests for osmTiles module and docker demo";
      platforms = lib.platforms.all;
      maintainers = with lib.maintainers; [serpent213];
    };
  } ''
    set -euo pipefail

    ${pkgs.gnugrep}/bin/grep -F 'local locale_codes = { "en", "de" }' ${flexLua}
    ${pkgs.gnugrep}/bin/grep -F 'tables.transportation = osm2pgsql.define_table({' ${flexLuaOpenmaptiles}

    ${pkgs.gnugrep}/bin/grep -F 'AS name_en' ${setupSqlNoCountries}
    ${pkgs.gnugrep}/bin/grep -F 'AS name_de' ${setupSqlNoCountries}
    ${pkgs.gnugrep}/bin/grep -F 'WHERE FALSE' ${setupSqlNoCountries}

    ${pkgs.gnugrep}/bin/grep -F 'FROM "osm_germany"."landcover" c' ${setupSqlOneCountry}
    ${pkgs.gnugrep}/bin/grep -F 'CREATE OR REPLACE VIEW "osm_serving"."transportation"' ${setupSqlOpenmaptiles}
    ${pkgs.gnugrep}/bin/grep -F 'CREATE MATERIALIZED VIEW "osm_serving"."transportation_low_z7"' ${setupSqlOpenmaptiles}

    ${pkgs.gnugrep}/bin/grep -F '"route_prefix":"/maptiles"' ${martinYaml}
    ${pkgs.gnugrep}/bin/grep -F '"transportation":{"bounds"' ${martinYamlOpenmaptiles}

    touch "$out"
  ''
