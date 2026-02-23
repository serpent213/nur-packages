{
  lib,
  pkgs,
  testers,
}: let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  neSqliteZip = pkgs.fetchurl {
    url = "https://dev.maptiler.download/geodata/omt/natural_earth_vector.sqlite_v5.1.2.zip";
    sha256 = "0akfmcyiwbcgyhizvza6i3y35h8hczf9cd0kqxw5yfksnqfb4if8";
  };
  waterPolygonsZip = pkgs.fetchurl {
    url = "http://osmdata.openstreetmap.de/download/water-polygons-split-3857.zip";
    sha256 = "1m0pg0888x8qaa8dwbgkv82l7ff9i5s53mi0nhsq82ix3p83fa4q";
  };

  tilesetYaml = pkgs.writeText "osm-tiles-test-tileset.yaml" (
    import ../../modules/osm-tiles/generators/mk-openmaptiles-tileset.nix {
      inherit lib;
      locales = [
        "en"
        "de"
      ];
    }
  );

  martinYaml = pkgs.writeText "osm-tiles-test-martin.yaml" (
    import ../../modules/osm-tiles/generators/mk-martin-yaml.nix {
      inherit lib;
      routePrefix = "/maptiles";
      connectionString = "postgresql://osm_maps@127.0.0.1:5432/osm_maps?sslmode=disable";
      poolSize = 20;
      workerProcesses = 2;
      schema = "public";
    }
  );

  moduleSmoke =
    if isLinux
    then
      testers.runNixOSTest {
        name = "osm-tiles-module-smoke";

        nodes.machine = {pkgs, ...}: {
          imports = [../../modules/osm-tiles];

          virtualisation = {
            memorySize = 2048;
            cores = 2;
          };

          services.osmTiles = {
            enable = true;

            components = {
              osmImport.enable = false;
              osmUpdate.enable = false;
              martin.enable = false;
              nginx.enable = false;
              sampleClient.enable = false;
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
          };

          documentation.enable = false;
        };

        testScript = ''
          start_all()
          machine.wait_for_unit("postgresql.service")
          machine.wait_for_unit("osm-tiles-prepare-db.service")
        '';
      }
    else
      pkgs.runCommand "osm-tiles-module-smoke-skipped" {} ''
        mkdir -p "$out"
        echo "Skipped on non-Linux host platform: ${pkgs.stdenv.hostPlatform.system}" > "$out/reason"
      '';

  moduleE2E =
    if isLinux
    then
      testers.runNixOSTest {
        name = "osm-tiles-module-e2e";

        nodes.machine = {pkgs, ...}: {
          imports = [../../modules/osm-tiles];

          virtualisation = {
            diskSize = 32768;
            memorySize = 8192;
            cores = 4;
          };

          environment.systemPackages = [
            pkgs.binutils
            pkgs.curl
            pkgs.file
            pkgs.gnugrep
          ];

          services.osmTiles = {
            enable = true;

            source = {
              naturalEarthSqliteUrl = "file://${neSqliteZip}";
              waterPolygonsUrl = "file://${waterPolygonsZip}";
            };

            data = {
              locales = ["en"];
              countries = {};
            };

            components = {
              osmImport.enable = true;
              osmUpdate.enable = true;
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
              managed.ramMB = 4096;
            };
          };

          documentation.enable = false;
        };

        testScript = ''
          start_all()

          machine.wait_for_unit("postgresql.service")
          machine.wait_for_unit("osm-tiles-prepare-db.service")
          machine.succeed("systemctl start --wait osm-tiles-import-external.service")
          machine.succeed("systemctl start --wait osm-tiles-osm-import.service")
          machine.succeed("systemctl start --wait osm-tiles-sql-import.service")

          machine.succeed("systemctl start --wait osm-tiles-serving-refresh.service")

          machine.wait_for_unit("martin.service")
          machine.wait_for_unit("nginx.service")
          machine.wait_for_open_port(3000)
          machine.wait_for_open_port(8080)

          machine.succeed("${pkgs.curl}/bin/curl -fsS http://127.0.0.1:8080/ | ${pkgs.gnugrep}/bin/grep -F 'Sample MapLibre Client'")

          machine.succeed("${pkgs.curl}/bin/curl -fsS -H 'Accept: application/x-protobuf' -o /tmp/tile-z2-x2-y1.mvt http://127.0.0.1:8080/maptiles/landcover,water,boundary,place/2/2/1")
          machine.succeed("test -s /tmp/tile-z2-x2-y1.mvt")
          machine.succeed("${pkgs.file}/bin/file --brief --mime-type /tmp/tile-z2-x2-y1.mvt | ${pkgs.gnugrep}/bin/grep -E 'application/(octet-stream|vnd.mapbox-vector-tile|x-protobuf)'")
          machine.succeed("${pkgs.gnugrep}/bin/grep -aE 'name_en|name:en' /tmp/tile-z2-x2-y1.mvt")
        '';
      }
    else
      pkgs.runCommand "osm-tiles-module-e2e-skipped" {} ''
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
            diskSize = 12288;
            memorySize = 2048;
            cores = 2;
            docker.enable = true;
          };

          environment.systemPackages = [
            pkgs.docker
            pkgs.jq
          ];
        };

        testScript = ''
          start_all()
          docker.wait_for_unit("docker.service")
          docker.succeed("docker load --input='${pkgs.callPackage ../osm-tiles-demo {}}'")
          docker.succeed("docker image inspect osm-tiles-demo:latest | ${pkgs.jq}/bin/jq -e '.[0].Config.ExposedPorts[\"8080/tcp\"] == {}'")
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
        moduleE2E
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

    ${pkgs.gnugrep}/bin/grep -F 'id: openmaptiles_minimal' ${tilesetYaml}
    ${pkgs.gnugrep}/bin/grep -F '    - en' ${tilesetYaml}
    ${pkgs.gnugrep}/bin/grep -F '    - de' ${tilesetYaml}

    ${pkgs.gnugrep}/bin/grep -F '"route_prefix":"/maptiles"' ${martinYaml}
    ${pkgs.gnugrep}/bin/grep -F '"function":"landcover_zxy"' ${martinYaml}

    touch "$out"
  ''
