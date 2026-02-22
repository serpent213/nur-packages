{
  lib,
  pkgs,
  testers,
}: let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;

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
