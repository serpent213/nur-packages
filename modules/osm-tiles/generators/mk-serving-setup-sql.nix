{
  lib,
  locales,
  countrySchemas,
  dbUser,
  servingSchema ? "osm_serving",
  lowresSchema ? "osm_lowres",
}: let
  common = import ./common.nix {inherit lib;};
  inherit
    (common)
    localeColumns
    localeJsonExprs
    localeNullExprs
    quoteIdent
    sqlColumnList
    unionSql
    ;

  localeCols = localeColumns locales;

  mkCols = base: localeExprs: base ++ localeExprs;

  mkFromCountry = {
    table,
    alias,
    cols,
  }: schema: ''
    SELECT
      ${sqlColumnList cols}
    FROM ${quoteIdent schema}.${quoteIdent table} ${alias}
  '';

  mkEmptySelect = cols: ''
    SELECT
      ${sqlColumnList cols}
    WHERE FALSE
  '';

  mkCountryUnion = {
    table,
    alias,
    cols,
    emptyCols,
  }: let
    statements = map (mkFromCountry {inherit table alias cols;}) countrySchemas;
    merged = unionSql statements;
  in
    if merged == null
    then mkEmptySelect emptyCols
    else merged;

  landcoverCountryCols =
    mkCols ["c.class" "c.name"] (localeJsonExprs {
      alias = "c";
      inherit locales;
    })
    ++ ["c.geom"];

  waterCountryCols =
    mkCols ["w.class" "w.name"] (localeJsonExprs {
      alias = "w";
      inherit locales;
    })
    ++ ["w.geom"];

  boundaryCountryCols =
    mkCols ["b.class" "b.admin_level" "b.name"] (localeJsonExprs {
      alias = "b";
      inherit locales;
    })
    ++ ["b.geom"];

  placeCountryCols =
    mkCols ["p.class" "p.population" "p.name"] (localeJsonExprs {
      alias = "p";
      inherit locales;
    })
    ++ ["p.geom::geometry(Point,4326) AS geom"];

  landcoverCountrySql = mkCountryUnion {
    table = "landcover";
    alias = "c";
    cols = landcoverCountryCols;
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::text AS name"
      ]
      ++ localeNullExprs locales
      ++ ["NULL::geometry(Geometry,3857) AS geom"];
  };

  waterCountrySql = mkCountryUnion {
    table = "water";
    alias = "w";
    cols = waterCountryCols;
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::text AS name"
      ]
      ++ localeNullExprs locales
      ++ ["NULL::geometry(Geometry,3857) AS geom"];
  };

  boundaryCountrySql = mkCountryUnion {
    table = "boundary";
    alias = "b";
    cols = boundaryCountryCols;
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::integer AS admin_level"
        "NULL::text AS name"
      ]
      ++ localeNullExprs locales
      ++ ["NULL::geometry(Geometry,3857) AS geom"];
  };

  placeCountrySql = mkCountryUnion {
    table = "place";
    alias = "p";
    cols = placeCountryCols;
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::bigint AS population"
        "NULL::text AS name"
      ]
      ++ localeNullExprs locales
      ++ ["NULL::geometry(Point,4326) AS geom"];
  };

  localeNullColsList = lib.concatStringsSep ",\n  " (localeNullExprs locales);
  localeColsList = lib.concatStringsSep ", " localeCols;
  localeColsWithComma = lib.optionalString (localeCols != []) "${localeColsList}, ";
  localeSelectCols = lib.concatStringsSep ",\n      " localeCols;
  localeSelectColsPrefixed = lib.optionalString (localeCols != []) "      ${localeSelectCols},\n";

  placeSearchTextCols =
    ["coalesce(name, '')"]
    ++ map (col: "coalesce(${col}, '')") localeCols;
in ''
    BEGIN;

    CREATE SCHEMA IF NOT EXISTS ${quoteIdent servingSchema} AUTHORIZATION ${quoteIdent dbUser};
    CREATE SCHEMA IF NOT EXISTS ${quoteIdent lowresSchema} AUTHORIZATION ${quoteIdent dbUser};

    CREATE TABLE IF NOT EXISTS ${quoteIdent lowresSchema}.${quoteIdent "lowres_landcover"} (
      id bigserial PRIMARY KEY,
      geom geometry(MultiPolygon, 4326)
    );

    CREATE TABLE IF NOT EXISTS ${quoteIdent lowresSchema}.${quoteIdent "lowres_ocean"} (
      id bigserial PRIMARY KEY,
      geom geometry(MultiPolygon, 4326)
    );

    CREATE TABLE IF NOT EXISTS ${quoteIdent lowresSchema}.${quoteIdent "lowres_boundary"} (
      id bigserial PRIMARY KEY,
      name text,
      geom geometry(MultiPolygon, 4326)
    );

    CREATE TABLE IF NOT EXISTS ${quoteIdent lowresSchema}.${quoteIdent "lowres_place"} (
      id bigserial PRIMARY KEY,
      name text,
      geom geometry(Point, 4326)
    );

    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "place_zxy"}(integer, integer, integer);

    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "place_api"};

    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover_country"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_country"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary_country"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "place_country"};

    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "place"};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover_country"} AS
    ${landcoverCountrySql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "water_country"} AS
    ${waterCountrySql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "boundary_country"} AS
    ${boundaryCountrySql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "place_country"} AS
    ${placeCountrySql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover"} AS
    SELECT
      class,
      name,
      ${localeColsList}
      ${lib.optionalString (localeCols != []) ","}
      geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "landcover_country"}
    UNION ALL
    SELECT
      'land'::text AS class,
      NULL::text AS name
      ${lib.optionalString (localeCols != []) ","}
      ${localeNullColsList}
      ${lib.optionalString (localeCols != []) ","}
      ST_Transform(geom, 3857)::geometry AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_landcover"};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "water"} AS
    SELECT
      class,
      name,
      ${localeColsList}
      ${lib.optionalString (localeCols != []) ","}
      geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "water_country"}
    UNION ALL
    SELECT
      'ocean'::text AS class,
      NULL::text AS name
      ${lib.optionalString (localeCols != []) ","}
      ${localeNullColsList}
      ${lib.optionalString (localeCols != []) ","}
      ST_Transform(geom, 3857)::geometry AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_ocean"};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "boundary"} AS
    SELECT
      class,
      admin_level,
      name,
      ${localeColsList}
      ${lib.optionalString (localeCols != []) ","}
      geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "boundary_country"}
    UNION ALL
    SELECT
      'administrative'::text AS class,
      2::integer AS admin_level,
      lowres.name::text AS name
      ${lib.optionalString (localeCols != []) ","}
      ${localeNullColsList}
      ${lib.optionalString (localeCols != []) ","}
      ST_CollectionExtract(ST_Boundary(ST_Transform(lowres.geom, 3857)), 2)::geometry AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_boundary"} AS lowres;

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "place"} AS
    SELECT
      class,
      population,
      name,
      ${localeColsList}
      ${lib.optionalString (localeCols != []) ","}
      geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "place_country"}
    UNION ALL
    SELECT
      'country'::text AS class,
      NULL::bigint AS population,
      lowres.name::text AS name
      ${lib.optionalString (localeCols != []) ","}
      ${localeNullColsList}
      ${lib.optionalString (localeCols != []) ","}
      ST_PointOnSurface(ST_Transform(lowres.geom, 4326))::geometry(Point,4326) AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_boundary"} AS lowres
    UNION ALL
    SELECT
      'city'::text AS class,
      NULL::bigint AS population,
      lowres.name::text AS name
      ${lib.optionalString (localeCols != []) ","}
      ${localeNullColsList}
      ${lib.optionalString (localeCols != []) ","}
      ST_PointOnSurface(ST_Transform(lowres.geom, 4326))::geometry(Point,4326) AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_place"} AS lowres;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"} AS
    SELECT
      class,
      name,
      ${localeColsList}
      ${lib.optionalString (localeCols != []) ","}
      ST_Multi(ST_SimplifyPreserveTopology(geom, 20000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "landcover"}
    WHERE ST_Area(geom) > 500000000
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"} AS
    SELECT
      class,
      name,
      ${localeColsList}
      ${lib.optionalString (localeCols != []) ","}
      ST_Multi(ST_SimplifyPreserveTopology(geom, 12000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "water"}
    WHERE ST_Area(geom) > 100000000
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"} AS
    SELECT
      class,
      admin_level,
      name,
      ${localeColsList}
      ${lib.optionalString (localeCols != []) ","}
      ST_Multi(ST_SimplifyPreserveTopology(geom, 12000))::geometry(MultiLineString,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "boundary"}
    WHERE admin_level <= 4
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "place_api"} AS
    SELECT
      class,
      population,
      name,
      ${localeColsList}
      ${lib.optionalString (localeCols != []) ","}
      geom,
      lower(concat_ws(' ', ${lib.concatStringsSep ", " placeSearchTextCols})) AS search_text
    FROM ${quoteIdent servingSchema}.${quoteIdent "place"}
    WITH DATA;

    CREATE INDEX IF NOT EXISTS landcover_low_z5_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS water_low_z5_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS boundary_low_z5_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS place_api_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "place_api"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS place_api_search_idx ON ${quoteIdent servingSchema}.${quoteIdent "place_api"} USING GIN (to_tsvector('simple', search_text));

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "landcover_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          l.class,
          l.name,
  ${localeSelectColsPrefixed}        ST_AsMVTGeom(l.geom, b.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, name, ${localeColsWithComma}geom FROM ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"} WHERE z <= 5
          UNION ALL
          SELECT class, name, ${localeColsWithComma}geom FROM ${quoteIdent servingSchema}.${quoteIdent "landcover"} WHERE z > 5
        ) l
        CROSS JOIN bounds b
        WHERE l.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'landcover', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "water_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          w.class,
          w.name,
  ${localeSelectColsPrefixed}        ST_AsMVTGeom(w.geom, b.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, name, ${localeColsWithComma}geom FROM ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"} WHERE z <= 5
          UNION ALL
          SELECT class, name, ${localeColsWithComma}geom FROM ${quoteIdent servingSchema}.${quoteIdent "water"} WHERE z > 5
        ) w
        CROSS JOIN bounds b
        WHERE w.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'water', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "boundary_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          b.class,
          b.admin_level,
          b.name,
  ${localeSelectColsPrefixed}        ST_AsMVTGeom(b.geom, t.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, admin_level, name, ${localeColsWithComma}geom FROM ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"} WHERE z <= 5
          UNION ALL
          SELECT class, admin_level, name, ${localeColsWithComma}geom FROM ${quoteIdent servingSchema}.${quoteIdent "boundary"} WHERE z > 5
        ) b
        CROSS JOIN bounds t
        WHERE b.geom && t.geom
      )
      SELECT ST_AsMVT(src, 'boundary', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "place_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          p.class,
          p.population,
          p.name,
  ${localeSelectColsPrefixed}        ST_AsMVTGeom(ST_Transform(p.geom, 3857), b.geom, 4096, 64, true) AS geom
        FROM ${quoteIdent servingSchema}.${quoteIdent "place"} p
        CROSS JOIN bounds b
        WHERE ST_Transform(p.geom, 3857) && b.geom
      )
      SELECT ST_AsMVT(src, 'place', 4096, 'geom') FROM src;
    $$;

    COMMIT;
''
