{
  lib,
  countrySchemas,
  dbUser,
  servingSchema ? "osm_serving",
  lowresSchema ? "osm_lowres",
}: let
  common = import ./common.nix {inherit lib;};
  inherit
    (common)
    quoteIdent
    sqlColumnList
    unionSql
    ;

  nameCols = [
    "name"
    "name_de"
    "name_en"
    "name_fr"
    "\"name:latin\""
    "\"name:nonlatin\""
  ];

  nameColsCsv = lib.concatStringsSep ", " nameCols;
  nameColsPref = alias: map (col: "${alias}.${col}") nameCols;
  nameNullExprs = map (col: "NULL::text AS ${col}") nameCols;
  nameNullList = lib.concatStringsSep ",\n  " nameNullExprs;
  nameSelect = lib.concatStringsSep ",\n      " nameCols;
  nameSelectPrefixed = "      ${nameSelect},\n";

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

  landcoverHighresSql = mkCountryUnion {
    table = "landcover";
    alias = "c";
    cols = ["c.class" "c.subclass" "c.minzoom"] ++ nameColsPref "c" ++ ["c.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::text AS subclass"
        "NULL::integer AS minzoom"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  landuseSql = mkCountryUnion {
    table = "landuse";
    alias = "l";
    cols = ["l.class" "l.minzoom"] ++ nameColsPref "l" ++ ["l.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::integer AS minzoom"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  parkSql = mkCountryUnion {
    table = "park";
    alias = "p";
    cols = ["p.class"] ++ nameColsPref "p" ++ ["p.geom"];
    emptyCols =
      [
        "NULL::text AS class"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  waterInlandSql = mkCountryUnion {
    table = "water";
    alias = "w";
    cols = ["w.class" "w.brunnel"] ++ nameColsPref "w" ++ ["w.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::text AS brunnel"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  waterwaySql = mkCountryUnion {
    table = "waterway";
    alias = "w";
    cols = ["w.class" "w.minzoom" "w.intermittent"] ++ nameColsPref "w" ++ ["w.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::integer AS minzoom"
        "NULL::boolean AS intermittent"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  boundaryHighresSql = mkCountryUnion {
    table = "boundary";
    alias = "b";
    cols =
      [
        "b.class"
        "b.minzoom"
        "b.admin_level"
        "b.claimed_by"
        "b.disputed"
        "b.maritime"
      ]
      ++ nameColsPref "b" ++ ["b.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::integer AS minzoom"
        "NULL::integer AS admin_level"
        "NULL::text AS claimed_by"
        "NULL::boolean AS disputed"
        "NULL::boolean AS maritime"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  transportationSql = mkCountryUnion {
    table = "transportation";
    alias = "t";
    cols =
      [
        "t.class"
        "t.minzoom"
        "t.subclass"
        "t.brunnel"
        "t.service"
        "t.oneway"
        "t.network"
        "t.expressway"
        "t.surface"
        "t.access"
        "t.toll"
        "t.bicycle"
        "t.foot"
        "t.horse"
        "t.mtb_scale"
        "t.layer"
        "t.level"
        "t.indoor"
      ]
      ++ nameColsPref "t" ++ ["t.ref" "t.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::integer AS minzoom"
        "NULL::text AS subclass"
        "NULL::text AS brunnel"
        "NULL::text AS service"
        "NULL::integer AS oneway"
        "NULL::text AS network"
        "NULL::boolean AS expressway"
        "NULL::text AS surface"
        "NULL::text AS access"
        "NULL::boolean AS toll"
        "NULL::text AS bicycle"
        "NULL::text AS foot"
        "NULL::text AS horse"
        "NULL::text AS mtb_scale"
        "NULL::integer AS layer"
        "NULL::text AS level"
        "NULL::boolean AS indoor"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::text AS ref"
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  aerowaySql = mkCountryUnion {
    table = "aeroway";
    alias = "a";
    cols = ["a.class" "a.ref" "a.iata"] ++ nameColsPref "a" ++ ["a.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::text AS ref"
        "NULL::text AS iata"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  transportationNameSql = mkCountryUnion {
    table = "transportation_name";
    alias = "t";
    cols =
      [
        "t.class"
        "t.minzoom"
        "t.subclass"
        "t.network"
        "t.layer"
        "t.level"
        "t.indoor"
      ]
      ++ nameColsPref "t" ++ ["t.ref" "t.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::integer AS minzoom"
        "NULL::text AS subclass"
        "NULL::text AS network"
        "NULL::integer AS layer"
        "NULL::text AS level"
        "NULL::boolean AS indoor"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::text AS ref"
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  buildingSql = mkCountryUnion {
    table = "building";
    alias = "b";
    cols = ["b.class"] ++ nameColsPref "b" ++ ["b.geom"];
    emptyCols =
      [
        "NULL::text AS class"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  waterNameSql = mkCountryUnion {
    table = "water_name";
    alias = "w";
    cols = ["w.class" "w.minzoom"] ++ nameColsPref "w" ++ ["w.geom"];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::integer AS minzoom"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::geometry(Geometry,3857) AS geom"
      ];
  };

  placeHighresSql = mkCountryUnion {
    table = "place";
    alias = "p";
    cols =
      ["p.class" "p.minzoom"]
      ++ nameColsPref "p"
      ++ [
        "p.population"
        "p.rank"
        "p.capital"
        "p.iso_a2"
        "p.geom::geometry(Point,4326) AS geom"
      ];
    emptyCols =
      [
        "NULL::text AS class"
        "NULL::integer AS minzoom"
      ]
      ++ nameNullExprs
      ++ [
        "NULL::bigint AS population"
        "NULL::integer AS rank"
        "NULL::integer AS capital"
        "NULL::text AS iso_a2"
        "NULL::geometry(Point,4326) AS geom"
      ];
  };

  placeSearchTextCols = ["coalesce(name, '')"] ++ map (col: "coalesce(${col}, '')") (builtins.tail nameCols);
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

    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "transportation_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "transportation_name_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landuse_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "park_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "waterway_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_name_zxy"}(integer, integer, integer);
    DROP FUNCTION IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "place_zxy"}(integer, integer, integer);

    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "transportation_low_z7"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "transportation_low_z9"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z8"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z7"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z9"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landuse_low_z7"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landuse_low_z9"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "park_low_z7"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "park_low_z9"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_low_z7"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_low_z9"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "waterway_low_z7"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "waterway_low_z9"};
    DROP MATERIALIZED VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "place_api"};

    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "aeroway"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "place"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_name"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "building"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "transportation_name"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "transportation"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "boundary_highres"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "waterway"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_ocean"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "water_inland"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "park"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landuse"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover"};
    DROP VIEW IF EXISTS ${quoteIdent servingSchema}.${quoteIdent "landcover_highres"};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover_highres"} AS
    ${landcoverHighresSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover"} AS
    SELECT class, subclass, minzoom, ${nameColsCsv}, geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "landcover_highres"}
    UNION ALL
    SELECT
      'land'::text AS class,
      NULL::text AS subclass,
      0::integer AS minzoom,
      ${nameNullList},
      ST_Transform(geom, 3857)::geometry AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_landcover"};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "landuse"} AS
    ${landuseSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "park"} AS
    ${parkSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "water_inland"} AS
    ${waterInlandSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "water_ocean"} AS
    SELECT
      'ocean'::text AS class,
      NULL::text AS brunnel,
      ${nameNullList},
      ST_Transform(geom, 3857)::geometry AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_ocean"};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "water"} AS
    SELECT class, brunnel, ${nameColsCsv}, geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "water_inland"}
    UNION ALL
    SELECT class, brunnel, ${nameColsCsv}, geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "water_ocean"};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "waterway"} AS
    ${waterwaySql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "boundary_highres"} AS
    ${boundaryHighresSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "boundary"} AS
    SELECT class, minzoom, admin_level, claimed_by, disputed, maritime, ${nameColsCsv}, geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "boundary_highres"}
    UNION ALL
    SELECT
      'administrative'::text AS class,
      0::integer AS minzoom,
      2::integer AS admin_level,
      NULL::text AS claimed_by,
      false::boolean AS disputed,
      false::boolean AS maritime,
      lowres.name::text AS name,
      NULL::text AS name_de,
      NULL::text AS name_en,
      NULL::text AS name_fr,
      lowres.name::text AS "name:latin",
      NULL::text AS "name:nonlatin",
      ST_CollectionExtract(ST_Boundary(ST_Transform(lowres.geom, 3857)), 2)::geometry AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_boundary"} AS lowres;

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "transportation"} AS
    ${transportationSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "aeroway"} AS
    ${aerowaySql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "transportation_name"} AS
    ${transportationNameSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "building"} AS
    ${buildingSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "water_name"} AS
    ${waterNameSql};

    CREATE OR REPLACE VIEW ${quoteIdent servingSchema}.${quoteIdent "place"} AS
    SELECT class, minzoom, ${nameColsCsv}, population, rank, capital, iso_a2, geom::geometry(Point,4326) AS geom
    FROM (
      ${placeHighresSql}
    ) place_highres
    UNION ALL
    SELECT
      'country'::text AS class,
      0::integer AS minzoom,
      lowres.name::text AS name,
      NULL::text AS name_de,
      NULL::text AS name_en,
      NULL::text AS name_fr,
      lowres.name::text AS "name:latin",
      NULL::text AS "name:nonlatin",
      NULL::bigint AS population,
      2::integer AS rank,
      NULL::integer AS capital,
      NULL::text AS iso_a2,
      ST_PointOnSurface(ST_Transform(lowres.geom, 4326))::geometry(Point,4326) AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_boundary"} AS lowres
    UNION ALL
    SELECT
      'city'::text AS class,
      6::integer AS minzoom,
      lowres.name::text AS name,
      NULL::text AS name_de,
      NULL::text AS name_en,
      NULL::text AS name_fr,
      lowres.name::text AS "name:latin",
      NULL::text AS "name:nonlatin",
      NULL::bigint AS population,
      6::integer AS rank,
      NULL::integer AS capital,
      NULL::text AS iso_a2,
      ST_PointOnSurface(ST_Transform(lowres.geom, 4326))::geometry(Point,4326) AS geom
    FROM ${quoteIdent lowresSchema}.${quoteIdent "lowres_place"} AS lowres;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "place_api"} AS
    SELECT
      class,
      minzoom,
      population,
      rank,
      capital,
      iso_a2,
      name,
      name_de,
      name_en,
      name_fr,
      "name:latin",
      "name:nonlatin",
      geom::geometry(Point,4326) AS geom,
      lower(concat_ws(' ', ${lib.concatStringsSep ", " placeSearchTextCols})) AS search_text
    FROM ${quoteIdent servingSchema}.${quoteIdent "place"}
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "transportation_low_z7"} AS
    SELECT
      class,
      minzoom,
      subclass,
      brunnel,
      service,
      oneway,
      network,
      expressway,
      surface,
      access,
      toll,
      bicycle,
      foot,
      horse,
      mtb_scale,
      layer,
      level,
      indoor,
      ${nameColsCsv},
      ref,
      ST_Multi(ST_CollectionExtract(ST_SimplifyPreserveTopology(geom, 160), 2))::geometry(MultiLineString,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "transportation"}
    WHERE minzoom <= 7 AND ST_Length(geom) >= 120
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "transportation_low_z9"} AS
    SELECT
      class,
      minzoom,
      subclass,
      brunnel,
      service,
      oneway,
      network,
      expressway,
      surface,
      access,
      toll,
      bicycle,
      foot,
      horse,
      mtb_scale,
      layer,
      level,
      indoor,
      ${nameColsCsv},
      ref,
      ST_Multi(ST_CollectionExtract(ST_SimplifyPreserveTopology(geom, 64), 2))::geometry(MultiLineString,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "transportation"}
    WHERE minzoom <= 9
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"} AS
    SELECT
      class,
      minzoom,
      admin_level,
      claimed_by,
      disputed,
      maritime,
      ${nameColsCsv},
      ST_Multi(ST_CollectionExtract(ST_SimplifyPreserveTopology(geom, 2000), 2))::geometry(MultiLineString,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "boundary"}
    WHERE minzoom <= 5 OR admin_level <= 4
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z8"} AS
    SELECT
      class,
      minzoom,
      admin_level,
      claimed_by,
      disputed,
      maritime,
      ${nameColsCsv},
      ST_Multi(ST_CollectionExtract(ST_SimplifyPreserveTopology(geom, 600), 2))::geometry(MultiLineString,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "boundary"}
    WHERE minzoom <= 8
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"} AS
    SELECT
      class,
      subclass,
      minzoom,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 20000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "landcover"}
    WHERE minzoom <= 5 OR ST_Area(geom) > 500000000
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z7"} AS
    SELECT
      class,
      subclass,
      minzoom,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 6000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "landcover"}
    WHERE minzoom <= 7
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z9"} AS
    SELECT
      class,
      subclass,
      minzoom,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 1200))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "landcover"}
    WHERE minzoom <= 9
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "landuse_low_z7"} AS
    SELECT
      class,
      minzoom,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 3000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "landuse"}
    WHERE minzoom <= 7
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "landuse_low_z9"} AS
    SELECT
      class,
      minzoom,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 800))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "landuse"}
    WHERE minzoom <= 9
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "park_low_z7"} AS
    SELECT
      class,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 2000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "park"}
    WHERE ST_Area(geom) > 500000
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "park_low_z9"} AS
    SELECT
      class,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 500))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "park"}
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"} AS
    SELECT
      class,
      brunnel,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 12000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "water"}
    WHERE ST_Area(geom) > 100000000
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "water_low_z7"} AS
    SELECT
      class,
      brunnel,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 4000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "water"}
    WHERE ST_Area(geom) > 20000000
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "water_low_z9"} AS
    SELECT
      class,
      brunnel,
      ${nameColsCsv},
      ST_Multi(ST_SimplifyPreserveTopology(geom, 1000))::geometry(MultiPolygon,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "water"}
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "waterway_low_z7"} AS
    SELECT
      class,
      minzoom,
      intermittent,
      ${nameColsCsv},
      ST_Multi(ST_CollectionExtract(ST_SimplifyPreserveTopology(geom, 160), 2))::geometry(MultiLineString,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "waterway"}
    WHERE minzoom <= 7
    WITH DATA;

    CREATE MATERIALIZED VIEW ${quoteIdent servingSchema}.${quoteIdent "waterway_low_z9"} AS
    SELECT
      class,
      minzoom,
      intermittent,
      ${nameColsCsv},
      ST_Multi(ST_CollectionExtract(ST_SimplifyPreserveTopology(geom, 80), 2))::geometry(MultiLineString,3857) AS geom
    FROM ${quoteIdent servingSchema}.${quoteIdent "waterway"}
    WHERE minzoom <= 9
    WITH DATA;

    CREATE INDEX IF NOT EXISTS osm_transportation_low_z7_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "transportation_low_z7"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_transportation_low_z9_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "transportation_low_z9"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_boundary_low_z5_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_boundary_low_z8_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z8"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_landcover_low_z5_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_landcover_low_z7_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z7"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_landcover_low_z9_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z9"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_landuse_low_z7_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "landuse_low_z7"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_landuse_low_z9_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "landuse_low_z9"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_park_low_z7_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "park_low_z7"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_park_low_z9_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "park_low_z9"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_water_low_z5_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_water_low_z7_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "water_low_z7"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_water_low_z9_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "water_low_z9"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_waterway_low_z7_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "waterway_low_z7"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_waterway_low_z9_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "waterway_low_z9"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_place_api_geom_idx ON ${quoteIdent servingSchema}.${quoteIdent "place_api"} USING GIST (geom);
    CREATE INDEX IF NOT EXISTS osm_place_api_search_idx ON ${quoteIdent servingSchema}.${quoteIdent "place_api"} USING GIN (to_tsvector('simple', search_text));

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
          l.subclass,
          l.minzoom,
  ${nameSelectPrefixed}        ST_AsMVTGeom(l.geom, b.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, subclass, minzoom, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z5"} WHERE z <= 5
          UNION ALL
          SELECT class, subclass, minzoom, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z7"} WHERE z > 5 AND z <= 7
          UNION ALL
          SELECT class, subclass, minzoom, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "landcover_low_z9"} WHERE z > 7 AND z <= 9
          UNION ALL
          SELECT class, subclass, minzoom, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "landcover"} WHERE z > 9
        ) l
        CROSS JOIN bounds b
        WHERE l.minzoom <= z AND l.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'landcover', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "landuse_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          l.class,
          l.minzoom,
  ${nameSelectPrefixed}        ST_AsMVTGeom(l.geom, b.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, minzoom, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "landuse_low_z7"} WHERE z <= 7
          UNION ALL
          SELECT class, minzoom, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "landuse_low_z9"} WHERE z > 7 AND z <= 9
          UNION ALL
          SELECT class, minzoom, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "landuse"} WHERE z > 9
        ) l
        CROSS JOIN bounds b
        WHERE l.minzoom <= z AND l.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'landuse', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "park_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          p.class,
  ${nameSelectPrefixed}        ST_AsMVTGeom(p.geom, b.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "park_low_z7"} WHERE z <= 7
          UNION ALL
          SELECT class, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "park_low_z9"} WHERE z > 7 AND z <= 9
          UNION ALL
          SELECT class, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "park"} WHERE z > 9
        ) p
        CROSS JOIN bounds b
        WHERE p.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'park', 4096, 'geom') FROM src;
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
          w.brunnel,
  ${nameSelectPrefixed}        ST_AsMVTGeom(w.geom, b.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, brunnel, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "water_low_z5"} WHERE z <= 5
          UNION ALL
          SELECT class, brunnel, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "water_low_z7"} WHERE z > 5 AND z <= 7
          UNION ALL
          SELECT class, brunnel, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "water_low_z9"} WHERE z > 7 AND z <= 9
          UNION ALL
          SELECT class, brunnel, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "water"} WHERE z > 9
        ) w
        CROSS JOIN bounds b
        WHERE w.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'water', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "waterway_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          w.class,
          w.minzoom,
          w.intermittent,
  ${nameSelectPrefixed}        ST_AsMVTGeom(w.geom, b.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, minzoom, intermittent, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "waterway_low_z7"} WHERE z <= 7
          UNION ALL
          SELECT class, minzoom, intermittent, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "waterway_low_z9"} WHERE z > 7 AND z <= 9
          UNION ALL
          SELECT class, minzoom, intermittent, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "waterway"} WHERE z > 9
        ) w
        CROSS JOIN bounds b
        WHERE w.minzoom <= z AND w.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'waterway', 4096, 'geom') FROM src;
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
          b.minzoom,
          b.admin_level,
          b.claimed_by,
          b.disputed,
          b.maritime,
  ${nameSelectPrefixed}        ST_AsMVTGeom(b.geom, t.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, minzoom, admin_level, claimed_by, disputed, maritime, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z5"} WHERE z <= 5
          UNION ALL
          SELECT class, minzoom, admin_level, claimed_by, disputed, maritime, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "boundary_low_z8"} WHERE z > 5 AND z <= 8
          UNION ALL
          SELECT class, minzoom, admin_level, claimed_by, disputed, maritime, ${nameColsCsv}, geom FROM ${quoteIdent servingSchema}.${quoteIdent "boundary"} WHERE z > 8
        ) b
        CROSS JOIN bounds t
        WHERE b.minzoom <= z AND b.geom && t.geom
      )
      SELECT ST_AsMVT(src, 'boundary', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "transportation_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          t.class,
          t.minzoom,
          t.subclass,
          t.brunnel,
          t.service,
          t.oneway,
          t.network,
          t.expressway,
          t.surface,
          t.access,
          t.toll,
          t.bicycle,
          t.foot,
          t.horse,
          t.mtb_scale,
          t.layer,
          t.level,
          t.indoor,
  ${nameSelectPrefixed}        t.ref,
          ST_AsMVTGeom(t.geom, b.geom, 4096, 64, true) AS geom
        FROM (
          SELECT class, minzoom, subclass, brunnel, service, oneway, network, expressway, surface, access, toll, bicycle, foot, horse, mtb_scale, layer, level, indoor, ${nameColsCsv}, ref, geom
          FROM ${quoteIdent servingSchema}.${quoteIdent "transportation_low_z7"} WHERE z <= 7
          UNION ALL
          SELECT class, minzoom, subclass, brunnel, service, oneway, network, expressway, surface, access, toll, bicycle, foot, horse, mtb_scale, layer, level, indoor, ${nameColsCsv}, ref, geom
          FROM ${quoteIdent servingSchema}.${quoteIdent "transportation_low_z9"} WHERE z > 7 AND z <= 9
          UNION ALL
          SELECT class, minzoom, subclass, brunnel, service, oneway, network, expressway, surface, access, toll, bicycle, foot, horse, mtb_scale, layer, level, indoor, ${nameColsCsv}, ref, geom
          FROM ${quoteIdent servingSchema}.${quoteIdent "transportation"} WHERE z > 9
        ) t
        CROSS JOIN bounds b
        WHERE t.minzoom <= z AND t.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'transportation', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "transportation_name_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          t.class,
          t.minzoom,
          t.subclass,
          t.network,
          t.layer,
          t.level,
          t.indoor,
  ${nameSelectPrefixed}        t.ref,
          ST_AsMVTGeom(t.geom, b.geom, 4096, 64, true) AS geom
        FROM ${quoteIdent servingSchema}.${quoteIdent "transportation_name"} t
        CROSS JOIN bounds b
        WHERE t.minzoom <= z AND t.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'transportation_name', 4096, 'geom') FROM src;
    $$;

    CREATE OR REPLACE FUNCTION ${quoteIdent servingSchema}.${quoteIdent "water_name_zxy"}(z integer, x integer, y integer)
    RETURNS bytea
    LANGUAGE sql
    STABLE
    AS $$
      WITH bounds AS (
        SELECT ST_TileEnvelope(z, x, y) AS geom
      ), src AS (
        SELECT
          w.class,
          w.minzoom,
  ${nameSelectPrefixed}        ST_AsMVTGeom(w.geom, b.geom, 4096, 64, true) AS geom
        FROM ${quoteIdent servingSchema}.${quoteIdent "water_name"} w
        CROSS JOIN bounds b
        WHERE w.minzoom <= z AND w.geom && b.geom
      )
      SELECT ST_AsMVT(src, 'water_name', 4096, 'geom') FROM src;
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
          p.minzoom,
          p.population,
          p.rank,
          p.capital,
          p.iso_a2,
  ${nameSelectPrefixed}        ST_AsMVTGeom(ST_Transform(p.geom, 3857), b.geom, 4096, 64, true) AS geom
        FROM ${quoteIdent servingSchema}.${quoteIdent "place"} p
        CROSS JOIN bounds b
        WHERE p.minzoom <= z AND ST_Transform(p.geom, 3857) && b.geom
      )
      SELECT ST_AsMVT(src, 'place', 4096, 'geom') FROM src;
    $$;

    COMMIT;
''
