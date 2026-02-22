local srid = 3857
local tables = {}

local landuse_whitelist = {
	allotments = true,
	brownfield = true,
	cemetery = true,
	commercial = true,
	farmyard = true,
	farmland = true,
	forest = true,
	garages = true,
	greenfield = true,
	industrial = true,
	landfill = true,
	meadow = true,
	military = true,
	orchard = true,
	quarry = true,
	railway = true,
	recreation_ground = true,
	residential = true,
	retail = true,
	vineyard = true,
}

local amenity_landuse_whitelist = {
	college = true,
	grave_yard = true,
	hospital = true,
	school = true,
	university = true,
}

local landcover_whitelist = {
	glacier = true,
	grass = true,
	heath = true,
	ice_shelf = true,
	mud = true,
	rock = true,
	sand = true,
	scrub = true,
	wetland = true,
	wood = true,
}

local transportation_label_classes = {
	motorway = true,
	minor = true,
	path = true,
	primary = true,
	rail = true,
	secondary = true,
	service = true,
	track = true,
	tertiary = true,
	transit = true,
	trunk = true,
}

local water_name_classes = {
	canal = true,
	river = true,
	stream = true,
}

local trunk_z5_networks = {
	["us-interstate"] = true,
	["us-highway"] = true,
	["ca-transcanada"] = true,
	["ca-provincial-arterial"] = true,
	["de-motorway"] = true,
	["de-national"] = true,
	["gb-motorway"] = true,
	["gb-trunk"] = true,
	["ie-motorway"] = true,
	["ie-national"] = true,
	["sn-national"] = true,
	["e-road"] = true,
	["a-road"] = true,
}

local route_network_priority = {
	["us-interstate"] = 1,
	["us-highway"] = 2,
	["us-state"] = 3,
	["ca-transcanada"] = 4,
	["ca-provincial-arterial"] = 5,
	["ca-provincial"] = 6,
	["de-motorway"] = 7,
	["de-national"] = 8,
	["gb-motorway"] = 9,
	["gb-trunk"] = 10,
	["gb-primary"] = 11,
	["ie-motorway"] = 12,
	["ie-national"] = 13,
	["ie-regional"] = 14,
	["sn-national"] = 15,
	["e-road"] = 16,
	["a-road"] = 17,
}

local way_route_info = {}

local function transportation_minzoom(class, subclass)
	local minzoom = 12

	if class == "motorway" then
		minzoom = 4
	elseif class == "trunk" then
		minzoom = 6
	elseif class == "primary" then
		minzoom = 7
	elseif class == "secondary" then
		minzoom = 9
	elseif class == "tertiary" then
		minzoom = 11
	elseif class == "minor" then
		minzoom = 12
	elseif class == "service" then
		minzoom = 13
	elseif class == "track" or class == "path" then
		minzoom = 13
	elseif class == "rail" then
		minzoom = 10
	elseif class == "transit" then
		minzoom = 11
	elseif class == "pier" then
		minzoom = 13
	end

	if subclass and string.find(subclass, "_link", 1, true) then
		minzoom = math.max(minzoom, 9)
	end

	return minzoom
end

local function boundary_minzoom(admin_level)
	if admin_level == 2 then
		return 2
	end
	if admin_level == 4 then
		return 5
	end
	if admin_level ~= nil then
		return 8
	end
	return 10
end

local function waterway_minzoom(class)
	if class == "river" then
		return 5
	end
	if class == "canal" then
		return 8
	end
	if class == "stream" then
		return 10
	end
	return 12
end

local function landcover_minzoom(class, area_m2)
	if
		area_m2
		and area_m2 >= 3000000
		and (
			class == "land"
			or class == "wood"
			or class == "wetland"
			or class == "grass"
			or class == "scrub"
			or class == "sand"
			or class == "rock"
			or class == "glacier"
			or class == "ice"
			or class == "ice_shelf"
		)
	then
		return 7
	end
	if area_m2 and area_m2 >= 400000 then
		return 9
	end
	return 10
end

local function landuse_minzoom(class, area_m2)
	if
		area_m2
		and area_m2 >= 2000000
		and (
			class == "residential"
			or class == "industrial"
			or class == "commercial"
			or class == "retail"
			or class == "farmland"
			or class == "farmyard"
			or class == "forest"
			or class == "military"
			or class == "cemetery"
			or class == "recreation_ground"
			or class == "allotments"
			or class == "meadow"
			or class == "orchard"
			or class == "vineyard"
			or class == "quarry"
		)
	then
		return 7
	end
	if area_m2 and area_m2 >= 300000 then
		return 9
	end
	return 10
end

local function transportation_name_minzoom(class, subclass)
	local label_floor = 12

	if class == "motorway" then
		label_floor = 6
	elseif class == "trunk" then
		label_floor = 8
	end

	if subclass and string.find(subclass, "_link", 1, true) then
		label_floor = 13
	end

	return math.max(label_floor, transportation_minzoom(class, subclass))
end

local function water_name_minzoom(class)
	if class == "river" then
		return 9
	end
	if class == "canal" then
		return 10
	end
	if class == "stream" then
		return 12
	end
	return 13
end

local function place_minzoom(class, rank, population, capital)
	local minzoom = 12
	if class == "country" then
		minzoom = math.max(0, (rank or 3) - 1)
	elseif class == "state" or class == "province" or class == "region" then
		minzoom = 3
	elseif class == "city" then
		if rank and rank <= 8 then
			minzoom = math.max(3, rank - 1)
		elseif population and population >= 300000 then
			minzoom = 6
		else
			minzoom = 8
		end
	elseif class == "town" then
		minzoom = 8
	elseif
		class == "village"
		or class == "suburb"
		or class == "quarter"
		or class == "neighbourhood"
		or class == "neighborhood"
		or class == "island"
	then
		minzoom = 10
	elseif class == "hamlet" or class == "isolated_dwelling" or class == "locality" or class == "farm" then
		minzoom = 12
	end

	if capital and minzoom > 5 then
		minzoom = 5
	end

	return minzoom
end

local function is_truthy(value)
	return value and value ~= "no" and value ~= "false" and value ~= "0"
end

local function to_int(value)
	local num = tonumber(value)
	if not num then
		return nil
	end
	return math.floor(num)
end

local function nonempty_text(value)
	if value == nil or value == "" then
		return nil
	end
	return value
end

local function bool_value(value)
	if value == "yes" or value == "true" or value == "1" then
		return true
	end
	if value == "no" or value == "false" or value == "0" then
		return false
	end
	return nil
end

local function surface_class(surface)
	if not surface then
		return nil
	end
	local paved = {
		asphalt = true,
		concrete = true,
		concrete_lanes = true,
		concrete_plates = true,
		paved = true,
		paving_stones = true,
		cobblestone = true,
		sett = true,
	}
	local unpaved = {
		unpaved = true,
		compacted = true,
		fine_gravel = true,
		gravel = true,
		pebblestone = true,
		dirt = true,
		ground = true,
		earth = true,
		sand = true,
		mud = true,
		woodchips = true,
	}
	if paved[surface] then
		return "paved"
	end
	if unpaved[surface] then
		return "unpaved"
	end
	return nil
end

local function relation_network_type(network, ref)
	if network == "US:I" then
		return "us-interstate"
	end
	if network == "US:US" then
		return "us-highway"
	end
	if network and #network == 5 and string.sub(network, 1, 3) == "US:" then
		return "us-state"
	end
	if network and string.sub(network, 1, 14) == "CA:transcanada" then
		return "ca-transcanada"
	end
	if network == "CA:QC:A" then
		return "ca-provincial-arterial"
	end
	if network == "CA:ON:primary" then
		if ref and ((#ref == 3 and string.sub(ref, 1, 1) == "4") or ref == "QEW") then
			return "ca-provincial-arterial"
		end
		return "ca-provincial"
	end
	if network == "CA:MB:PTH" and ref == "75" then
		return "ca-provincial-arterial"
	end
	if network == "CA:AB:primary" and (ref == "2" or ref == "3" or ref == "4") then
		return "ca-provincial-arterial"
	end
	if network == "CA:BC" and (ref == "3" or ref == "5" or ref == "99") then
		return "ca-provincial-arterial"
	end
	if network and string.sub(network, 1, 3) == "CA:" then
		return "ca-provincial"
	end
	if network == "DE:BAB" then
		return "de-motorway"
	end
	if network == "DE:BS" or network == "DE:B" then
		return "de-national"
	end
	if network and string.sub(network, 1, 3) == "DE:" then
		if string.find(network, "BAB", 1, true) then
			return "de-motorway"
		end
		if string.find(network, "BS", 1, true) then
			return "de-national"
		end
	end
	if network == "omt-gb-motorway" then
		return "gb-motorway"
	end
	if network == "omt-gb-trunk" then
		return "gb-trunk"
	end
	if network == "omt-gb-primary" then
		return "gb-primary"
	end
	if network == "omt-ie-motorway" then
		return "ie-motorway"
	end
	if network == "omt-ie-national" then
		return "ie-national"
	end
	if network == "omt-ie-regional" then
		return "ie-regional"
	end
	if network == "SN:RN" or network == "SN:N" then
		return "sn-national"
	end
	if network and string.sub(network, 1, 3) == "SN:" then
		return "sn-national"
	end
	if network == "e-road" then
		return "e-road"
	end
	if network == "a-road" then
		return "a-road"
	end
	return nil
end

local function route_rank(tags)
	local network = tags.network
	if network == "iwn" or network == "nwn" or network == "rwn" then
		return 1
	end
	if network == "lwn" then
		return 2
	end
	if tags["osmc:symbol"] or tags.colour or tags["ref:colour"] then
		return 2
	end
	return 3
end

local function route_priority(info)
	if not info or not info.network_type then
		return 999
	end
	return route_network_priority[info.network_type] or 999
end

local function pick_better_route(a, b)
	if not a then
		return b
	end
	if not b then
		return a
	end

	local pa = route_priority(a)
	local pb = route_priority(b)
	if pb < pa then
		return b
	end
	if pb > pa then
		return a
	end

	local na = a.network or ""
	local nb = b.network or ""
	if nb < na then
		return b
	end
	if nb > na then
		return a
	end

	local ra = a.ref or ""
	local rb = b.ref or ""
	if #rb < #ra then
		return b
	end
	if #rb > #ra then
		return a
	end
	if rb < ra then
		return b
	end
	if rb > ra then
		return a
	end

	if (b.rank or 99) < (a.rank or 99) then
		return b
	end
	return a
end

local function set_names(attrs, tags)
	attrs.name = tags.name
	attrs.name_de = tags["name:de"]
	attrs.name_en = tags["name:en"]
	attrs.name_fr = tags["name:fr"]
	attrs["name:latin"] = tags["name:latin"] or tags["name:en"] or tags.name
	attrs["name:nonlatin"] = tags["name:nonlatin"]

	if not attrs["name:nonlatin"] and tags.name and attrs["name:latin"] and attrs["name:latin"] ~= tags.name then
		attrs["name:nonlatin"] = tags.name
	end
end

local function has_area_tags(tags)
	if tags.area == "yes" then
		return true
	end
	if tags.area == "no" then
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
		or tags["area:highway"]
end

local function transportation_class(tags)
	local highway = tags.highway
	if highway then
		if highway == "motorway" or highway == "motorway_link" then
			return "motorway", highway
		end
		if highway == "trunk" or highway == "trunk_link" then
			return "trunk", highway
		end
		if highway == "primary" or highway == "primary_link" then
			return "primary", highway
		end
		if highway == "secondary" or highway == "secondary_link" then
			return "secondary", highway
		end
		if highway == "tertiary" or highway == "tertiary_link" then
			return "tertiary", highway
		end
		if highway == "service" then
			return "service", highway
		end
		if highway == "track" then
			return "track", highway
		end
		if
			highway == "path"
			or highway == "footway"
			or highway == "cycleway"
			or highway == "bridleway"
			or highway == "pedestrian"
			or highway == "steps"
		then
			return "path", highway
		end

		return "minor", highway
	end

	local railway = tags.railway
	if railway then
		if railway == "subway" or railway == "light_rail" or railway == "tram" then
			return "transit", railway
		end
		return "rail", railway
	end

	if tags.man_made == "pier" then
		return "pier", "pier"
	end

	return nil, nil
end

local function place_rank(tags, population)
	local explicit = to_int(tags.rank or tags.place_rank)
	if explicit then
		return explicit
	end

	local cls = tags.place
	if cls == "country" then
		if population and population > 100000000 then
			return 1
		end
		if population and population > 5000000 then
			return 2
		end
		return 3
	end

	if cls == "state" then
		return 4
	end

	if cls == "city" then
		if population and population > 3000000 then
			return 1
		end
		if population and population > 1000000 then
			return 2
		end
		if population and population > 300000 then
			return 3
		end
		return 4
	end

	if cls == "town" then
		return 6
	end
	if cls == "village" then
		return 8
	end
	if cls == "suburb" then
		return 10
	end
	if cls == "hamlet" or cls == "isolated_dwelling" then
		return 12
	end

	return 10
end

local function place_capital(tags)
	if tags.capital == "2" then
		return 2
	end
	if is_truthy(tags.capital) then
		return 2
	end
	return nil
end

local function place_iso_a2(tags)
	return tags.iso_a2 or tags["ISO3166-1:alpha2"] or tags["is_in:country_code"]
end

local function landcover_class(tags)
	if tags.natural == "glacier" then
		return "ice", "glacier"
	end
	if tags.natural == "ice_shelf" then
		return "ice", "ice_shelf"
	end
	if tags.natural == "wood" or tags.landuse == "forest" then
		return "wood", nil
	end
	if tags.natural == "sand" or tags.natural == "beach" then
		return "sand", nil
	end
	if tags.natural == "scree" or tags.natural == "bare_rock" or tags.natural == "shingle" then
		return "rock", nil
	end
	if tags.natural == "heath" then
		return "scrub", nil
	end
	if tags.natural == "grassland" then
		return "grass", nil
	end
	if tags.natural == "scrub" then
		return "scrub", nil
	end
	if tags.natural == "wetland" then
		return "wetland", tags.wetland
	end
	if tags.landcover then
		if not landcover_whitelist[tags.landcover] then
			return nil, nil
		end
		return tags.landcover, nil
	end
	if tags.wetland then
		return "wetland", tags.wetland
	end
	return nil, nil
end

local function landuse_class(tags)
	if tags.landuse then
		if not landuse_whitelist[tags.landuse] then
			return nil
		end
		return tags.landuse
	end
	if tags.amenity and amenity_landuse_whitelist[tags.amenity] then
		return tags.amenity
	end
	return nil
end

local function park_class(tags)
	if tags.leisure == "park" or tags.leisure == "nature_reserve" or tags.boundary == "national_park" then
		return tags.leisure or tags.boundary
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

local function waterway_class(tags)
	return tags.waterway
end

local function boundary_class(tags)
	if tags.boundary == "administrative" or tags.boundary == "disputed" then
		return "administrative"
	end
	if tags.admin_level then
		return "administrative"
	end
	return nil
end

local function aeroway_class(tags)
	local value = tags.aeroway
	if value == "runway" or value == "taxiway" or value == "apron" or value == "helipad" or value == "aerodrome" then
		return value
	end
	return nil
end

local function oneway_value(tags)
	if tags.oneway == "-1" then
		return -1
	end
	if is_truthy(tags.oneway) then
		return 1
	end
	if tags.oneway == "no" then
		return 0
	end
	return nil
end

tables.landcover = osm2pgsql.define_area_table("landcover", {
	{ column = "class", type = "text", not_null = true },
	{ column = "subclass", type = "text" },
	{ column = "minzoom", type = "int", not_null = true },
	{ column = "name", type = "text" },
	{ column = "name_de", type = "text" },
	{ column = "name_en", type = "text" },
	{ column = "name_fr", type = "text" },
	{ column = "name:latin", type = "text" },
	{ column = "name:nonlatin", type = "text" },
	{ column = "geom", type = "geometry", projection = srid, not_null = true },
})

tables.landuse = osm2pgsql.define_area_table("landuse", {
	{ column = "class", type = "text", not_null = true },
	{ column = "minzoom", type = "int", not_null = true },
	{ column = "name", type = "text" },
	{ column = "name_de", type = "text" },
	{ column = "name_en", type = "text" },
	{ column = "name_fr", type = "text" },
	{ column = "name:latin", type = "text" },
	{ column = "name:nonlatin", type = "text" },
	{ column = "geom", type = "geometry", projection = srid, not_null = true },
})

tables.park = osm2pgsql.define_area_table("park", {
	{ column = "class", type = "text", not_null = true },
	{ column = "name", type = "text" },
	{ column = "name_de", type = "text" },
	{ column = "name_en", type = "text" },
	{ column = "name_fr", type = "text" },
	{ column = "name:latin", type = "text" },
	{ column = "name:nonlatin", type = "text" },
	{ column = "geom", type = "geometry", projection = srid, not_null = true },
})

tables.water = osm2pgsql.define_area_table("water", {
	{ column = "class", type = "text", not_null = true },
	{ column = "brunnel", type = "text" },
	{ column = "name", type = "text" },
	{ column = "name_de", type = "text" },
	{ column = "name_en", type = "text" },
	{ column = "name_fr", type = "text" },
	{ column = "name:latin", type = "text" },
	{ column = "name:nonlatin", type = "text" },
	{ column = "geom", type = "geometry", projection = srid, not_null = true },
})

tables.waterway = osm2pgsql.define_way_table("waterway", {
	{ column = "class", type = "text", not_null = true },
	{ column = "minzoom", type = "int", not_null = true },
	{ column = "intermittent", type = "bool" },
	{ column = "name", type = "text" },
	{ column = "name_de", type = "text" },
	{ column = "name_en", type = "text" },
	{ column = "name_fr", type = "text" },
	{ column = "name:latin", type = "text" },
	{ column = "name:nonlatin", type = "text" },
	{ column = "geom", type = "linestring", projection = srid, not_null = true },
})

tables.boundary = osm2pgsql.define_table({
	name = "boundary",
	ids = { type = "any", id_column = "osm_id", type_column = "osm_type" },
	columns = {
		{ column = "class", type = "text", not_null = true },
		{ column = "minzoom", type = "int", not_null = true },
		{ column = "admin_level", type = "int" },
		{ column = "claimed_by", type = "text" },
		{ column = "disputed", type = "bool" },
		{ column = "maritime", type = "bool" },
		{ column = "name", type = "text" },
		{ column = "name_de", type = "text" },
		{ column = "name_en", type = "text" },
		{ column = "name_fr", type = "text" },
		{ column = "name:latin", type = "text" },
		{ column = "name:nonlatin", type = "text" },
		{ column = "geom", type = "geometry", projection = srid, not_null = true },
	},
	indexes = {
		{ column = "geom", method = "gist" },
		{ column = { "class", "admin_level" }, method = "btree" },
		{ column = { "class", "minzoom" }, method = "btree" },
	},
})

tables.transportation = osm2pgsql.define_table({
	name = "transportation",
	ids = { type = "any", id_column = "osm_id", type_column = "osm_type" },
	columns = {
		{ column = "class", type = "text", not_null = true },
		{ column = "minzoom", type = "int", not_null = true },
		{ column = "subclass", type = "text" },
		{ column = "brunnel", type = "text" },
		{ column = "service", type = "text" },
		{ column = "oneway", type = "int" },
		{ column = "network", type = "text" },
		{ column = "expressway", type = "bool" },
		{ column = "surface", type = "text" },
		{ column = "access", type = "text" },
		{ column = "toll", type = "bool" },
		{ column = "bicycle", type = "text" },
		{ column = "foot", type = "text" },
		{ column = "horse", type = "text" },
		{ column = "mtb_scale", type = "text" },
		{ column = "layer", type = "int" },
		{ column = "level", type = "text" },
		{ column = "indoor", type = "bool" },
		{ column = "ref", type = "text" },
		{ column = "name", type = "text" },
		{ column = "name_de", type = "text" },
		{ column = "name_en", type = "text" },
		{ column = "name_fr", type = "text" },
		{ column = "name:latin", type = "text" },
		{ column = "name:nonlatin", type = "text" },
		{ column = "geom", type = "geometry", projection = srid, not_null = true },
	},
	indexes = {
		{ column = "geom", method = "gist" },
		{ column = { "class", "subclass" }, method = "btree" },
		{ column = { "class", "minzoom" }, method = "btree" },
	},
})

tables.aeroway = osm2pgsql.define_table({
	name = "aeroway",
	ids = { type = "any", id_column = "osm_id", type_column = "osm_type" },
	columns = {
		{ column = "class", type = "text", not_null = true },
		{ column = "ref", type = "text" },
		{ column = "iata", type = "text" },
		{ column = "name", type = "text" },
		{ column = "name_de", type = "text" },
		{ column = "name_en", type = "text" },
		{ column = "name_fr", type = "text" },
		{ column = "name:latin", type = "text" },
		{ column = "name:nonlatin", type = "text" },
		{ column = "geom", type = "geometry", projection = srid, not_null = true },
	},
	indexes = {
		{ column = "geom", method = "gist" },
		{ column = "class", method = "btree" },
	},
})

tables.transportation_name = osm2pgsql.define_table({
	name = "transportation_name",
	ids = { type = "any", id_column = "osm_id", type_column = "osm_type" },
	columns = {
		{ column = "class", type = "text", not_null = true },
		{ column = "minzoom", type = "int", not_null = true },
		{ column = "subclass", type = "text" },
		{ column = "network", type = "text" },
		{ column = "layer", type = "int" },
		{ column = "level", type = "text" },
		{ column = "indoor", type = "bool" },
		{ column = "ref", type = "text" },
		{ column = "name", type = "text" },
		{ column = "name_de", type = "text" },
		{ column = "name_en", type = "text" },
		{ column = "name_fr", type = "text" },
		{ column = "name:latin", type = "text" },
		{ column = "name:nonlatin", type = "text" },
		{ column = "geom", type = "geometry", projection = srid, not_null = true },
	},
	indexes = {
		{ column = "geom", method = "gist" },
		{ column = { "class", "minzoom" }, method = "btree" },
	},
})

tables.building = osm2pgsql.define_area_table("building", {
	{ column = "class", type = "text", not_null = true },
	{ column = "name", type = "text" },
	{ column = "name_de", type = "text" },
	{ column = "name_en", type = "text" },
	{ column = "name_fr", type = "text" },
	{ column = "name:latin", type = "text" },
	{ column = "name:nonlatin", type = "text" },
	{ column = "geom", type = "geometry", projection = srid, not_null = true },
})

tables.water_name = osm2pgsql.define_way_table("water_name", {
	{ column = "class", type = "text", not_null = true },
	{ column = "minzoom", type = "int", not_null = true },
	{ column = "name", type = "text" },
	{ column = "name_de", type = "text" },
	{ column = "name_en", type = "text" },
	{ column = "name_fr", type = "text" },
	{ column = "name:latin", type = "text" },
	{ column = "name:nonlatin", type = "text" },
	{ column = "geom", type = "linestring", projection = srid, not_null = true },
})

tables.place = osm2pgsql.define_table({
	name = "place",
	ids = { type = "any", id_column = "osm_id", type_column = "osm_type" },
	columns = {
		{ column = "class", type = "text", not_null = true },
		{ column = "minzoom", type = "int", not_null = true },
		{ column = "population", type = "int8" },
		{ column = "rank", type = "int" },
		{ column = "capital", type = "int" },
		{ column = "iso_a2", type = "text" },
		{ column = "name", type = "text" },
		{ column = "name_de", type = "text" },
		{ column = "name_en", type = "text" },
		{ column = "name_fr", type = "text" },
		{ column = "name:latin", type = "text" },
		{ column = "name:nonlatin", type = "text" },
		{ column = "geom", type = "point", projection = 4326, not_null = true },
	},
	indexes = {
		{ column = "geom", method = "gist" },
		{ column = { "class", "rank" }, method = "btree" },
		{ column = { "class", "minzoom" }, method = "btree" },
		{ column = "population", method = "btree" },
	},
})

local function insert_place(tags, geom)
	if not tags.place then
		return
	end

	local population = to_int(tags.population)
	local rank = place_rank(tags, population)
	local capital = place_capital(tags)
	local attrs = {
		class = tags.place,
		minzoom = place_minzoom(tags.place, rank, population, capital),
		population = population,
		rank = rank,
		capital = capital,
		iso_a2 = place_iso_a2(tags),
		geom = geom,
	}
	set_names(attrs, tags)
	tables.place:insert(attrs)
end

local function insert_landcover(tags, geom)
	local class, subclass = landcover_class(tags)
	if not class then
		return
	end
	local area_m2 = geom:area()

	local attrs = {
		class = class,
		subclass = subclass,
		minzoom = landcover_minzoom(class, area_m2),
		geom = geom,
	}
	set_names(attrs, tags)
	tables.landcover:insert(attrs)
end

local function insert_landuse(tags, geom)
	local class = landuse_class(tags)
	if not class then
		return
	end
	local area_m2 = geom:area()

	local attrs = {
		class = class,
		minzoom = landuse_minzoom(class, area_m2),
		geom = geom,
	}
	set_names(attrs, tags)
	tables.landuse:insert(attrs)
end

local function insert_park(tags, geom)
	local class = park_class(tags)
	if not class then
		return
	end

	local attrs = {
		class = class,
		geom = geom,
	}
	set_names(attrs, tags)
	tables.park:insert(attrs)
end

local function insert_water(tags, geom)
	local class = water_class(tags)
	if not class then
		return
	end

	local attrs = {
		class = class,
		brunnel = nil,
		geom = geom,
	}
	set_names(attrs, tags)
	tables.water:insert(attrs)
end

local function insert_building(tags, geom)
	if not tags.building then
		return
	end

	local attrs = {
		class = tags.building == "yes" and "building" or tags.building,
		geom = geom,
	}
	set_names(attrs, tags)
	tables.building:insert(attrs)
end

local function insert_transportation(object, geom, write_name_labels)
	local tags = object.tags
	local class, subclass = transportation_class(tags)
	if not class then
		return
	end

	local route_info = way_route_info[object.id]
	local route_network = route_info and route_info.network_type or nil
	local route_ref = route_info and route_info.ref or nil

	local brunnel = nil
	if is_truthy(tags.tunnel) then
		brunnel = "tunnel"
	elseif is_truthy(tags.bridge) then
		brunnel = "bridge"
	end

	local attrs = {
		class = class,
		minzoom = transportation_minzoom(class, subclass),
		subclass = subclass,
		brunnel = brunnel,
		service = tags.service,
		oneway = oneway_value(tags),
		network = route_network or nonempty_text(tags.network),
		expressway = bool_value(tags.expressway),
		surface = surface_class(tags.surface),
		access = nonempty_text(tags.access),
		toll = bool_value(tags.toll),
		bicycle = nonempty_text(tags.bicycle),
		foot = nonempty_text(tags.foot),
		horse = nonempty_text(tags.horse),
		mtb_scale = nonempty_text(tags.mtb_scale),
		layer = to_int(tags.layer),
		level = nonempty_text(tags.level),
		indoor = bool_value(tags.indoor),
		ref = nonempty_text(tags.ref) or route_ref,
		geom = geom,
	}

	if class == "trunk" and attrs.network and trunk_z5_networks[attrs.network] then
		attrs.minzoom = math.min(attrs.minzoom, 5)
	end
	if (class == "path" or class == "track") and route_info then
		if route_info.rank == 1 then
			attrs.minzoom = math.min(attrs.minzoom, 12)
		elseif route_info.rank == 2 then
			attrs.minzoom = math.min(attrs.minzoom, 13)
		end
	end

	set_names(attrs, tags)
	tables.transportation:insert(attrs)
	if
		write_name_labels
		and transportation_label_classes[class]
		and (attrs.name or attrs["name:latin"] or attrs.ref)
	then
		local labels = {
			class = class,
			minzoom = transportation_name_minzoom(class, subclass),
			subclass = subclass,
			network = attrs.network or (attrs.ref and "road" or nil),
			layer = attrs.layer,
			level = attrs.level,
			indoor = attrs.indoor,
			ref = attrs.ref,
			geom = geom,
		}
		set_names(labels, tags)
		tables.transportation_name:insert(labels)
	end
end

local function insert_aeroway(tags, geom, write_name_labels)
	local class = aeroway_class(tags)
	if not class then
		return
	end

	local attrs = {
		class = class,
		ref = tags.ref,
		iata = tags.iata,
		geom = geom,
	}
	set_names(attrs, tags)
	tables.aeroway:insert(attrs)

	if write_name_labels and (attrs.name or attrs["name:latin"] or attrs.ref) then
		local labels = {
			class = "aerialway",
			minzoom = 12,
			subclass = class,
			network = nonempty_text(tags.network),
			layer = to_int(tags.layer),
			level = nonempty_text(tags.level),
			indoor = bool_value(tags.indoor),
			ref = tags.ref,
			geom = geom,
		}
		set_names(labels, tags)
		tables.transportation_name:insert(labels)
	end
end

local function insert_shipway_name(tags, geom)
	if tags.route ~= "ferry" then
		return
	end

	if not (tags.name or tags["name:latin"] or tags.ref) then
		return
	end

	local labels = {
		class = "ferry",
		minzoom = 12,
		subclass = "ferry",
		network = nonempty_text(tags.network),
		layer = to_int(tags.layer),
		level = nonempty_text(tags.level),
		indoor = bool_value(tags.indoor),
		ref = tags.ref,
		geom = geom,
	}
	set_names(labels, tags)
	tables.transportation_name:insert(labels)
end

local function insert_motorway_junction(tags, geom)
	if tags.highway ~= "motorway_junction" then
		return
	end
	if not (tags.ref or tags.name or tags["name:latin"]) then
		return
	end

	local labels = {
		class = "motorway_junction",
		minzoom = 10,
		subclass = "junction",
		network = nonempty_text(tags.network),
		layer = to_int(tags.layer),
		level = nonempty_text(tags.level),
		indoor = bool_value(tags.indoor),
		ref = tags.ref,
		geom = geom,
	}
	set_names(labels, tags)
	tables.transportation_name:insert(labels)
end

local function insert_waterway(tags, geom)
	local class = waterway_class(tags)
	if not class then
		return
	end

	local attrs = {
		class = class,
		minzoom = waterway_minzoom(class),
		intermittent = is_truthy(tags.intermittent),
		geom = geom,
	}
	set_names(attrs, tags)
	tables.waterway:insert(attrs)

	if water_name_classes[class] and (attrs.name or attrs["name:latin"]) then
		local labels = {
			class = class,
			minzoom = water_name_minzoom(class),
			geom = geom,
		}
		set_names(labels, tags)
		tables.water_name:insert(labels)
	end
end

local function insert_boundary(tags, geom)
	local class = boundary_class(tags)
	if not class then
		return
	end
	local admin_level = to_int(tags.admin_level)

	local attrs = {
		class = class,
		admin_level = admin_level,
		minzoom = boundary_minzoom(admin_level),
		claimed_by = tags.claimed_by,
		disputed = is_truthy(tags.disputed),
		maritime = is_truthy(tags.maritime),
		geom = geom,
	}
	set_names(attrs, tags)
	tables.boundary:insert(attrs)
end

local function insert_polygon_features(tags, geom)
	insert_landcover(tags, geom)
	insert_landuse(tags, geom)
	insert_park(tags, geom)
	insert_water(tags, geom)
	insert_building(tags, geom)
	insert_aeroway(tags, geom, false)
end

function osm2pgsql.process_node(object)
	local point = object:as_point()
	insert_place(object.tags, point)
	insert_motorway_junction(object.tags, point)
end

function osm2pgsql.process_way(object)
	local tags = object.tags

	if object.is_closed and has_area_tags(tags) then
		local polygon = object:as_polygon()
		insert_polygon_features(tags, polygon)
		insert_place(tags, polygon:centroid())
		return
	end

	local line = object:as_linestring()
	insert_waterway(tags, line)
	insert_boundary(tags, line)
	insert_transportation(object, line, true)
	insert_aeroway(tags, line, true)
	insert_shipway_name(tags, line)
end

function osm2pgsql.select_relation_members(relation)
	if relation.tags.type == "route" then
		return { ways = osm2pgsql.way_member_ids(relation) }
	end
end

function osm2pgsql.process_relation(object)
	if object.tags.type == "route" and (object.tags.route == "road" or object.tags.route == "hiking") then
		local ref = nonempty_text(object.tags.ref)
		local network = nonempty_text(object.tags.network)
		local info = {
			network_type = relation_network_type(network, ref),
			network = network,
			ref = ref,
			rank = route_rank(object.tags),
		}
		if info.network_type or info.rank < 3 or info.ref then
			for _, member in ipairs(object.members) do
				if member.type == "w" then
					way_route_info[member.ref] = pick_better_route(way_route_info[member.ref], info)
				end
			end
		end
		return
	end

	if object.tags.type == "boundary" then
		insert_boundary(object.tags, object:as_multilinestring())
		return
	end

	if object.tags.type ~= "multipolygon" then
		return
	end

	local polygon = object:as_multipolygon()
	insert_polygon_features(object.tags, polygon)
	insert_place(object.tags, polygon:centroid())
end
