require("util")

-- Pipe connectors

local function factory_pipe(name, height, order) 
	data:extend({
		{
			type = "item",
			name = name,
			icon = graphicsDir.."/icon/"..name..".png",
			icon_size = 32,
			flags = {"goes-to-quickbar"},
			subgroup = "microfactorio",
			order = order,
			place_result = name,
			stack_size = 50,
		},
		{
			type = "storage-tank",
			name = name,
			icon = graphicsDir.."/icon/"..name..".png",
			icon_size = 32,
			flags = {"placeable-player", "player-creation"},
			minable = {mining_time = 1, result = name},
			max_health = 80,
			corpse = "small-remnants",
			collision_box = centered_square(0.125),
			selection_box = centered_square(1.0),
			fluid_box =
			{
				base_area = 25,
				base_level = height,
				pipe_covers = pipecoverspictures(),
				pipe_connections = {
					{ position = {0, -1} },
					{ position = {0, 1} },
				},
			},
			window_bounding_box = centered_square(0),
			pictures = {
				picture = {
					sheet = {
						filename = graphicsDir.."/utility/"..name..".png",
						priority = "extra-high",
						frames = 2,
						width = 50,
						height = 50,
						shift = {0.15625, -0.0625}
					}
				},
				fluid_background = {
					filename = "__base__/graphics/entity/storage-tank/fluid-background.png",
					priority = "extra-high",
					width = 0,
					height = 0
				},
				window_background = {
					filename = "__base__/graphics/entity/storage-tank/window-background.png",
					priority = "extra-high",
					width = 0,
					height = 0
				},
				flow_sprite = {
					filename = "__base__/graphics/entity/pipe/fluid-flow-low-temperature.png",
					priority = "extra-high",
					width = 0,
					height = 0
				},
				gas_flow = {
					filename = "__base__/graphics/entity/pipe/fluid-flow-low-temperature.png",
					priority = "extra-high",
					width = 0,
					height = 0,
					frame_count = 1,
				}
			},
			flow_length_in_ticks = 1,
			vehicle_impact_sound = { filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 },
			working_sound = {
				sound = {
						filename = "__base__/sound/storage-tank.ogg",
						volume = 0.1
				},
				apparent_volume = 0.1,
				max_sounds_per_type = 3
			},
			circuit_connector_points = circuit_connector_definitions["storage-tank"].points,
			circuit_connector_sprites = circuit_connector_definitions["storage-tank"].sprites,
			circuit_wire_max_distance = 0
		},
	})
end

factory_pipe("factory-input-pipe", -1, "b-a")
factory_pipe("factory-output-pipe", 1, "b-b")

-- Circuit connectors

data:extend({
	{
		type = "item",
		name = "factory-circuit-input",
		icon = graphicsDir.."/icon/factory-circuit-input.png",
		icon_size = 32,
		flags = {"goes-to-quickbar"},
		subgroup = "microfactorio",
		order = "c-a",
		place_result = "factory-circuit-input",
		stack_size = 50,
	},
	{
		type = "pump",
		name = "factory-circuit-input",
		icon = graphicsDir.."/icon/factory-circuit-input.png",
		icon_size = 32,
		flags = {"placeable-neutral", "player-creation"},
		minable = {mining_time = 1, result = "factory-circuit-input"},
		max_health = 80,
		corpse = "small-remnants",
		
		collision_box = centered_square(0.58),
		selection_box = centered_square(1.0),
		
		fluid_box = {
			base_area = 1,
			pipe_covers = pipecoverspictures(),
			pipe_connections = {},
		},
		
		energy_source = {
			type = "electric",
			usage_priority = "secondary-input",
			emissions = 0,
			render_no_power_icon = false,
			render_no_network_icon = false,
		},
		energy_usage = "60W",
		pumping_speed = 0,
		vehicle_impact_sound = { filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 },
		animations = {
			north = {
				filename = graphicsDir.."/utility/factory-combinators.png",
				x = 158,
				y = 0,
				width = 79,
				height = 63,
				frame_count = 1,
				shift = {0.140625, 0.140625},
			},
			east = {
				filename = graphicsDir.."/utility/factory-combinators.png",
				y = 0,
				width = 79,
				height = 63,
				frame_count = 1,
				shift = {0.140625, 0.140625},
			},
			south = {
				filename = graphicsDir.."/utility/factory-combinators.png",
				x = 237,
				y = 0,
				width = 79,
				height = 63,
				frame_count = 1,
				shift = {0.140625, 0.140625},
			},
			west = {
				filename = graphicsDir.."/utility/factory-combinators.png",
				x = 79,
				y = 0,
				width = 79,
				height = 63,
				frame_count = 1,
				shift = {0.140625, 0.140625},
			}
		},
		circuit_wire_connection_points = {
			{
				shadow = {
					red = {0.15625, -0.28125},
					green = {0.65625, -0.25}
				},
				wire = {
					red = {-0.28125, -0.5625},
					green = {0.21875, -0.5625},
				}
			},
			{
				shadow = {
					red = {0.75, -0.15625},
					green = {0.75, 0.25},
				},
				wire = {
					red = {0.46875, -0.5},
					green = {0.46875, -0.09375},
				}
			},
			{
				shadow = {
					red = {0.75, 0.5625},
					green = {0.21875, 0.5625}
				},
				wire = {
					red = {0.28125, 0.15625},
					green = {-0.21875, 0.15625}
				}
			},
			{
				shadow = {
					red = {-0.03125, 0.28125},
					green = {-0.03125, -0.125},
				},
				wire = {
					red = {-0.46875, 0},
					green = {-0.46875, -0.40625},
				}
			}
		},
		circuit_connector_sprites = {
			circuit_connector_definitions["chest"].sprites,
			circuit_connector_definitions["chest"].sprites,
			circuit_connector_definitions["chest"].sprites,
			circuit_connector_definitions["chest"].sprites
		},
		circuit_wire_max_distance = 7.5
	},
	
	{
		type = "item",
		name = "factory-circuit-output",
		icon = graphicsDir.."/icon/factory-circuit-output.png",
		icon_size = 32,
		flags = {"goes-to-quickbar"},
		subgroup = "microfactorio",
		order = "c-b",
		place_result = "factory-circuit-output",
		stack_size = 50,
	},
	{
		type = "constant-combinator",
		name = "factory-circuit-output",
		icon = graphicsDir.."/icon/factory-circuit-output.png",
		icon_size = 32,
		flags = {"placeable-neutral", "player-creation"},
		minable = {hardness = 0.2, mining_time = 0.5, result = "factory-circuit-output"},
		max_health = 50,
		corpse = "small-remnants",

		collision_box = centered_square(0.7),
		selection_box = centered_square(1.0),

		item_slot_count = 15,

		sprites = {
			north = {
				filename = graphicsDir.."/utility/factory-combinators.png",
				x = 158,
				y = 63,
				width = 79,
				height = 63,
				frame_count = 1,
				shift = {0.140625, 0.140625},
			},
			east = {
				filename = graphicsDir.."/utility/factory-combinators.png",
				y = 63,
				width = 79,
				height = 63,
				frame_count = 1,
				shift = {0.140625, 0.140625},
			},
			south = {
				filename = graphicsDir.."/utility/factory-combinators.png",
				x = 237,
				y = 63,
				width = 79,
				height = 63,
				frame_count = 1,
				shift = {0.140625, 0.140625},
			},
			west = {
				filename = graphicsDir.."/utility/factory-combinators.png",
				x = 79,
				y = 63,
				width = 79,
				height = 63,
				frame_count = 1,
				shift = {0.140625, 0.140625},
			}
		},

		activity_led_sprites = {
			north = {
				filename = "__base__/graphics/entity/combinator/activity-leds/constant-combinator-LED-N.png",
				width = 11,
				height = 10,
				frame_count = 1,
				shift = {0.296875, -0.40625},
			},
			east = {
				filename = "__base__/graphics/entity/combinator/activity-leds/constant-combinator-LED-E.png",
				width = 14,
				height = 12,
				frame_count = 1,
				shift = {0.25, -0.03125},
			},
			south = {
				filename = "__base__/graphics/entity/combinator/activity-leds/constant-combinator-LED-S.png",
				width = 11,
				height = 11,
				frame_count = 1,
				shift = {-0.296875, -0.078125},
			},
			west = {
				filename = "__base__/graphics/entity/combinator/activity-leds/constant-combinator-LED-W.png",
				width = 12,
				height = 12,
				frame_count = 1,
				shift = {-0.21875, -0.46875},
			}
		},

		activity_led_light = {
			intensity = 0.2,
			size = 1,
		},

		activity_led_light_offsets = {
			{0.296875, -0.40625},
			{0.25, -0.03125},
			{-0.296875, -0.078125},
			{-0.21875, -0.46875}
		},

		circuit_wire_connection_points = {
			{
				shadow = {
					red = {0.15625, -0.28125},
					green = {0.65625, -0.25}
				},
				wire = {
					red = {-0.28125, -0.5625},
					green = {0.21875, -0.5625},
				}
			},
			{
				shadow = {
					red = {0.75, -0.15625},
					green = {0.75, 0.25},
				},
				wire = {
					red = {0.46875, -0.5},
					green = {0.46875, -0.09375},
				}
			},
			{
				shadow = {
					red = {0.75, 0.5625},
					green = {0.21875, 0.5625}
				},
				wire = {
					red = {0.28125, 0.15625},
					green = {-0.21875, 0.15625}
				}
			},
			{
				shadow = {
					red = {-0.03125, 0.28125},
					green = {-0.03125, -0.125},
				},
				wire = {
					red = {-0.46875, 0},
					green = {-0.46875, -0.40625},
				}
			}
		},

		circuit_wire_max_distance = 7.5
	},
	-- Factory requester chest
	{
		type = "item",
		name = "factory-requester-chest",
		icon = graphicsDir.."/icon/factory-requester-chest.png",
		icon_size = 32,
		flags = {"goes-to-quickbar"},
		subgroup = "microfactorio",
		order = "d-a",
		place_result = "factory-requester-chest",
		stack_size = 1,
	},
	{
		type = "logistic-container",
		name = "factory-requester-chest",
		icon = graphicsDir.."/icon/factory-requester-chest.png",
		icon_size = 32,
		flags = {"placeable-player", "player-creation"},
		minable = {hardness = 0.2, mining_time = 0.5, result = "factory-requester-chest"},
		max_health = 450,
		corpse = "small-remnants",
		collision_box = centered_square(0.7),
		selection_box = centered_square(1.0),
		inventory_size = 48,
		logistic_slots_count = 48,
		logistic_mode = "requester",
		open_sound = { filename = "__base__/sound/metallic-chest-open.ogg", volume=0.65 },
		close_sound = { filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.7 },
		vehicle_impact_sound =	{ filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 },
		picture =
		{
			filename = graphicsDir.."/utility/factory-requester-chest.png",
			priority = "extra-high",
			width = 38,
			height = 32,
			shift = {0.09375, 0}
		},
		circuit_wire_connection_point =
		{
			shadow =
			{
				red = {0.734375, 0.453125},
				green = {0.609375, 0.515625},
			},
			wire =
			{
				red = {0.40625, 0.21875},
				green = {0.40625, 0.375},
			}
		},
		circuit_wire_max_distance = 7.5,
		circuit_connector_sprites = circuit_connector_definitions["chest"].sprites,
	},
})

-- Factory blueprint bounds-marker
-- This object exists only so that factory-content blueprints don't have their
-- bounding box shrunk because they aren't filled all the way to the edges. It
-- is created as factories are being blueprinted, and deleted after the
-- blueprint is applied.
data:extend({
	{
		type = "item",
		name = "factory-bounds-marker",
		icon = graphicsDir.."/indicator/blue-dot.png",
		icon_size = 32,
		flags = {},
		subgroup = "microfactorio",
		order = "a-a",
		place_result = "factory-bounds-marker",
		stack_size = 1,
	},
	{
		type = "container",
		inventory_size=0,
		name = "factory-bounds-marker",
		icon = graphicsDir.."/indicator/blue-dot.png",
		icon_size = 32,
		flags = {"placeable-player", "player-creation"},
		max_health = 100,
		collision_box = centered_square(0.7),
		selection_box = centered_square(1.0),
		collision_mask = {},
		picture = {
			-- Placeholder
			filename = graphicsDir.."/indicator/blue-dot.png",
			priority = "extra-high",
			width = 32,
			height = 32,
			shift = {0,0}
		},
	}
})

-- Factory contents marker
-- This object exists only inside blueprints, to store the blueprint-string of
-- a factory in that blueprint. It inherits programmable-speaker and puts the
-- blueprint in the alert string. (Yes, that's a terrible hack.) When the
-- factory is built, any adjacent factory-contents-markers are applied, then
-- replaced with factory construction requester chests.
data:extend({
	{
		type = "item",
		name = "factory-contents-marker",
		icon = graphicsDir.."/icon/factory-requester-chest.png",
		icon_size = 32,
		flags = {},
		subgroup = "microfactorio",
		order = "a-a",
		place_result = "factory-contents-marker",
		stack_size = 1,
	},
	{
		type = "programmable-speaker",
		name = "factory-contents-marker",
		icon = graphicsDir.."/icon/factory-requester-chest.png",
		icon_size = 32,
		max_health = 1000,
		flags = {"placeable-player", "player-creation"},
		collision_mask = {},
		selection_box = centered_square(1.0),
		energy_source = {
			type = "electric",
			usage_priority = "secondary-input",
			emissions = 0,
			render_no_power_icon = false,
			render_no_network_icon = false,
		},
		energy_usage_per_tick = "0W",
		sprite = blank(),
		maximum_polyphony = 0,
		instruments = {},
		picture = blank(),
	}
})

-- Factory construction requester chest
-- A requester chest which auto-updates its request to match the ghosts inside
-- an adjacent factory, and which uses items inside it to build those ghosts.
data:extend({
	{
		type = "item",
		name = "factory-construction-requester-chest",
		icon = graphicsDir.."/icon/factory-requester-chest.png",
		icon_size = 32,
		flags = {"goes-to-quickbar"},
		subgroup = "microfactorio",
		order = "d-a",
		place_result = "factory-construction-requester-chest",
		stack_size = 50,
	},
	{
		type = "logistic-container",
		name = "factory-construction-requester-chest",
		icon = graphicsDir.."/icon/factory-requester-chest.png",
		icon_size = 32,
		flags = {"placeable-player", "player-creation"},
		minable = {hardness = 0.2, mining_time = 0.5, result = "factory-construction-requester-chest"},
		max_health = 450,
		corpse = "small-remnants",
		collision_box = centered_square(0.7),
		selection_box = centered_square(1.0),
		inventory_size = 48,
		logistic_slots_count = 48,
		logistic_mode = "requester",
		open_sound = { filename = "__base__/sound/metallic-chest-open.ogg", volume=0.65 },
		close_sound = { filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.7 },
		vehicle_impact_sound =	{ filename = "__base__/sound/car-metal-impact.ogg", volume = 0.65 },
		picture =
		{
			filename = graphicsDir.."/utility/factory-requester-chest.png",
			priority = "extra-high",
			width = 38,
			height = 32,
			shift = {0.09375, 0}
		},
		circuit_wire_connection_point =
		{
			shadow =
			{
				red = {0.734375, 0.453125},
				green = {0.609375, 0.515625},
			},
			wire =
			{
				red = {0.40625, 0.21875},
				green = {0.40625, 0.375},
			}
		},
		circuit_wire_max_distance = 7.5,
		circuit_connector_sprites = circuit_connector_definitions["chest"].sprites,
	},
})
