{
  lib,
  stdenvNoCC,
  fetchgit,
  makeWrapper,
  python3,
}: let
  python = python3.withPackages (ps:
    with ps; [
      asyncpg
      beautifulsoup4
      betterproto
      dataclasses-json
      deprecated
      docopt-ng
      psycopg2
      pyyaml
      requests
      tabulate
      tornado
      aiohttp
    ]);
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "openmaptiles-tools";
    version = "1.11.0";

    src = fetchgit {
      url = "https://github.com/openmaptiles/openmaptiles-tools.git";
      rev = "9c47b03a7d78118ff81f5a8b01c422639ac6b219";
      hash = "sha256-E95PMiTszsl4aY98qRznl5ySBSgqA8pNmtIKtA6cd8g=";
    };

    nativeBuildInputs = [
      makeWrapper
      python
    ];
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
            runHook preInstall

            mkdir -p "$out/bin" "$out/lib" "$out/sql"
            cp -r openmaptiles "$out/lib/openmaptiles"
            cp -r sql/* "$out/sql/"
            cat > "$out/lib/ascii_graph.py" <<'PY'
      class Pyasciigraph:
          def graph(self, *_args, **_kwargs):
              return []
      PY
            patchShebangs bin

            for script in bin/*; do
              if [ ! -f "$script" ]; then
                continue
              fi
              target="$out/bin/$(basename "$script")"
              cp "$script" "$target"
              chmod +x "$target"
              wrapProgram "$target" \
                --prefix PATH : "${lib.makeBinPath [python]}" \
                --set PYTHONPATH "$out/lib"
            done

            runHook postInstall
    '';

    meta = {
      description = "OpenMapTiles tooling for generating imposm mappings and SQL from tileset YAML";
      homepage = "https://github.com/openmaptiles/openmaptiles-tools";
      license = lib.licenses.mit;
      maintainers = with lib.maintainers; [serpent213];
      platforms = lib.platforms.unix;
      mainProgram = "generate-sql";
    };
  })
