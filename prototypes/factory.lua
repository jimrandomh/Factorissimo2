require("util")
require("constants")
local Constants = Constants

local function cwc0()
	return {shadow = {red = {0,0},green = {0,0}}, wire = {red = {0,0},green = {0,0}}}
end
local function cc0()
	return get_circuit_connector_sprites({0,0},nil,1)
end


function factory_base(params)
	local name = params.name .. params.suffix
	local result_name = params.name .. params.mined_result_suffix
	
	return {
		name = name,
		type = "storage-tank",
		icon = params.icon,
		max_health = params.max_health,
		flags = {"player-creation"},
		collision_box = centered_square(params.collision_size),
		minable = {
			mining_time = 5,
			result = result_name,
			count = params.mined_result_count
		},
		pictures = {
			picture = params.picture,
			fluid_background = blank(),
			window_background = blank(),
			flow_sprite = blank(),
			gas_flow = ablank(),
		},
		allow_copy_paste = true,
		additional_pastable_entities = {"storage-tank"},
		vehicle_impact_sound = { filename = "__base__/sound/car-stone-impact.ogg", volume = 1.0 },
		corpse = "big-remnants",
		window_bounding_box = centered_square(0),
		selection_box = centered_square(params.collision_size),
		fluid_box = {
			base_area = 1,
			pipe_covers = pipecoverspictures(),
			pipe_connections = {},
		},
		flow_length_in_ticks = 1,
		circuit_wire_connection_points = {cwc0(), cwc0(), cwc0(), cwc0()},
		circuit_connector_sprites = {cc0(), cc0(), cc0(), cc0()},
		circuit_wire_max_distance = 0,
		map_color = {r = 0.8, g = 0.7, b = 0.55}
	}
end

function factory_item_base(params)
	local name = params.name .. params.suffix
	local item_flags
	if params.craftable then item_flags = {"goes-to-quickbar"} else item_flags = {"hidden"} end
	
	return {
		name = name,
		type = "item",
		subgroup = "factorissimo2",
		icon = params.icon,
		order = params.order,
		flags = item_flags,
		place_result = name,
		stack_size = (params.suffix=="" and 10 or 1),
	}
end

function create_factory_entities(params)
	local building_and_item = function(params)
		return {
			factory_base(params),
			factory_item_base(params)
		};
	end
	-- Craftable factory object, with no corresponding interior generated
	data:extend(building_and_item(
		merge_properties({
			mined_result_count = 0,
			craftable = true,
			suffix = "",
			mined_result_suffix = ""
		}, params)
	))
	
	-- Inactive factory object, for when the player put down a factory building
	-- but it was invalid in some way (eg recursion without the technology
	-- being researched).
	data:extend(building_and_item(
		merge_properties({
			mined_result_count = 1,
			craftable = false,
			suffix = "-i",
			mined_result_suffix = ""
		}, params)
	))
	
	-- Saved factory entities - that is, for when the player placed a factory,
	-- populated it, and then picked it back up. There's a set of special
	-- entities for these (since entity-type-name is the only property that
	-- gets reliably preserved when in inventory), and that's the maximum
	-- number of factories you can have picked up.
	for i=Constants.factory_id_min,Constants.factory_id_max do
		data:extend(building_and_item(
			merge_properties({
				mined_result_count = 1,
				craftable = false,
				suffix = "-s"..i,
				mined_result_suffix = "-s"..i
			}, params)
		))
	end
	
	-- Blueprint factory entities
	data:extend({{
		type = "item",
		name = params.name .. "-blueprint",
		icon = params.icon,
		flags = {},
		subgroup = "factorissimo2",
		order = "a-a",
		place_result = params.name .. "-blueprint",
		stack_size = 1,
	}})
	data:extend({{
		type = "programmable-speaker",
		name = params.name .. "-blueprint",
		icon = params.icon,
		max_health = 1000,
		flags = {"player-creation"},
		
		collision_box = centered_square(params.collision_size),
		selection_box = centered_square(params.collision_size),
		energy_source = {
			type = "electric",
			usage_priority = "secondary-input",
			emissions = 0,
			render_no_power_icon = false,
			render_no_network_icon = false,
		},
		energy_usage_per_tick = "0W",
		sprite = {
			filename = params.combined_image,
			frames = 1,
			width = params.picture.sheet.width,
			height = params.picture.sheet.height,
			shift = params.picture.sheet.shift,
			scale = params.picture.sheet.scale,
		},
		maximum_polyphony = 0,
		instruments = {},
		picture = {
			filename = params.combined_image,
			priority = "extra-high",
			width = params.picture.sheet.width,
			height = params.picture.sheet.height,
			shift = params.picture.sheet.shift,
			scale = params.picture.sheet.scale,
		},
	}})
	
	-- Crafting recipe
	data:extend({
		{
			type = "recipe",
			name = params.name,
			enabled = false,
			result = params.name,
			
			energy_required = params.energy_required,
			ingredients = params.ingredients
		}
	})
end


create_factory_entities({
	name = "factory-tiny",
	image = graphicsDir.."/factory/factory-1.png",
	combined_image = graphicsDir.."/factory/factory-1-combined.png",
	icon = graphicsDir.."/icon/factory-1.png",
	max_health = 1000,
	collision_size = 3.6,
	order = "a-a",
	
	picture = {
		sheet = {
			filename = graphicsDir.."/factory/factory-1-combined.png",
			frames = 1,
			width = 416,
			height = 320,
			shift = {0.75, 0},
			scale = 0.5
		}
	},
	
	energy_required = 15,
	ingredients = {{"stone-brick", 100}, {"iron-plate", 200}, {"copper-plate", 100}},
})
create_factory_entities({
	name = "factory-1",
	image = graphicsDir.."/factory/factory-1.png",
	combined_image = graphicsDir.."/factory/factory-1-combined.png",
	icon = graphicsDir.."/icon/factory-1.png",
	max_health = 2000,
	collision_size = 7.6,
	order = "a-a",
	
	picture = {
		sheet = {
			filename = graphicsDir.."/factory/factory-1-combined.png",
			frames = 1,
			width = 416,
			height = 320,
			shift = {1.5, 0},
			scale = 1.0
		},
	},
	
	energy_required = 30,
	ingredients = {{"stone-brick", 200}, {"iron-plate", 250}, {"copper-plate", 100}},
})
create_factory_entities({
	name = "factory-2",
	image = graphicsDir.."/factory/factory-2.png",
	combined_image = graphicsDir.."/factory/factory-2-combined.png",
	icon = graphicsDir.."/icon/factory-2.png",
	max_health = 3500,
	collision_size = 11.6,
	order = "a-b",
	
	picture = {
		sheet = {
			filename = graphicsDir.."/factory/factory-2-combined.png",
			frames = 1,
			width = 544,
			height = 448,
			shift = {1.5, 0},
			scale = 1.0
		},
	},
	
	energy_required = 46,
	ingredients = {{"stone-brick", 1000}, {"steel-plate", 250}, {"big-electric-pole", 50}},
})
create_factory_entities({
	name = "factory-3",
	image = graphicsDir.."/factory/factory-3.png",
	combined_image = graphicsDir.."/factory/factory-3-combined.png",
	icon = graphicsDir.."/icon/factory-3.png",
	max_health = 5000,
	collision_size = 15.6,
	order = "a-c",
	
	picture = {
		sheet = {
			filename = graphicsDir.."/factory/factory-3-combined.png",
			frames = 1,
			width = 704,
			height = 608,
			shift = {2, -0.09375},
			scale = 1.0
		},
	},
	
	energy_required = 60,
	ingredients = {{"concrete", 5000}, {"steel-plate", 2000}, {"substation", 100}},
})
