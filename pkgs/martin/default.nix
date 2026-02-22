{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchNpmDeps,
  npmHooks,
  pkg-config,
  openssl,
  nodejs,
  withWebUi ? false,
}: let
  version = "1.3.1";
  martinSrc = fetchFromGitHub {
    owner = "maplibre";
    repo = "martin";
    rev = "martin-v${version}";
    hash = "sha256-s96o0J/0z7ZIHNFdNnuJ0X3P6ZXJjhQ9c7ylYXPtOP0=";
  };
in
  rustPlatform.buildRustPackage (
    rec {
      pname = "martin";
      inherit version;

      src = martinSrc;

      cargoHash = "sha256-lPZE+jU7wJFm6BiGhkyhHZ7K+4sQF/9WbOPoNxnrsrQ=";

      nativeBuildInputs =
        [pkg-config]
        ++ lib.optionals withWebUi [
          nodejs
          npmHooks.npmConfigHook
        ];
      buildInputs = [openssl];
      cargoBuildFlags = ["-p" "martin"];
      buildNoDefaultFeatures = true;
      buildFeatures =
        [
          "postgres"
          "styles"
          "sprites"
          "fonts"
          "lambda"
          "mbtiles"
          "metrics"
          "pmtiles"
        ]
        ++ lib.optional withWebUi "webui";

      prePatch = lib.optionalString withWebUi ''
        # Nix build sandboxes don't provide /usr/bin/env; avoid cross-env wrapper.
        substituteInPlace martin/martin-ui/package.json \
          --replace-fail 'cross-env VITE_MARTIN_VERSION=$npm_package_version vite build' \
                         'VITE_MARTIN_VERSION=$npm_package_version node ./node_modules/vite/bin/vite.js build'
      '';

      # Build with explicit features. Martin 1.3.x webui invokes npm in build.rs,
      # so withWebUi=true requires npm (nodejs) at build time and may still fail in
      # strict/offline build environments.
      # Upstream package is marked broken in nixpkgs metadata, so we keep this
      # local package explicit and checks off for deployment reliability.
      doCheck = false;

      meta = with lib; {
        description = "Blazing fast and lightweight PostGIS vector tiles server";
        homepage = "https://martin.maplibre.org/";
        license = [licenses.mit licenses.asl20];
        platforms = platforms.unix;
        maintainers = with maintainers; [sikmir];
      };
    }
    // lib.optionalAttrs withWebUi {
      npmRoot = "martin/martin-ui";
      npmDeps = fetchNpmDeps {
        src = martinSrc;
        sourceRoot = "${martinSrc.name}/martin/martin-ui";
        hash = "sha256-1L4HiW3nYcCCy0ODGxb9ddxMWaVasQjxW+2+vKDJnDE=";
      };
      makeCacheWritable = true;
    }
  )
