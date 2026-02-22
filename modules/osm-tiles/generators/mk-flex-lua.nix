{
  pkgs,
  lib,
  locales,
}: let
  localeArray = lib.concatStringsSep ", " (map (locale: ''"${locale}"'') locales);
in
  pkgs.writeText "osm-tiles-flex.lua" ''
    local srid = 3857
    local locale_codes = { ${localeArray} }
    local tables = {}

    local function collect_names(tags)
      local names = {}

      for _, locale in ipairs(locale_codes) do
        local key = "name:" .. locale
        local value = tags[key]
        if value and value ~= "" then
          names[locale] = value
        end
      end

      return names
    end

    local function set_name_attrs(attrs, tags)
      attrs.name = tags.name
      attrs.names = collect_names(tags)
    end

    local function has_area_tags(tags)
      if tags.area == "yes" then
        return true
      end
      if tags.area == "no" then
        return false
      end

      return tags.natural
        or tags.landcover
        or tags.landuse
        or tags.leisure
        or tags.water
        or tags.waterway
        or tags.wetland
        or tags.building
    end

    local function landcover_class(tags)
      if tags.landcover then
        return tags.landcover
      end
      if tags.natural then
        return tags.natural
      end
      if tags.landuse == "forest" then
        return "forest"
      end
      if tags.wetland then
        return "wetland"
      end
      if tags.leisure == "park" then
        return "park"
      end

      return nil
    end

    local function water_class(tags)
      if tags.natural == "water" then
        return tags.water or "water"
      end
      if tags.water then
        return tags.water
      end
      if tags.landuse == "reservoir" then
        return "reservoir"
      end
      if tags.waterway == "riverbank" then
        return "riverbank"
      end

      return nil
    end

    local function to_int(value)
      if not value then
        return nil
      end
      local n = tonumber(value)
      if not n then
        return nil
      end
      return math.floor(n)
    end

    local function boundary_admin_level(tags)
      if tags.boundary ~= "administrative" then
        return nil
      end

      return to_int(tags.admin_level)
    end

    local function insert_landcover(tags, geom)
      local class = landcover_class(tags)
      if not class then
        return
      end

      local attrs = {
        class = class,
        geom = geom,
      }
      set_name_attrs(attrs, tags)
      tables.landcover:insert(attrs)
    end

    local function insert_water(tags, geom)
      local class = water_class(tags)
      if not class then
        return
      end

      local attrs = {
        class = class,
        geom = geom,
      }
      set_name_attrs(attrs, tags)
      tables.water:insert(attrs)
    end

    local function insert_boundary(tags, geom)
      local admin_level = boundary_admin_level(tags)
      if not admin_level then
        return
      end

      local attrs = {
        class = "administrative",
        admin_level = admin_level,
        geom = geom,
      }
      set_name_attrs(attrs, tags)
      tables.boundary:insert(attrs)
    end

    local function insert_place(tags, geom)
      if not tags.place then
        return
      end

      local attrs = {
        class = tags.place,
        population = to_int(tags.population),
        geom = geom,
      }
      set_name_attrs(attrs, tags)
      tables.place:insert(attrs)
    end

    tables.landcover = osm2pgsql.define_area_table("landcover", {
      { column = "class", type = "text", not_null = true },
      { column = "name", type = "text" },
      { column = "names", type = "jsonb" },
      { column = "geom", type = "geometry", projection = srid, not_null = true },
    })

    tables.water = osm2pgsql.define_area_table("water", {
      { column = "class", type = "text", not_null = true },
      { column = "name", type = "text" },
      { column = "names", type = "jsonb" },
      { column = "geom", type = "geometry", projection = srid, not_null = true },
    })

    tables.boundary = osm2pgsql.define_table({
      name = "boundary",
      ids = { type = "any", id_column = "osm_id", type_column = "osm_type" },
      columns = {
        { column = "class", type = "text", not_null = true },
        { column = "admin_level", type = "int", not_null = true },
        { column = "name", type = "text" },
        { column = "names", type = "jsonb" },
        { column = "geom", type = "linestring", projection = srid, not_null = true },
      },
      indexes = {
        { column = "geom", method = "gist" },
        { column = { "class", "admin_level" }, method = "btree" },
      },
    })

    tables.place = osm2pgsql.define_table({
      name = "place",
      ids = { type = "any", id_column = "osm_id", type_column = "osm_type" },
      columns = {
        { column = "class", type = "text", not_null = true },
        { column = "population", type = "int8" },
        { column = "name", type = "text" },
        { column = "names", type = "jsonb" },
        { column = "geom", type = "point", projection = 4326, not_null = true },
      },
      indexes = {
        { column = "geom", method = "gist" },
        { column = { "class", "population" }, method = "btree" },
      },
    })

    function osm2pgsql.process_node(object)
      insert_place(object.tags, object:as_point())
    end

    function osm2pgsql.process_way(object)
      if object.is_closed and has_area_tags(object.tags) then
        local polygon = object:as_polygon()
        insert_landcover(object.tags, polygon)
        insert_water(object.tags, polygon)
        insert_place(object.tags, polygon:centroid())
        return
      end

      local line = object:as_linestring()
      insert_boundary(object.tags, line)
    end

    function osm2pgsql.process_relation(object)
      if object.tags.type == "multipolygon" then
        local mp = object:as_multipolygon()
        insert_landcover(object.tags, mp)
        insert_water(object.tags, mp)
        insert_place(object.tags, mp:centroid())
      end
    end
  ''
