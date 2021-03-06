require("config")
local Config = GetConfigs()

require("layout")
local HasLayout = HasLayout

require("connections")
local Connections = Connections

require("updates")
local Updates = Updates

require("constants")

require("mod-gui")

require("connections")

local BlueprintString = require("blueprintstring.blueprintstring")
local serpent = require "blueprintstring.serpent0272"

-- DATA STRUCTURE --

-- Factory buildings are entities of type "storage-tank" internally, because reasons
local BUILDING_TYPE = "storage-tank"

--[[
factory = {
	+outside_surface = *,
	+outside_x = *,
	+outside_y = *,
	+outside_door_x = *,
	+outside_door_y = *,
	
	+inside_surface = *,
	+inside_x = *,
	+inside_y = *,
	+inside_door_x = *,
	+inside_door_y = *,
	
	+force = *,
	+layout = *,
	+building = *,
	+outside_energy_sender = *,
	+outside_energy_receiver = *,
	+outside_overlay_displays = {*},
	+outside_fluid_dummy_connectors = {*},
	+outside_port_markers = {*},
	(+)outside_other_entities = {*},
	
	+inside_energy_sender = *,
	+inside_energy_receiver = *,
	+inside_overlay_controllers = {*},
	+inside_fluid_dummy_connectors = {*},
	(+)inside_other_entities = {*},
	+energy_indicator = *,
	
	+transfer_rate = *,
	+transfers_outside = *,
	+stored_pollution = *,
	
	+connections = {*},
	+connection_settings = {{*}*},
	+connection_indicators = {*},
	
	+upgrades = {},
}
]]--


-- INITIALIZATION --

local function init_globals()
	-- List of all factories
	global.factories = global.factories or {}
	-- Map: Save name -> Factory it is currently saving
	global.saved_factories = global.saved_factories or {}
	-- Map: Player or robot -> Save name to give him on the next relevant event
	global.pending_saves = global.pending_saves or {}
	-- Map: Entity unit number -> Factory it is a part of
	global.factories_by_entity = global.factories_by_entity or {}
	-- Map: Surface name -> list of factories on it
	global.surface_factories = global.surface_factories or {}
	-- Map: Surface name -> number of used factory spots on it
	global.surface_factory_counters = global.surface_factory_counters or {}
	-- Scalar
	global.next_factory_surface = global.next_factory_surface or 0
	-- Map: Player index -> Last teleport time
	global.last_player_teleport = global.last_player_teleport or {}
	-- Map: Player index -> Whether preview is activated
	global.player_preview_active = global.player_preview_active or {}
	-- List of all construction-requester chests
	global.construction_requester_chests = global.construction_requester_chests or {}
end

local prepare_gui = 0  -- Will be set to a function lower in the file

local function init_gui()
	for _, player in pairs(game.players) do
		prepare_gui(player)
	end
end

script.on_init(function()
	init_globals()
	Connections.init_data_structure()
	Updates.init()
	init_gui()
end)

script.on_configuration_changed(function(config_changed_data)
	init_globals()
	Updates.run()
	init_gui()
	for surface_name, _ in pairs(global.surface_factories or {}) do
		if remote.interfaces["RSO"] then -- RSO compatibility
			pcall(remote.call, "RSO", "ignoreSurface", surface_name)
		end
	end
end)

-- DATA MANAGEMENT --

local function set_entity_to_factory(entity, factory)
	global.factories_by_entity[entity.unit_number] = factory
end

local function get_factory_by_entity(entity)
	if entity == nil then return nil end
	return global.factories_by_entity[entity.unit_number]
end

local function get_factory_by_building(entity)
	local factory = global.factories_by_entity[entity.unit_number]
	if factory == nil then
		game.print("ERROR: Unbound factory building: " .. entity.name .. "@" .. entity.surface.name .. "(" .. entity.position.x .. ", " .. entity.position.y .. ")")
	end	
	return factory
end

local function find_factory_by_building(surface, area)
	local candidates = surface.find_entities_filtered{area=area, type=BUILDING_TYPE}
	for _,entity in pairs(candidates) do
		if HasLayout(entity.name) then return get_factory_by_building(entity) end
	end
	return nil
end

local function find_surrounding_factory(surface, position)
	local factories = global.surface_factories[surface.name]
	if factories == nil then return nil end
	local x = math.floor(0.5+position.x/(16*32))
	local y = math.floor(0.5+position.y/(16*32))
	if (x > 7 or x < 0) then return nil end
	return factories[8*y+x+1]
end

-- POWER MANAGEMENT --

local function make_valid_transfer_rate(rate)
	for _,v in pairs(Constants.VALID_POWER_TRANSFER_RATES) do
		if v == rate then return v end
	end
	return 0 -- Catchall
end

local function update_power_settings(factory)
	if factory.built then
		local layout = factory.layout
		-- Inside sender
		local new_ies = factory.inside_surface.create_entity{
			name = "factory-power-output-2-" .. factory.transfer_rate,
			position = {factory.inside_x + layout.inside_energy_x, factory.inside_y + layout.inside_energy_y},
			force = force
		}
		new_ies.destructible = false
		new_ies.operable = false
		new_ies.rotatable = false
		if factory.inside_energy_sender.valid then
			factory.inside_energy_sender.destroy()
		end
		factory.inside_energy_sender = new_ies

		-- Inside receiver
		local new_ier = factory.inside_surface.create_entity{
			name = "factory-power-input-2-" .. factory.transfer_rate,
			position = {factory.inside_x + layout.inside_energy_x, factory.inside_y + layout.inside_energy_y},
			force = force
		}
		new_ier.destructible = false
		new_ier.operable = false
		new_ier.rotatable = false
		if factory.inside_energy_receiver.valid then
			factory.inside_energy_receiver.destroy()
		end
		factory.inside_energy_receiver = new_ier

		-- Outside sender
		local new_oes = factory.outside_surface.create_entity{
			name = layout.outside_energy_sender_type .. "-" .. factory.transfer_rate,
			position = {factory.outside_x, factory.outside_y},
			force = factory.force
		}
		new_oes.destructible = false
		new_oes.operable = false
		new_oes.rotatable = false
		if factory.outside_energy_sender.valid then
			factory.outside_energy_sender.destroy()
		end
		factory.outside_energy_sender = new_oes

		-- Outside receiver
		local new_oer = factory.outside_surface.create_entity{
			name = layout.outside_energy_receiver_type .. "-" .. factory.transfer_rate,
			position = {factory.outside_x, factory.outside_y},
			force = factory.force
		}
		new_oer.destructible = false
		new_oer.operable = false
		new_oer.rotatable = false
		if factory.outside_energy_receiver.valid then
			factory.outside_energy_receiver.destroy()
		end
		factory.outside_energy_receiver = new_oer

		local e = factory.transfer_rate*16667 -- conversion factor of MW to J/U
		if factory.transfers_outside then
			factory.inside_energy_sender.energy = 0--e
			factory.inside_energy_receiver.energy = 0
			factory.outside_energy_sender.energy = 0
			factory.outside_energy_receiver.energy = 0--e
		else
			factory.inside_energy_sender.energy = 0
			factory.inside_energy_receiver.energy = 0--e
			factory.outside_energy_sender.energy = 0--e
			factory.outside_energy_receiver.energy = 0
		end
	end
	if factory.energy_indicator and factory.energy_indicator.valid then
		factory.energy_indicator.destroy()
		factory.energy_indicator = nil
	end
	local direction = (factory.transfers_outside and defines.direction.south) or defines.direction.north
	local energy_indicator = factory.inside_surface.create_entity{
		name = "factory-connection-indicator-energy-d" .. make_valid_transfer_rate(factory.transfer_rate),
		direction = direction, force = factory.force,
		position = {x = factory.inside_x + factory.layout.energy_indicator_x, y = factory.inside_y + factory.layout.energy_indicator_y}
	}
	energy_indicator.destructible = false
	factory.energy_indicator = energy_indicator
end

local function adjust_power_transfer_rate(factory, positive)
	local transfer_rate = factory.transfer_rate
	if positive then
		for i = 1,#Constants.VALID_POWER_TRANSFER_RATES do
			if transfer_rate < Constants.VALID_POWER_TRANSFER_RATES[i] then
				transfer_rate = Constants.VALID_POWER_TRANSFER_RATES[i]
				break
			end
		end
		if transfer_rate > Constants.VALID_POWER_TRANSFER_RATES[#Constants.VALID_POWER_TRANSFER_RATES] then
			transfer_rate = Constants.VALID_POWER_TRANSFER_RATES[#Constants.VALID_POWER_TRANSFER_RATES]
		end
	else
		for i = #Constants.VALID_POWER_TRANSFER_RATES,1,-1 do
			if transfer_rate > Constants.VALID_POWER_TRANSFER_RATES[i] then
				transfer_rate = Constants.VALID_POWER_TRANSFER_RATES[i]
				break
			end
		end
		if transfer_rate < Constants.VALID_POWER_TRANSFER_RATES[1] then
			transfer_rate = Constants.VALID_POWER_TRANSFER_RATES[1]
		end
	end
	factory.transfer_rate = transfer_rate
	local power_string, transfer_text = "",""
	if transfer_rate >= 1000 then
		power_string = (transfer_rate / 1000) .. "GW"
	else
		power_string = transfer_rate .. "MW"
	end
	if positive then
		transfer_text = "factory-connection-text.power-transfer-increased"
	else
		transfer_text = "factory-connection-text.power-transfer-decreased"
	end
	factory.inside_surface.create_entity{
		name = "flying-text",
		position = {x = factory.inside_x + factory.layout.energy_indicator_x, y = factory.inside_y + factory.layout.energy_indicator_y}, color = {r = 228/255, g = 236/255, b = 0},
		text = {transfer_text, power_string}
	}
	update_power_settings(factory)
end

-- FACTORY UPGRADES --

--[[
local function build_power_upgrade(factory)
	if factory.upgrades.power then return end
	factory.upgrades.power = true
	local iet = factory.inside_surface.create_entity{name = "factory-power-pole", position = {factory.inside_x + factory.layout.inside_energy_x, factory.inside_y + factory.layout.inside_energy_y}, force = factory.force}
	iet.destructible = false
	table.insert(factory.inside_other_entities, iet)
end
]]--

local function build_lights_upgrade(factory)
	if factory.upgrades.lights then return end
	factory.upgrades.lights = true
	for _, pos in pairs(factory.layout.lights) do
		local light = factory.inside_surface.create_entity{name = "factory-ceiling-light", position = {factory.inside_x + pos.x, factory.inside_y + pos.y}, force = factory.force}
		light.destructible = false
		light.operable = false
		light.rotatable = false
		table.insert(factory.inside_other_entities, light)
	end
end

local function build_display_upgrade(factory)
	if factory.upgrades.display then return end
	factory.upgrades.display = true
	for id, pos in pairs(factory.layout.overlays) do
		local controller = factory.inside_surface.create_entity {
			name = "factory-overlay-controller",
			position = {factory.inside_x + pos.inside_x, factory.inside_y + pos.inside_y},
			force = factory.force
		}
		controller.destructible = false
		controller.rotatable = false
		factory.inside_overlay_controllers[id] = controller
	end
end

-- OVERLAY MANAGEMENT --

local function update_overlay(factory)
	if factory.built then
		-- Do it this way because the controllers might not exist yet
		for id, controller in pairs(factory.inside_overlay_controllers) do
			local display = factory.outside_overlay_displays[id]
			if controller.valid and display and display.valid then
				local behavior = controller.get_control_behavior()
				local display_behavior = display.get_control_behavior()
				
				for i=1,Constants.overlay_slot_count do
					local signal = behavior.get_signal(i)
					if display_behavior and signal and signal.signal then
						display_behavior.set_signal(i, signal)
					else
						display_behavior.set_signal(i, nil)
					end
				end
			end
		end
		
		remove_port_markers(factory)
		add_port_markers(factory)
	end
end

-- FACTORY GENERATION --

local function create_factory_position()
	global.next_factory_surface = global.next_factory_surface + 1
	if (global.next_factory_surface > Config.max_surfaces) then
		global.next_factory_surface = 1
	end
	local surface_name = "Factory floor " .. global.next_factory_surface
	local surface = game.surfaces[surface_name]
	if surface == nil then
		if #(game.surfaces) < 256 then
			surface = game.create_surface(surface_name, {width = 2, height = 2})
			surface.daytime = 0.5
			surface.freeze_daytime = true
			if remote.interfaces["RSO"] then -- RSO compatibility
				pcall(remote.call, "RSO", "ignoreSurface", surface_name)
			end
		else
			global.next_factory_surface = 1
			surface_name = "Factory floor 1"
			surface = game.surfaces[surface_name]
			if surface == nil then
				error("Unfortunately you have no available surfaces left for Microfactorio. You cannot use Microfactorio on this map.")
			end
		end
	end
	local n = global.surface_factory_counters[surface_name] or 0
	global.surface_factory_counters[surface_name] = n+1
	local cx = 16*(n % 8)
	local cy = 16*math.floor(n / 8)
	
	-- To make void chunks show up on the map, you need to tell them they've finished generating.
	for xi=-2,1 do
	for yi=-2,1 do
		surface.set_chunk_generated_status({cx+xi, cy+yi}, defines.chunk_generated_status.entities)
	end end
	
	local factory = {}
	factory.inside_surface = surface
	factory.inside_x = 32*cx
	factory.inside_y = 32*cy
	factory.stored_pollution = 0
	factory.upgrades = {}

	global.surface_factories[surface_name] = global.surface_factories[surface_name] or {}
	global.surface_factories[surface_name][n+1] = factory
	local fn = #(global.factories)+1
	global.factories[fn] = factory
	factory.id = fn

	return factory
end

local function add_tile_rect(tiles, tile_name, xmin, ymin, xmax, ymax) -- tiles is rw
	local i = #tiles
	for x = xmin, xmax-1 do
		for y = ymin, ymax-1 do
			i = i + 1
			tiles[i] = {name = tile_name, position = {x, y}}
		end
	end
end

local function add_tile_mosaic(tiles, tile_name, xmin, ymin, xmax, ymax, pattern) -- tiles is rw
	local i = #tiles
	for x = 0, xmax-xmin-1 do
		for y = 0, ymax-ymin-1 do
			if (string.sub(pattern[y+1],x+1, x+1) == "+") then
				i = i + 1
				tiles[i] = {name = tile_name, position = {x+xmin, y+ymin}}
			end
		end
	end
end

local function create_factory_interior(layout, force)
	local factory = create_factory_position()
	factory.layout = layout
	factory.force = force
	factory.inside_door_x = layout.inside_door_x + factory.inside_x
	factory.inside_door_y = layout.inside_door_y + factory.inside_y
	local tiles = {}
	for _, rect in pairs(layout.rectangles) do
		add_tile_rect(tiles, rect.tile, rect.x1 + factory.inside_x, rect.y1 + factory.inside_y, rect.x2 + factory.inside_x, rect.y2 + factory.inside_y)
	end
	for _, mosaic in pairs(layout.mosaics) do
		add_tile_mosaic(tiles, mosaic.tile, mosaic.x1 + factory.inside_x, mosaic.y1 + factory.inside_y, mosaic.x2 + factory.inside_x, mosaic.y2 + factory.inside_y, mosaic.pattern)
	end
	for _, cpos in pairs(layout.connections) do
		table.insert(tiles, {name = layout.connection_tile, position = {factory.inside_x + cpos.inside_x, factory.inside_y + cpos.inside_y}})
	end
	factory.inside_surface.set_tiles(tiles)

	local ier = factory.inside_surface.create_entity{name = "factory-power-input-2-10", position = {factory.inside_x + layout.inside_energy_x, factory.inside_y + layout.inside_energy_y}, force = force}
	ier.destructible = false
	ier.operable = false
	ier.rotatable = false
	factory.inside_energy_receiver = ier
	
	local ies = factory.inside_surface.create_entity{name = "factory-power-output-2-10", position = {factory.inside_x + layout.inside_energy_x, factory.inside_y + layout.inside_energy_y}, force = force}
	ies.destructible = false
	ies.operable = false
	ies.rotatable = false
	factory.inside_energy_sender = ies
	
	local iet = factory.inside_surface.create_entity{name = "factory-power-pole", position = {factory.inside_x + layout.inside_energy_x, factory.inside_y + layout.inside_energy_y}, force = force}
	iet.destructible = false
	
	factory.inside_other_entities = {iet}
	
	--if force.technologies["factory-interior-upgrade-power"].researched then
	--	build_power_upgrade(factory)
	--end
	
	if force.technologies["factory-interior-upgrade-lights"].researched then
		build_lights_upgrade(factory)
	end
	
	factory.inside_overlay_controllers = {}
	
	if force.technologies["factory-interior-upgrade-display"].researched then
		build_display_upgrade(factory)
	end
	
	factory.inside_fluid_dummy_connectors = {}
	
	for id, cpos in pairs(layout.connections) do
		local connector = factory.inside_surface.create_entity{name = "factory-fluid-dummy-connector", position = {factory.inside_x + cpos.inside_x + cpos.indicator_dx, factory.inside_y + cpos.inside_y + cpos.indicator_dy}, force = force, direction = cpos.direction_in}
		connector.destructible = false
		connector.operable = false
		connector.rotatable = false
		factory.inside_fluid_dummy_connectors[id] = connector
	end
	
	factory.transfer_rate = factory.layout.default_power_transfer_rate or 10 -- MW
	factory.transfers_outside = false
	
	factory.connections = {}
	factory.connection_settings = {}
	factory.connection_indicators = {}
	
	return factory
end

local function destroy_factory_interior(factory)
	-- TODO
end

function create_factory_exterior(factory, building)
	local layout = factory.layout
	local force = factory.force
	factory.outside_x = building.position.x
	factory.outside_y = building.position.y
	factory.outside_door_x = factory.outside_x + layout.outside_door_x
	factory.outside_door_y = factory.outside_y + layout.outside_door_y
	factory.outside_surface = building.surface
	
	local oer = factory.outside_surface.create_entity{name = layout.outside_energy_receiver_type .. "-10", position = {factory.outside_x, factory.outside_y}, force = force}
	oer.destructible = false
	oer.operable = false
	oer.rotatable = false
	factory.outside_energy_receiver = oer
	
	local oes = factory.outside_surface.create_entity{name = layout.outside_energy_sender_type .. "-10", position = {factory.outside_x, factory.outside_y}, force = force}
	oes.destructible = false
	oes.operable = false
	oes.rotatable = false
	factory.outside_energy_sender = oes
	
	factory.outside_overlay_displays = {}
	
	for id, pos in pairs(layout.overlays) do
		local display = factory.outside_surface.create_entity {
			name = "factory-overlay-display-"..pos.outside_size,
			position = {factory.outside_x + pos.outside_x, factory.outside_y + pos.outside_y},
			force = force
		}
		display.destructible = false
		display.operable = false
		display.rotatable = false
		factory.outside_overlay_displays[id] = display
	end
	
	factory.outside_fluid_dummy_connectors = {}
	
	for id, cpos in pairs(layout.connections) do
		local name = ((cpos.direction_out == defines.direction.south and "factory-fluid-dummy-connector-south") or "factory-fluid-dummy-connector")
		local connector = factory.outside_surface.create_entity{name = name, position = {factory.outside_x + cpos.outside_x - cpos.indicator_dx, factory.outside_y + cpos.outside_y - cpos.indicator_dy}, force = force, direction = cpos.direction_out}
		connector.destructible = false
		connector.operable = false
		connector.rotatable = false
		factory.outside_fluid_dummy_connectors[id] = connector
	end

	-- local overlay = factory.outside_surface.create_entity{name = factory.layout.overlay_name, position = {factory.outside_x + factory.layout.overlay_x, factory.outside_y + factory.layout.overlay_y}, force = force}
	-- overlay.destructible = false
	-- overlay.operable = false
	-- overlay.rotatable = false
	
	-- factory.outside_other_entities = {overlay}
	factory.outside_other_entities = {}

	factory.outside_port_markers = {}
	
	set_entity_to_factory(building, factory)
	factory.building = building
	factory.built = true
	
	update_power_settings(factory)
	Connections.recheck_factory(factory, nil, nil)
	update_overlay(factory)
	return factory
end

local function toggle_port_markers(factory)
	if not factory.built then return end
	if #(factory.outside_port_markers) == 0 then
		add_port_markers(factory)
	else
		remove_port_markers(factory)
	end
end

function remove_port_markers(factory)
	for _, entity in pairs(factory.outside_port_markers) do entity.destroy() end
	factory.outside_port_markers = {}
end

function add_port_markers(factory)
	for cid, cpos in pairs(factory.layout.connections) do
		local indicator = Connections.get_port_marker_type(factory, cid)
		game.print("Indicator is "..indicator)
		
		local indicator_direction
		local indicator_position
		if indicator == "disconnected" then
			-- TODO: Something aesthetic for the "disconnected" case
		elseif indicator == "bidirectional" then
			-- TODO: Something more aesthetic for the bidirectional-connection
			-- case than just putting two arrows on top of each other
			local marker = factory.outside_surface.create_entity {
				name = "factory-port-marker",
				position  = {
					factory.outside_x + cpos.outside_x-cpos.indicator_dx,
					factory.outside_y + cpos.outside_y-cpos.indicator_dy
				},
				force = factory.force,
				direction = cpos.direction_out
			}
			marker.destructible = false
			marker.operable = false
			marker.rotatable = false
			marker.active = false
			table.insert(factory.outside_port_markers, marker)
			
			local marker2 = factory.outside_surface.create_entity {
				name = "factory-port-marker",
				position  = {
					factory.outside_x + cpos.outside_x,
					factory.outside_y + cpos.outside_y
				},
				force = factory.force,
				direction = cpos.direction_in
			}
			marker2.destructible = false
			marker2.operable = false
			marker2.rotatable = false
			marker2.active = false
			table.insert(factory.outside_port_markers, marker2)
		elseif indicator == "out" then
			indicator_direction = cpos.direction_out
			indicator_position = {
				factory.outside_x + cpos.outside_x-cpos.indicator_dx,
				factory.outside_y + cpos.outside_y-cpos.indicator_dy
			}
			local marker = factory.outside_surface.create_entity {
				name = "factory-port-marker",
				position = indicator_position,
				force = factory.force,
				direction = indicator_direction
			}
			marker.destructible = false
			marker.operable = false
			marker.rotatable = false
			marker.active = false
			table.insert(factory.outside_port_markers, marker)
		else
			indicator_direction = cpos.direction_in
			indicator_position = {
				factory.outside_x + cpos.outside_x,
				factory.outside_y + cpos.outside_y
			}
			local marker = factory.outside_surface.create_entity {
				name = "factory-port-marker",
				position = indicator_position,
				force = factory.force,
				direction = indicator_direction
			}
			marker.destructible = false
			marker.operable = false
			marker.rotatable = false
			marker.active = false
			table.insert(factory.outside_port_markers, marker)
		end
	end
end

local function is_factory_component_entity(entity)
	if (entity.name == "factory-ceiling-light"
	    or entity.name == "factory-power-pole"
	    or entity.name == "factory-overlay-controller"
	    or string.find(entity.name, "factory-fluid-dummy-connector", 1, true)
	    or string.find(entity.name, "factory-overlay-display-", 1, true)
	    or string.find(entity.name, "factory-power-input-", 1, true)
	    or string.find(entity.name, "factory-power-output-", 1, true)) then
		return true
	else
		return false
	end
end

-- Returns whether a factory is empty, that is, whether it is free of entities
-- other than blueprint ghosts.
local function factory_is_empty(factory)
	local inside_area = get_factory_inside_area(factory)
	local contents = factory.inside_surface.find_entities(inside_area)
	for _,entity in pairs(contents) do
		if entity.name ~= "entity-ghost" and not is_factory_component_entity(entity) then
			return false
		end
	end
	
	return true
end

-- Given a factory which may contain blueprint ghosts but is otherwise empty,
-- clear it (removing any blueprint ghosts).
local function clear_factory_ghosts(factory)
	local inside_area = get_factory_inside_area(factory)
	local contents = factory.inside_surface.find_entities(inside_area)
	for _,entity in pairs(contents) do
		if entity.name == "entity-ghost" then
			entity.order_deconstruction(factory.force)
		end
	end
end

local function add_inventory(items_list, inventory)
	if inventory ~= nil then
		for name,count in pairs(inventory.get_contents()) do
			incr_default_0(items_list, name, count)
		end
	end
end

local teleport_blacklist = list_to_index({
	"storage-tank",
	"underground-belt", "transport-belt", "splitter", "loader",
	"assembling-machine", "pipe", "pipe-to-ground", "pump", "generator", "boiler", "fluid-turret",
	"straight-rail", "curved-rail",
	"rail-signal", "rail-chain-signal", "train-stop",
	"wall", "gate",
})

local rotate_factory_blacklist = list_to_index({
	"straight-rail", "curved-rail", "locomotive"
})

local function can_teleport(entity_name, proto_name)
	if HasLayout(entity_name) then return true end
	
	if teleport_blacklist[proto_name] then return false end
	
	-- local prototype = game.entity_prototypes[proto_name]
	-- if not prototype then return false end
	
	return true
end

local all_inventories = {
	defines.inventory.fuel, defines.inventory.burnt_result,
	defines.inventory.chest, defines.inventory.furnace_source,
	defines.inventory.furnace_result, defines.inventory.furnace_modules,
	defines.inventory.roboport_robot, defines.inventory.roboport_material,
	defines.inventory.robot_cargo, defines.inventory.robot_repair,
	defines.inventory.assembling_machine_input, defines.inventory.assembling_machine_output,
	defines.inventory.assembling_machine_modules, defines.inventory.lab_input,
	defines.inventory.lab_modules, defines.inventory.mining_drill_modules,
	defines.inventory.item_main, defines.inventory.rocket_silo_rocket,
	defines.inventory.rocket_silo_result, defines.inventory.car_trunk,
	defines.inventory.car_ammo, defines.inventory.cargo_wagon,
	defines.inventory.turret_ammo, defines.inventory.beacon_modules
}

-- Deconstruct all the buildings inside a factory, then return the items they
-- were made from.
local function deconstruct_factory_contents(factory)
	local inside_area = get_factory_inside_area(factory)
	local contents = factory.inside_surface.find_entities(inside_area)
	local items_generated = {}
	-- TODO: Handle tiles
	for _,entity in pairs(contents) do
		if entity.name == "entity-ghost" then
			entity.order_deconstruction(factory.force)
		elseif is_factory_component_entity(entity) then
			-- Skip
		else
			local skip = false
			if entity.name=="item-on-ground" then
				incr_default_0(items_generated, entity.stack.name, entity.stack.count)
				skip = true
			elseif entity.prototype.type=="inserter" then
				if entity.valid and entity.held_stack and entity.held_stack.valid_for_read then
					incr_default_0(items_generated, entity.held_stack.name, entity.held_stack.count)
				end
			elseif entity.prototype.type=="transport-belt" then
				add_inventory(items_generated, entity.get_transport_line(1))
				add_inventory(items_generated, entity.get_transport_line(2))
			end
			
			if entity.has_items_inside() then
				for _,inventory_id in ipairs(all_inventories) do
					local inventory = entity.get_inventory(inventory_id)
					if inventory then
						add_inventory(items_generated, inventory)
					end
				end
			end
			
			if not skip then
				incr_default_0(items_generated, entity.name, 1)
			end
			-- TODO: Handle recursive factories?
			entity.destroy()
		end
	end
	
	return items_generated
end

local function serialize_inventory(inventory)
	if not inventory then return nil end
	if inventory.get_item_count()==0 then return nil end
	return inventory.get_contents()
end

local function filter_blueprint_reconstructed_only(blueprint_string)
	local deserialized_blueprint = BlueprintString.fromString(blueprint_string)
	local filtered_entities = {}
	
	for _,entity in ipairs(deserialized_blueprint.entities) do
		local proto = game.entity_prototypes[entity.name]
		if entity.name == "factory-bounds-marker" then
			table.insert(filtered_entities, entity)
		elseif proto then
			if not can_teleport(entity.name, proto.type) then
				table.insert(filtered_entities, entity)
			end
		else
			game.print("Cannot rotate "..entity.name.." inside factory building")
		end
	end
	
	deserialized_blueprint.entities = filtered_entities
	return BlueprintString.toString(deserialized_blueprint)
end

local function rotate_position(factory, position)
	-- Translate into factory coords
	local x = position.x - factory.inside_x
	local y = position.y - factory.inside_y
	-- Rotate
	local rotated_x = -y
	local rotated_y = x
	-- Translate back to world coords
	return {
		rotated_x + factory.inside_x,
		rotated_y + factory.inside_y
	}
end

local function describe_for_reconstruction(entity, spill_surface, spill_position)
	local result = {
		name = entity.name,
		position = entity.position,
		force = entity.force,
		direction = entity.direction,
		health = entity.health,
		energy = entity.energy,
		temperature = entity.temperature,
		old_entity = entity,
		was_teleported = false
	}
	
	if entity.prototype.type == "underground-belt" then
		result.belt_to_ground_type = entity.belt_to_ground_type
	end
	if entity.prototype.type == "underground-belt" or entity.prototype.type == "transport-belt" or entity.prototype.type == "loader" or entity.prototype.type == "splitter" then
		result.belt_contents = {}

		local num_transport_lines = 2
		if entity.prototype.type == "splitter" then
			num_transport_lines = 8
		end

		for transport_line_index=1,num_transport_lines do
			--result.belt_contents[transport_line_index] = {}
			local transport_line = entity.get_transport_line(transport_line_index)
			if transport_line then
				local num_items = transport_line.get_item_count()
				for ii=1,num_items do
					local item = transport_line[ii]
					if item then
						spill_surface.spill_item_stack(spill_position, item)
					end
				end
				transport_line.clear()
			end
		end
	end
	if entity.name == "item-on-ground" then
		result.stack = {
			name = entity.stack.name,
			count = entity.stack.count
		}
	end
	if entity.prototype.type == "loader" then
		result.loader_type = entity.loader_type
	end
	--if entity.prototype.type == "assembling-machine" then
	--	if entity.recipe then
	--		result.recipe = entity.recipe.name
	--	end
	--end
	if entity.has_items_inside() then
		result.inventories = {}
		for _,inventory_id in ipairs(all_inventories) do
			local inventory = serialize_inventory(entity.get_inventory(inventory_id))
			if inventory then
				result.inventories[inventory_id] = inventory
			end
		end
	end
	
	-- Record wire connections
	if entity.circuit_connection_definitions then
		result.circuit_connection_definitions = entity.circuit_connection_definitions
	else
		result.circuit_connection_definitions = {}
	end

	return result
end

local function reconstruct_entity(factory, description, rotation_amount)
	local rotation_8dir = 2*orientation_to_rotation_count(rotation_amount)

	if description.name == "loader" and description.loader_type=="output" then
		-- With loaders, orientation is a more complex thing because there's an
		-- extra variable (input/output) which reverses the belt direction.
		-- So if it's an output loader, the creation direction needs to be
		-- reversed.
		rotation_8dir = rotation_8dir+4
	end
	local entity_create_params = {
		name = description.name,
		position = rotate_position(factory, description.position),
		force = description.force,
		direction = (description.direction+rotation_8dir)%8
	}
	local prototype = game.entity_prototypes[description.name]
	if prototype.type == "underground-belt" then
		entity_create_params.type = description.belt_to_ground_type
	end
	if description.name == "item-on-ground" then
		entity_create_params.stack = description.stack
	end
	
	local entity = factory.inside_surface.create_entity(entity_create_params)
	if not entity then
		game.print("Failed to recreate moved entity "..entity_create_params.name.." when rotating factory contents")
		return
	end
	entity.health = description.health
	entity.energy = description.energy
	entity.temperature = description.temperature
	
	if entity.prototype.type == "loader" then
		entity.loader_type = description.loader_type
	end
	if description.inventories then
		for inventory_id,contents in pairs(description.inventories) do
			local inventory = entity.get_inventory(inventory_id)
			if inventory and inventory.is_empty() then
				for item,count in pairs(contents) do
					inventory.insert({name=item, count=count})
				end
			end
		end
	end
	
	entity.copy_settings(description.old_entity)
	return entity
end

local function can_rotate_factory(factory)
	local inside_area = get_factory_inside_area(factory)
	local inside_entities = factory.inside_surface.find_entities(inside_area)

	for _,entity in ipairs(inside_entities) do
		if entity.valid then
			if HasLayout(entity.name) then
				local subfactory = get_factory_by_building(entity)
				if not can_rotate_factory(subfactory) then
					return false
				end
			else
				if rotate_factory_blacklist[entity.prototype.name] then
					return false
				end
			end
		end
	end

	return true
end

local function rotate_factory(factory, rotation_amount)
	local rotation_8dir = 2*orientation_to_rotation_count(rotation_amount)
	local inside_area = get_factory_inside_area(factory)
	local inside_entities = factory.inside_surface.find_entities(inside_area)
	local outside_surface = factory.outside_surface
	local outside_position = {x=factory.outside_x, y=factory.outside_y}
	
	-- Save anything that can't be teleported
	local reconstructed_entities = {}
	for _,entity in ipairs(inside_entities) do
		if is_factory_component_entity(entity) then
			-- Skip
		--elseif not can_teleport(entity.name, entity.prototype.type) then
		else
			reconstructed_entities[entity] = describe_for_reconstruction(entity, outside_surface, outside_position)
		end
	end

	-- Disconnect all wires
	for _,entity in ipairs(inside_entities) do
		if entity.circuit_connection_definitions then
			for _,connection in pairs(entity.circuit_connection_definitions) do
				entity.disconnect_neighbour({
					wire = connection.wire,
					target_entity = connection.target_entity,
					source_circuit_id = connection.source_circuit_id,
					target_circuit_id = connection.target_circuit_id 
				})
			end
		end
	end
	
	-- Create a blueprint which captures the factory contents
	local blueprint_string = factory_to_blueprint_string(factory, factory.force)
	
	-- Filter the blueprint to only contain things that can't be teleported
	blueprint_string = filter_blueprint_reconstructed_only(blueprint_string)
	
	-- Move teleported entities
	for _,entity in pairs(inside_entities) do
		if entity.valid then
			if is_factory_component_entity(entity) then
				-- Skip
			else
				local rotated_position = rotate_position(factory, entity.position)
				
				if HasLayout(entity.name) then
					reconstructed_entities[entity].was_teleported = true

					-- If this is a recursive factory building, update it
					local nested_factory = get_factory_by_building(entity)
					cleanup_factory_exterior(nested_factory, entity)
					-- entity.teleport(rotated_position)
					
					local entity_name = entity.name
					entity.destroy()
					entity = factory.inside_surface.create_entity {
						name = entity_name,
						position = rotated_position
					}
					
					create_factory_exterior(nested_factory, entity)
					rotate_factory(nested_factory, rotation_amount)
				else
					if entity.teleport(rotated_position) then
						reconstructed_entities[entity].was_teleported = true
						if entity.valid and entity.supports_direction then
							entity.direction = (entity.direction+rotation_8dir) % 8
						end
					end
				end
			end
		end
	end
	
	-- Apply the blueprint, but rotated
	if blueprint_string then
		apply_blueprint_to_factory(factory, factory.force, blueprint_string, 0.25)
	end
	
	-- Reconstruct entities that couldn't be teleported
	local entity_map = {}
	for _,desc in pairs(reconstructed_entities) do
		if (desc.was_teleported) then
			entity_map[desc.old_entity] = desc.old_entity
		else
			local new_entity = reconstruct_entity(factory, desc, rotation_amount)
			entity_map[desc.old_entity] = new_entity
		end
	end

	-- Reconnect wires
	for _,old_entity in ipairs(inside_entities) do
		if not old_entity or not old_entity.valid then
			-- Skip
		elseif is_factory_component_entity(old_entity) then
			-- Skip
		else
			local new_entity = old_entity
			if entity_map[old_entity] then
				new_entity = entity_map[old_entity]
			end
			
			-- Restore wire connections
			local description = reconstructed_entities[old_entity]
			if not description then
				game.print("Nil entity description for "..old_entity.prototype.type)
			else
				if description.circuit_connection_definitions then
					for _,connection in pairs(description.circuit_connection_definitions) do
						local mapped_neighbour = connection.target_entity
						if entity_map[connection.target_entity] then
							local mapped_neighbour = entity_map[connection.target_entity]
						end
						new_entity.connect_neighbour({
							wire = connection.wire,
							target_entity = mapped_neighbour,
							source_circuit_id = connection.source_circuit_id,
							target_circuit_id = connection.target_circuit_id
						})
					end
				end
			end
		end
	end
	
	-- Delete entities that couldn't be teleported and were cloned
	for _,desc in pairs(reconstructed_entities) do
		if not (desc.was_teleported) then
			desc.old_entity.destroy()
		end
	end
end

function cleanup_factory_exterior(factory, building)
	Connections.disconnect_factory(factory)
	if factory.outside_energy_sender.valid then
		factory.outside_energy_sender.destroy()
	end
	if factory.outside_energy_receiver.valid then
		factory.outside_energy_receiver.destroy()
	end
	for _, entity in pairs(factory.outside_overlay_displays) do
		if entity.valid then entity.destroy() end
	end
	factory.outside_overlay_displays = {}
	for _, entity in pairs(factory.outside_fluid_dummy_connectors) do
		if entity.valid then entity.destroy() end
	end
	factory.outside_fluid_dummy_connectors = {}
	for _, entity in pairs(factory.outside_port_markers) do
		if entity.valid then entity.destroy() end
	end
	factory.outside_port_markers = {}
	for _, entity in pairs(factory.outside_other_entities) do
		if entity.valid then entity.destroy() end
	end
	factory.outside_other_entities = {}
	factory.building = nil
	factory.built = false
end

-- FACTORY SAVING AND LOADING --

local SAVE_NAMES = {} -- Set of all valid factory save names
local SAVE_ITEMS = {}
for _,f in ipairs(Constants.factory_type_names) do
	SAVE_ITEMS[f] = {}
	for n = Constants.factory_id_min,Constants.factory_id_max do
		SAVE_NAMES[f .. "-s" .. n] = true
		SAVE_ITEMS[f][n] = f .. "-s" .. n
	end
end

local function save_factory(factory)
	for _,sf in pairs(SAVE_ITEMS[factory.layout.name] or {}) do
		if global.saved_factories[sf] then
		else
			global.saved_factories[sf] = factory
			return sf
		end
	end
	--game.print("Could not save factory!")
	return nil
end

local function is_invalid_save_slot(name)
	return SAVE_NAMES[name] and not global.saved_factories[name]
end

local function init_factory_requester_chest(entity)
	local n = entity.request_slot_count
	if n == 0 then return end
	local last_slot = entity.get_request_slot(n)
	local begin_after = last_slot and last_slot.name
	local saved_factories = global.saved_factories
	if not(begin_after and saved_factories[begin_after] and next(saved_factories,begin_after)) then begin_after = nil end
	local i = 0
	for sf,_ in next, saved_factories,begin_after do
		i = i+1
		entity.set_request_slot({name=sf,count=1},i)
		if i >= n then return end		
	end
	for j=i+1,n do
		entity.clear_request_slot(j)
	end
end

commands.add_command("give-lost-factory-buildings", {"command-help-message.give-lost-factory-buildings"}, function(event)
	--game.print(serpent.line(event))
	local player = game.players[event.player_index]
	if not (player and player.connected and player.admin) then return end
	if event.parameter == "destroyed" then
		for _,factory in pairs(global.factories) do
			local saved_or_built = factory.built
			for _,saved_factory in pairs(global.saved_factories) do
				if saved_factory.id == factory.id then
					saved_or_built = true
					break
				end
			end
			if not saved_or_built then
				save_factory(factory)
			end
		end
	end
	local main_inventory = player.get_inventory(defines.inventory.player_main)
	local quickbar = player.get_inventory(defines.inventory.player_quickbar)
	for save_name,_ in pairs(global.saved_factories) do
		if main_inventory.get_item_count(save_name) + quickbar.get_item_count(save_name) == 0 and not (player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name == save_name) then
			player.insert{name = save_name, count = 1}
		end
	end
end)
-- FACTORY PLACEMENT AND DESTRUCTION --

local function can_place_factory_here(tier, surface, position)
	local factory = find_surrounding_factory(surface, position)
	if not factory then return true end
	local outer_tier = factory.layout.tier
	if outer_tier > tier and (factory.force.technologies["factory-recursion-t1"].researched or settings.global["Microfactorio-free-recursion"].value) then return true end
	if outer_tier >= tier and (factory.force.technologies["factory-recursion-t2"].researched or settings.global["Microfactorio-free-recursion"].value) then return true end
	if outer_tier > tier then
		surface.create_entity{name="flying-text", position=position, text={"factory-connection-text.invalid-placement-recursion-1"}}
	elseif outer_tier >= tier then
		surface.create_entity{name="flying-text", position=position, text={"factory-connection-text.invalid-placement-recursion-2"}}
	else
		surface.create_entity{name="flying-text", position=position, text={"factory-connection-text.invalid-placement"}}
	end
	return false
end

local function recheck_nearby_connections(entity, delayed)
	local surface = entity.surface
	-- Find nearby factory buildings
	local bbox = entity.bounding_box
	-- Expand box by one tile to catch factories and also avoid illegal zero-area finds
	local bbox2 = {
		left_top = {x = bbox.left_top.x - 1.5, y = bbox.left_top.y - 1.5},
		right_bottom = {x = bbox.right_bottom.x + 1.5, y = bbox.right_bottom.y + 1.5}
	}
	local building_candidates = surface.find_entities_filtered{area = bbox2, type = BUILDING_TYPE}
	for _,candidate in pairs(building_candidates) do
		if candidate ~= entity and HasLayout(candidate.name) then
			local factory = get_factory_by_building(candidate)
			if factory then
				if delayed then
					Connections.recheck_factory_delayed(factory, bbox2, nil)
				else
					Connections.recheck_factory(factory, bbox2, nil)
				end
			end
		end
	end
	local surrounding_factory = find_surrounding_factory(surface, entity.position)
	if surrounding_factory then
		if delayed then
			Connections.recheck_factory_delayed(surrounding_factory, nil, bbox2)		
		else
			Connections.recheck_factory(surrounding_factory, nil, bbox2)
		end
	end
end

script.on_event({defines.events.on_built_entity, defines.events.on_robot_built_entity}, function(event)
	local entity = event.created_entity
	on_entity_built(entity)
end)

local function is_blueprinted_factory(entity_name)
	if string.find(entity_name, "-blueprint$") then
		local factory_type = string.sub(1, -(1+#"-blueprint"))
		return HasLayout(factory_type)
	else
		return false
	end
end

local function blueprinted_factory_to_building(entity_name)
	if string.find(entity_name, "-blueprint$") then
		local factory_type = string.sub(1, -(1+#"-blueprint"))
		return factory_type
	else
		return nil
	end
end

function on_entity_built(entity)
	if entity.name == "entity-ghost" then
		if entity.ghost_name == "blueprint-factory-overlay-display-1"
		   or entity.ghost_name == "blueprint-factory-overlay-display-2" then
			entity.destroy()
		end
	elseif HasLayout(entity.name) then
		-- This is a fresh factory, we need to create it
		local layout = CreateLayout(entity.name)
		if can_place_factory_here(layout.tier, entity.surface, entity.position) then
			local factory = create_factory_interior(layout, entity.force)
			create_factory_exterior(factory, entity)
		else
			entity.surface.create_entity{name=entity.name .. "-i", position=entity.position, force=entity.force}
			entity.destroy()
			return
		end
		
		-- Look for adjacent factory-contents-markers and ghosts thereof. If
		-- found, unpack its blueprint and delete it.
		local content_marker_ghost = find_factory_content_marker_near(entity)
		if content_marker_ghost ~= nil then
			-- Revive the factory-contents-marker so we can get the alert
			-- message (abused to contain a blueprint string) out of it.
			-- Then remove it.
			collisions,content_marker = content_marker_ghost.revive()
			blueprint_string = content_marker.alert_parameters.alert_message
			content_marker.destroy()
			
			-- Apply the blueprint to the factory, filling it with ghosts
			local factory = get_factory_by_entity(entity)
			apply_blueprint_to_factory(factory, entity.force, blueprint_string,
				entity.orientation)
		end
	elseif global.saved_factories[entity.name] then
		-- This is a saved factory, we need to unpack it
		local factory = global.saved_factories[entity.name]
		if can_place_factory_here(factory.layout.tier, entity.surface, entity.position) then
			global.saved_factories[entity.name] = nil
			local newbuilding = entity.surface.create_entity{name=factory.layout.name, position=entity.position, force=factory.force}
			newbuilding.last_user = entity.last_user
			create_factory_exterior(factory, newbuilding)
			entity.destroy()
		end
	elseif is_invalid_save_slot(entity.name) then
		entity.surface.create_entity{name="flying-text", position=entity.position, text={"factory-connection-text.invalid-factory-data"}}
		entity.destroy()
	elseif entity.name == "factory-construction-requester-chest" then
		init_construction_chest(entity)
	else
		if Connections.is_connectable(entity) then
			recheck_nearby_connections(entity)
		end
		if entity.name == "factory-requester-chest" then
			init_factory_requester_chest(entity)
		end
	end
end

function find_factory_content_marker_near(entity)
	if not entity or not entity.valid then
		return nil
	end
	local search_area = neighbor_area_from_collision_box(entity.position, entity.prototype.collision_box)
	
	local nearby = entity.surface.find_entities(search_area)
	
	for _,ghost in pairs(nearby) do
		if ghost.name == "entity-ghost" and ghost.ghost_name == "factory-contents-marker" then
			return ghost
		end
	end
	return nil
end

-- Return an area that includes all tiles that would touch an object that's at
-- the given position and has the given collision box.
function neighbor_area_from_collision_box(position, collision_box)
	return {
		left_top = {
			x = position.x + collision_box.left_top.x - 1,
			y = position.y + collision_box.left_top.y - 1,
		},
		right_bottom = {
			x = position.x + collision_box.right_bottom.x + 1,
			y = position.y + collision_box.right_bottom.y + 1,
		}
	}
end

function list_to_index(list)
	index = {}
	for _,v in pairs(list) do
		index[v] = true
	end
	return index
end

local entities_ignored_when_copying = list_to_index({
	"factory-ceiling-light", "factory-fluid-dummy-connector",
	"factory-overlay-controller"})

script.on_event({defines.events.on_entity_settings_pasted}, function(event)
	if event.source.name==event.destination.name and HasLayout(event.source.name) then
		-- "Paste settings" from one factory to another. Create ghosts in the
		-- destination factory to match buildings in the source factory.
		local player = game.players[event.player_index]

		local source_factory = get_factory_by_entity(event.source)
		local dest_factory = get_factory_by_entity(event.destination)
		
		if not factory_is_empty(dest_factory) then
			player.print("Can't paste onto factory because it is not empty.")
		else
			local blueprint_string = factory_to_blueprint_string(source_factory, player.force)
			clear_factory_ghosts(dest_factory)
			apply_blueprint_to_factory(dest_factory, player.force, blueprint_string,
				0)
		end
	end
end)

-- Create a temporary blueprint item, for generating blueprint strings or
-- applying them. Takes a factory and places it in an empty (player
-- inacecssible) position.
function create_temp_blueprint(factory)
	local surface = factory.inside_surface
	local item_on_ground = surface.create_entity {
		name = "item-on-ground",
		position = {64,64},
		stack = { name="blueprint" },
	}
	return item_on_ground
end

function factory_to_blueprint_string(factory, force)
	-- Create a blueprint covering the contents of a factory floor
	local blueprint = create_temp_blueprint(factory)
	
	local bounds_markers = place_bounds_markers(
		factory.inside_surface, force, get_factory_inside_area(factory))
	
	local topleft_x = factory.inside_x - factory.layout.inside_size/2
	local topleft_y = factory.inside_y - factory.layout.inside_size/2
	local inside_area = get_factory_inside_area(factory)
	blueprint.stack.create_blueprint{
		surface=factory.inside_surface,
		force=force,
		area=inside_area,
	}
	
	-- Modify the blueprint to filter out entities with skipped types
	filter_blueprint_entities(blueprint.stack, entities_ignored_when_copying)
	
	-- Modify the blueprint to record the contents of any nested factories
	blueprint_record_factory_contents(blueprint.stack, inside_area, factory.inside_surface, force)
	
	-- Record the filter settings on any overlay controllers
	local extended_inside_area = {
		left_top = {
			x = inside_area.left_top.x-1,
			y = inside_area.left_top.y-1
		},
		right_bottom = {
			x = inside_area.right_bottom.x+1,
			y = inside_area.right_bottom.y+1
		}
	}
	local overlay_controllers = factory.inside_surface.find_entities_filtered {
		area = extended_inside_area,
		name = "factory-overlay-controller",
	}
	local overlay_list={}
	for _,overlay_controller in pairs(overlay_controllers) do
		table.insert(overlay_list, extract_overlay_controller_settings(factory, overlay_controller))
	end
	
	local blueprint_table = {
		entities = blueprint.stack.get_blueprint_entities(),
		tiles = blueprint.stack.get_blueprint_tiles(),
		icons = blueprint.stack.blueprint_icons,
		name = "Factory blueprint",
		overlays = overlay_list
	}
	
	-- Serialize
	local blueprintString = BlueprintString.toString(blueprint_table)
	
	-- Clean up the temporary blueprint object and bounds markers
	blueprint.destroy()
	remove_bounds_markers(factory.inside_surface, get_factory_inside_area(factory))
	
	return blueprintString
end

function extract_overlay_controller_settings(factory, overlay_controller)
	signals = {}
	local behavior = overlay_controller.get_control_behavior()
	for i=1,Constants.overlay_slot_count do
		local signal = behavior.get_signal(i)
		if signal.signal then
			signals[i] = {
				type = signal.signal.type,
				count = signal.count,
				name = signal.signal.name
			}
		else
			signals[i] = nil
		end
	end
	return {
		x = overlay_controller.position.x-factory.inside_x,
		y = overlay_controller.position.y-factory.inside_y,
		overlay_signals = signals
	}
end

function apply_overlay_controller_settings(settings, overlay_controller)
	local behavior = overlay_controller.get_control_behavior()
	if behavior and settings.overlay_signals then
		for i=1,Constants.overlay_slot_count do
			if settings.overlay_signals[i] then
				behavior.set_signal(i, {
					signal = {
						type = settings.overlay_signals[i].type,
						name = settings.overlay_signals[i].name
					},
					count = 1
				})
			else
				behavior.set_signal(i, nil)
			end
		end
	end
end

function get_factory_inside_area(factory)
	-- FIXME: This (a) assumes factories are always square, and (b) probably has
	-- an off-by-one-half or worse
	local size = factory.layout.inside_size+1
	local topleft_x = factory.inside_x - size/2
	local topleft_y = factory.inside_y - size/2
	return {
		left_top = {
			x = factory.inside_x - size/2,
			y = factory.inside_y - size/2,
		},
		right_bottom = {
			x = factory.inside_x + size/2,
			y = factory.inside_y + size/2,
		}
	}
end

function apply_blueprint_to_factory(factory, force, blueprint_string, orientation)
	-- Unpack the blueprint
	local blueprint = create_temp_blueprint(factory)
	
	local blueprint_table = BlueprintString.fromString(blueprint_string)
	local overlays = blueprint_table.overlays
	blueprint.stack.set_blueprint_entities(blueprint_table.entities)
	blueprint.stack.set_blueprint_tiles(blueprint_table.tiles)
	blueprint.stack.blueprint_icons = blueprint_table.icons
	blueprint.stack.label = blueprint_table.name or ""
	
	local build_x = factory.inside_x
	local build_y = factory.inside_y
	
	local compass_dir = nil
	
	if orientation == 0 then
		compass_dir = defines.direction.north
	elseif orientation == 0.25 then
		compass_dir = defines.direction.east
		build_x = build_x - 1
	elseif orientation == 0.5 then
		compass_dir = defines.direction.south
		build_x = build_x - 1
		build_y = build_y - 1
	elseif orientation == 0.75 then
		compass_dir = defines.direction.west
		build_y = build_y - 1
	else
		game.print("ERROR: Trying to place factory in invalid orientation: "..direction)
		blueprint.destroy()
		return
	end
	
	local build_result = blueprint.stack.build_blueprint{
		surface=factory.inside_surface,
		force=force,
		position={build_x,build_y},
		force_build=true,
		direction = compass_dir,
	}
	
	-- Apply overlay settings
	for _,overlay in ipairs(blueprint_table.overlays) do
		local rotated_overlay_controller_pos = find_rotated_overlay_controller(factory, orientation, overlay.x, overlay.y)
		if rotated_overlay_controller_pos then
			local pos = {x=rotated_overlay_controller_pos.x+factory.inside_x, y=rotated_overlay_controller_pos.y+factory.inside_y}
			local controller_maybe = factory.inside_surface.find_entities_filtered {
				area = {
					top_left     = { x=pos.x-.5, y=pos.y-.5 },
					bottom_right = { x=pos.x+.5, y=pos.y+.5 },
				},
				name = "factory-overlay-controller",
			}
			if (#controller_maybe) == 1 then
				local controller = controller_maybe[1]
				apply_overlay_controller_settings(overlay, controller)
			else
				game.print("Couldn't find overlay controller")
			end
		end
	end
	update_overlay(factory)
	
	-- Clean up the temporary blueprint object and bounds markers
	blueprint.destroy()
	remove_bounds_marker_ghosts(factory.inside_surface, get_factory_inside_area(factory))
end

-- Given a factory, the inside (x,y) position of an overlay controller, and a
-- rotation, find the corresponding connection, find the rotated version of
-- that connection, and return the position of that connection's overlay
-- controller.
function find_rotated_overlay_controller(factory, orientation, x, y)
	local connections = factory.layout.connections
	local connection_id = nil
	
	-- Find the overlay specification in the factory layout
	local overlay_specification = nil
	for id,o in pairs(factory.layout.overlays) do
		if o.inside_x==x and o.inside_y==y then
			connection_id = id
			break
		end
	end
	if connection_id == nil then
		return nil
	end
	
	-- Get the corresponding connection specification
	local connection = connections[connection_id]
	if connection == nil then
		-- If no corresponding connection, then this overlay controller is one
		-- of the ones that marks the middle of the building, so it doesn't
		-- get rotated.
		return { x=x, y=y }
	end
	
	-- Find the rotated connection
	local rotated_connection_id = connection.id
	for i=1,orientation_to_rotation_count(orientation) do
		rotated_connection_id = connections[rotated_connection_id].rotates_to
	end
	
	local rotated_overlay = factory.layout.overlays[rotated_connection_id]
	return { x=rotated_overlay.inside_x, y=rotated_overlay.inside_y }
end

function orientation_to_rotation_count(orientation)
	if orientation == 0 then
		return 0
	elseif orientation == 0.25 then
		return 1
	elseif orientation == 0.5 then
		return 2
	elseif orientation == 0.75 then
		return 3
	else
		game.print("Invalid orientation: "..orientation)
	end
end

function place_bounds_markers(surface, force, rect)
	return {
		place_bound_marker_at(surface, force, rect.left_top    .x, rect.left_top    .y),
		place_bound_marker_at(surface, force, rect.right_bottom.x, rect.left_top    .y),
		place_bound_marker_at(surface, force, rect.left_top    .x, rect.right_bottom.y),
		place_bound_marker_at(surface, force, rect.right_bottom.x, rect.right_bottom.y),
	}
end

function remove_bounds_markers(surface, rect)
	local to_remove = surface.find_entities_filtered{
		area = rect,
		name = "factory-bounds-marker",
	}
	for _,v in pairs(to_remove) do
		v.destroy()
	end
end

function remove_bounds_marker_ghosts(surface, rect)
	local to_remove = surface.find_entities_filtered{
		area = rect,
		name = "entity-ghost",
	}
	for _,v in pairs(to_remove) do
		if v.ghost_name == "factory-bounds-marker" then
			v.destroy()
		end
	end
end

function place_bound_marker_at(surface, force, x, y)
	return surface.create_entity{
		name = "factory-bounds-marker",
		position = {x,y},
		force = force,
	}
end

-- Given a blueprint, modify it to remove any entities that appear in
-- skipped_entity_types, a dict from entity type-names to true.
function filter_blueprint_entities(blueprint, skipped_entity_types)
	local blueprint_entities = blueprint.get_blueprint_entities()
	local filtered_blueprint_entities = {}
	for _,v in pairs(blueprint_entities) do
		if not skipped_entity_types[v.name] then
			table.insert(filtered_blueprint_entities, v)
		end
	end
	blueprint.set_blueprint_entities(filtered_blueprint_entities)
end

function init_construction_chest(construction_requester_chest)
	update_construction_chest(construction_requester_chest)
	table.insert(global.construction_requester_chests, construction_requester_chest)
end

function update_all_construction_requester_chests(tick)
	local num_chests = #global.construction_requester_chests
	local check_interval = 60
	local offset = (23*game.tick)%check_interval+1
	while offset <= num_chests do
		local chest = global.construction_requester_chests[offset]
		if chest and chest.valid then
			update_construction_chest(chest)
		else
			table.remove(global.construction_requester_chests, offset)
		end
		offset = offset + check_interval
	end
end

local function get_factory_touching(surface, position)
	local nearby_entities = surface.find_entities({
		left_top = {position.x-1, position.y-1},
		right_bottom = {position.x+1, position.y+1},
	})
	for _,nearby_entity in pairs(nearby_entities) do
		if HasLayout(nearby_entity.name) then
			return get_factory_by_entity(nearby_entity)
		end
	end
	return nil
end

-- Modifies: items_to_use items_spent, missing_items
function build_ghosts(factory, items_to_use, items_spent, missing_items)
	local area = get_factory_inside_area(factory)
	local entities = factory.inside_surface.find_entities(area)
	local num_built = 0
	
	-- Count up items requested for ghosts
	for _,entity in pairs(entities) do
		-- Use items to revive ghosts
		if entity and entity.valid
		   and entity.name=="entity-ghost" and entity.ghost_prototype and entity.ghost_prototype.items_to_place_this
		   and entity.ghost_prototype.name ~= "factory-contents-marker" then
			local ghost = entity
			local item_needed = ghost.ghost_prototype.items_to_place_this
			local requests = {}
			for k,v in pairs(item_needed) do
				-- TODO: Handle alternatives? This only makes sense if a ghost can
				-- only be revived with one particular item type.
				-- (Which is how it normally works, but the API says there could
				-- be multiple things here.)
				requests[k] = 1
			end
			
			-- Can this request be satisfied?
			if request_is_satisfied(requests, items_to_use) then
				collisions,revived = ghost.revive()
				if revived and revived.valid then
					for item,num in pairs(requests) do
						incr_default_0(items_spent, item, num)
						incr_default_0(items_to_use, item, -num)
					end
					
					on_entity_built(revived)
					num_built = num_built+1
					entity = revived
				end
			else
				-- Add to the list of unsatisfied requests
				for item,num in pairs(requests) do
					incr_default_0(missing_items, item, num)
				end
			end
		end
		
		-- Fill module requests
		if entity and entity.valid and entity.name=="item-request-proxy" then
			local updated_requests = entity.item_requests
			local unsatisfied_requests = 0
			local changed = false
			for module,count in pairs(entity.item_requests) do
				local count_to_insert = math.min(count, items_to_use[module] or 0)
				
				if count_to_insert > 0 then
					entity.proxy_target.insert({name=module, count=count_to_insert})
					incr_default_0(items_to_use, module, -count_to_insert)
					incr_default_0(items_spent, module, count_to_insert)
					incr_default_0(missing_items, module, count-count_to_insert)
					incr_default_0(updated_requests, module, -count_to_insert)
					changed = true
				else
					incr_default_0(missing_items, module, count)
				end
				unsatisfied_requests = unsatisfied_requests + (count-count_to_insert)
			end
			if unsatisfied_requests > 0 then
				if changed then
					entity.item_requests = updated_requests
				end
			else
				entity.destroy()
			end
		end
	end
end

function update_construction_chest(construction_requester_chest)
	-- Find the factory this chest goes with
	local factory = get_factory_touching(construction_requester_chest.surface, construction_requester_chest.position)
	if factory == nil then
		return
	end
	local area = get_factory_inside_area(factory)
	
	-- Count up items in the chest, available for construction
	local items_in_chest = construction_requester_chest.get_inventory(defines.inventory.chest).get_contents()
	local items_spent = {}
	local unsatisfied_requests = {}
	
	build_ghosts(factory, items_in_chest, items_spent, unsatisfied_requests)
	
	-- Look for construction-requester-chests inside, in order to build
	-- recursive factories.
	local recursive_chests = factory.inside_surface.find_entities_filtered{
		area = area,
		name = "factory-construction-requester-chest"
	}
	for _,chest in pairs(recursive_chests) do
		local chest_requests = get_chest_requests(chest)
		for item,num in pairs(chest_requests) do
			local items_to_transfer = 0
			if items_in_chest[item] ~= nil and items_in_chest[item] > 0 then
				-- We have an item that can satisfy this request
				items_to_transfer = math.min(num, items_in_chest[item])
				chest.insert({ name=item, count=items_to_transfer })
				incr_default_0(items_spent, item, items_to_transfer)
				incr_default_0(items_in_chest, item, -items_to_transfer)
			end
			if items_to_transfer < num then
				incr_default_0(unsatisfied_requests, item, num-items_to_transfer)
			end
		end
	end
	
	-- Remove spent items
	for item,num in pairs(items_spent) do
		construction_requester_chest.remove_item({
			name = item,
			count = num
		})
	end
	
	-- Apply item requests to requester-chest settings
	local num_request_slots = construction_requester_chest.request_slot_count
	local request_slot_index = 1
	for item,num in pairs(unsatisfied_requests) do
		local request = { name = item, count = num }
		construction_requester_chest.set_request_slot(request, request_slot_index)
		request_slot_index = request_slot_index+1
		if request_slot_index > num_request_slots then
			break
		end
	end
	for i = request_slot_index,num_request_slots do
		construction_requester_chest.clear_request_slot(i)
	end
end

function get_chest_requests(chest)
	local requests = {}
	local num_request_slots = chest.request_slot_count
	for i=1,num_request_slots do
		local request = chest.get_request_slot(i)
		if request == nil then break end
		incr_default_0(requests, request.name, request.count)
	end
	return requests
end

function incr_default_0(dict, k, n)
	if n==0 then
		return dict
	end
	if dict[k] ~= nil then
		dict[k] = dict[k]+n
	else
		dict[k] = n
	end
	return dict
end

function request_is_satisfied(request, available)
	for k,v in pairs(request) do
		if available[k] == nil or available[k] < request[k] then
			return false
		end
	end
	return true
end

local pending_blueprints_by_player = {}

script.on_event(defines.events.on_player_setup_blueprint, function(event)
	local player_index = event.player_index
	local area = event.area
	local item = event.item
	local alt = event.alt
	
	local player = game.players[player_index]
	
	pending_blueprints_by_player[player_index] = {
		area = event.area,
		item = event.item,
		alt = event.alt,
		surface = player.surface,
	}
end)

script.on_event(defines.events.on_player_configured_blueprint, function(event)
	local player_index = event.player_index
	
	if pending_blueprints_by_player[player_index] == nil then
		return
	end
	
	local area = pending_blueprints_by_player[player_index].area
	local player = game.players[player_index]
	local blueprint = player.cursor_stack
	local force = player.force
	
	if blueprint == nil or not blueprint.valid or not blueprint.valid_for_read then
		return
	end
	
	-- Look at the surface the player was on when they set up the blueprint,
	-- not the surface they're on when they confirm it. (Otherwise this would
	-- go wrong if you entered/left a factory building while the blueprint
	-- dialog was up.)
	local surface = pending_blueprints_by_player[player_index].surface
	
	blueprint_record_factory_contents(blueprint, area, surface, force)
end)

function blueprint_record_factory_contents(blueprint, area, surface, force)
	if not blueprint.valid then
		return
	end
	
	-- Check whether the blueprint contains any factory buildings. If not, skip the
	-- rest of this.
	if not blueprint_contains_factories(blueprint) then
		return
	end
	
	-- Find the relation between world-coords and blueprint-coords.
	-- Find the factory with the lexicographically-first coordinates in each.
	-- They are the same factory; the difference between their positions is the
	-- blueprint offset.
	local ents_in_area = surface.find_entities(area)
	local blueprint_entities = blueprint.get_blueprint_entities()
	BlueprintString.remove_useless_fields(blueprint_entities)
	
	local first_blueprint_factory = lexicographically_first_factory_in(blueprint_entities)
	local first_world_factory = lexicographically_first_factory_in(ents_in_area)
	local blueprint_offset = {
		x = first_world_factory.position.x - first_blueprint_factory.position.x,
		y = first_world_factory.position.y - first_blueprint_factory.position.y,
	}
	local added_entities = {}
	
	for i,entity in pairs(blueprint_entities) do
		-- For each blueprint factory...
		if HasLayout(entity.name) then
			-- Un-rotate factories in the blueprint
			entity.direction = 0
			
			-- Find the factory entity in the world
			local world_pos = {
				x = entity.position.x + blueprint_offset.x,
				y = entity.position.y + blueprint_offset.y
			}
			local world_entities = surface.find_entities(
				shift_bounds_by(world_pos.x, world_pos.y, centered_square(1)))
			local factory_entity
			local factory
			for i,world_entity in ipairs(world_entities) do
				if world_entity.name == entity.name then
					factory_entity = world_entity
					factory = get_factory_by_entity(world_entity)
				end
			end
			
			-- Add a factory contents marker to the blueprint. This is a special
			-- entity type that abuses the programmable-speaker's "alert" field
			-- to store a blueprint string.
			local blueprint_string = factory_to_blueprint_string(factory, factory_entity.force)
			local contents_marker = {
				name = "factory-contents-marker",
				position = entity.position,
				parameters = {
					playback_volume=0,
					playback_globally=false,
					allow_polyphony=false,
				},
				alert_parameters = {
					show_alert=true,
					show_on_map=false,
					alert_message=blueprint_string
				}
			}
			table.insert(added_entities, contents_marker)
			
			-- Add the factory's overlays to the blueprint
			for i,overlay in pairs(factory.outside_overlay_displays) do
				if not overlay_is_empty(overlay) then
					table.insert(added_entities, {
						name = "blueprint-"..overlay.name,
						position = {
							x=overlay.position.x-world_pos.x - 0.5,
							y=overlay.position.y-world_pos.y - 0.5
						},
						control_behavior = serialize_overlay_behavior(overlay.get_control_behavior())
					})
				end
			end
		end
	end
	
	for i,overlay in ipairs(added_entities) do
		table.insert(blueprint_entities, overlay)
	end
	
	BlueprintString.fix_entities(blueprint_entities)
	blueprint.set_blueprint_entities(blueprint_entities)
end

function serialize_overlay_behavior(overlay)
	local filters = {}
	for i = 1,Constants.overlay_slot_count do
		local signal = overlay.get_signal(i)
		if signal and signal.signal then
			table.insert(filters, {
				index = i,
				count = signal.count,
				signal = signal.signal
			})
		end
	end
	
	return { filters = filters }
end

function overlay_is_empty(overlay)
	if not overlay then return true end
	local behavior = overlay.get_control_behavior()
	if not behavior then return true end
	for i = 1,Constants.overlay_slot_count do
		local signal = behavior.get_signal(i)
		if signal and signal.signal then
			return false
		end
	end
	return true
end

function lexicographically_first_factory_in(entity_list)
	local first = true
	local first_entity = nil
	local first_position = nil
	for _,entity in pairs(entity_list) do
		if HasLayout(entity.name) then
			if first then
				first = false
				first_entity = entity
				first_position = entity.position
			else
				if entity.position.y < first_position.y or entity.position.y == first_position.y and entity.position.x < first_position.x then
					first_entity = entity
					first_position = entity.position
				end
			end
		end
	end
	return first_entity
end

-- Returns whether the given blueprint contains at least one factory building
function blueprint_contains_factories(blueprint)
	local entities = blueprint.get_blueprint_entities()
	for _,entity in pairs(entities) do
		if HasLayout(entity.name) then
			return true
		end
	end
	return false
end


-- How players pick up factories
-- Working factory buildings don't return items, so we have to manually give the player an item
script.on_event(defines.events.on_pre_player_mined_item, function(event)
	local entity = event.entity
	if HasLayout(entity.name) then
		local factory = get_factory_by_building(entity)
		if factory then
			local save = save_factory(factory)
			if save then
				cleanup_factory_exterior(factory, entity)
				local player = game.players[event.player_index]
				if player.can_insert{name = save, count = 1} then
					player.insert{name = save, count = 1}
				else
					player.print{"inventory-restriction.player-inventory-full", {"entity-name."..save}}
					player.surface.spill_item_stack({x=factory.outside_x, y=factory.outside_y}, {name = save, count = 1})
				end
			else
				local newbuilding = entity.surface.create_entity{name=entity.name, position=entity.position, force=factory.force}
				newbuilding.last_user = entity.last_user
				entity.destroy()
				set_entity_to_factory(newbuilding, factory)
				factory.building = newbuilding
				game.players[event.player_index].print("Could not pick up factory, too many factories picked up at once")
			end
		end
	elseif Connections.is_connectable(entity) then
		recheck_nearby_connections(entity, true) -- Delay
	end
end)

-- How robots pick up factories
-- Since you can't insert items into construction robots, we'll have to swap out factories for fake placeholder factories
-- as soon as they are marked for deconstruction, and swap them back should they be unmarked.
script.on_event(defines.events.on_marked_for_deconstruction, function(event)
	local entity = event.entity
	if HasLayout(entity.name) then
		local factory = get_factory_by_building(entity)
		if factory then
			local save = save_factory(factory)
			if save then
				-- Replace by placeholder
				cleanup_factory_exterior(factory, entity)
				local placeholder = entity.surface.create_entity{name=save, position=entity.position, force=factory.force}
				placeholder.order_deconstruction(factory.force)
				entity.destroy()
			else
				-- Not saved, so put it back
				-- Don't cancel deconstruction (it'd cause another event), instead simply replace with new building
				local newbuilding = entity.surface.create_entity{name=entity.name, position=entity.position, force=factory.force}
				entity.destroy()
				set_entity_to_factory(newbuilding, factory)
				factory.building = newbuilding
				game.print("Could not pick up factory, too many factories picked up at once")			
			end
		end
	end
end)

-- Factories also need to start working again once they are unmarked
script.on_event(defines.events.on_canceled_deconstruction, function(event)
	local entity = event.entity
	if global.saved_factories[entity.name] then
		-- Rebuild factory from save
		local factory = global.saved_factories[entity.name]
		if can_place_factory_here(factory.layout.tier, entity.surface, entity.position) then
			global.saved_factories[entity.name] = nil
			local newbuilding = entity.surface.create_entity{name=factory.layout.name, position=entity.position, force=factory.force}
			create_factory_exterior(factory, newbuilding)
			entity.destroy()
		end
	end
end)

-- We need to check when a robot mines a piece of a connection
script.on_event(defines.events.on_robot_pre_mined, function(event)
	local entity = event.entity
	if Connections.is_connectable(entity) then
		recheck_nearby_connections(entity, true) -- Delay
	end
end)

script.on_event(defines.events.on_robot_mined, function(event)
	local item = event.item
end)
-- How biters pick up factories
-- Too bad they don't have hands
script.on_event(defines.events.on_entity_died, function(event)
	local entity = event.entity
	if HasLayout(entity.name) then
		local factory = get_factory_by_building(entity)
		if factory then
			cleanup_factory_exterior(factory, entity)
			-- Don't save it. It will be inaccessible from now on.
			--save_factory(factory)
		end
	elseif Connections.is_connectable(entity) then
		recheck_nearby_connections(entity, true) -- Delay
	end
end)

-- GUI --

local function get_camera_toggle_button(player)
	local buttonflow = mod_gui.get_button_flow(player)
	local button = buttonflow.factory_camera_toggle_button or buttonflow.add{type="sprite-button", name="factory_camera_toggle_button", sprite="technology/factory-architecture-t1"}
	button.style.visible = player.force.technologies["factory-preview"].researched
	return button
end

local function get_camera_frame(player)
	local frameflow = mod_gui.get_frame_flow(player)
	local camera_frame = frameflow.factory_camera_frame
	if not camera_frame then
		camera_frame = frameflow.add{type = "frame", name = "factory_camera_frame", style = "captionless_frame"}
		camera_frame.style.visible = false
	end
	return camera_frame
end

-- prepare_gui was declared waaay above
prepare_gui = function(player)
	get_camera_toggle_button(player)
	get_camera_frame(player)
end

local function set_camera(player, factory, inside)
	if not player.force.technologies["factory-preview"].researched then return end

	local ps = settings.get_player_settings(player)
	local ps_preview_size = ps["Factorissimo2-preview-size"]
	local preview_size = ps_preview_size and ps_preview_size.value or 300
	local ps_preview_zoom = ps["Factorissimo2-preview-zoom"]
	local preview_zoom = ps_preview_zoom and ps_preview_zoom.value or 1
	local position, surface_index, zoom
	if not inside then
		position = {x = factory.outside_x, y = factory.outside_y}
		surface_index = factory.outside_surface.index
		zoom = (preview_size/(32/preview_zoom))/(8+factory.layout.outside_size)
	else
		position = {x = factory.inside_x, y = factory.inside_y}
		surface_index = factory.inside_surface.index
		zoom = (preview_size/(32/preview_zoom))/(5+factory.layout.inside_size)
	end
	local camera_frame = get_camera_frame(player)
	local camera = camera_frame.factory_camera
	if camera then
		camera.position = position
		camera.surface_index = surface_index
		camera.zoom = zoom
		camera.style.minimal_width = preview_size
		camera.style.minimal_height = preview_size
	else
		local camera = camera_frame.add{type = "camera", name = "factory_camera", position = position, surface_index = surface_index, zoom = zoom}
		camera.style.minimal_width = preview_size
		camera.style.minimal_height = preview_size
	end
	camera_frame.style.visible = true
end

local function unset_camera(player)
	get_camera_frame(player).style.visible = false
end

local function update_camera(player)
	if not global.player_preview_active[player.index] then return end
	if not player.force.technologies["factory-preview"].researched then return end
	local cursor_stack = player.cursor_stack
	if cursor_stack and cursor_stack.valid_for_read and global.saved_factories[cursor_stack.name] then
		set_camera(player, global.saved_factories[cursor_stack.name], true)
		return
	end
	local selected = player.selected
	if selected then
		local factory = get_factory_by_entity(player.selected)
		if factory then
			set_camera(player, factory, true)
			return
		elseif selected.name == "factory-power-pole" then
			local factory = find_surrounding_factory(player.surface, player.position)
			if factory then
				set_camera(player, factory, false)
				return
			end
		end
	end
	unset_camera(player)
end

script.on_event(defines.events.on_gui_click, function(event)
	local player = game.players[event.player_index]
	if event.element.name == "factory_camera_toggle_button" then
		if global.player_preview_active[player.index] then
			get_camera_toggle_button(player).sprite = "technology/factory-architecture-t1"
			global.player_preview_active[player.index] = false
		else
			get_camera_toggle_button(player).sprite = "technology/factory-preview"
			global.player_preview_active[player.index] = true
		end
	end
end)

script.on_event(defines.events.on_selected_entity_changed, function(event)
	update_camera(game.players[event.player_index])
end)

script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
	update_camera(game.players[event.player_index])
end)

script.on_event(defines.events.on_player_created, function(event)
	prepare_gui(game.players[event.player_index])
end)

-- TRAVEL --

local function enter_factory(player, factory)
	player.teleport({factory.inside_door_x, factory.inside_door_y},factory.inside_surface)
	global.last_player_teleport[player.index] = game.tick
	update_camera(player)
end

local function leave_factory(player, factory)
	player.teleport({factory.outside_door_x, factory.outside_door_y},factory.outside_surface)
	global.last_player_teleport[player.index] = game.tick
	update_camera(player)
	update_overlay(factory)
end

local function teleport_players()
	local tick = game.tick
	for player_index, player in pairs(game.players) do
		if player.connected and not player.driving and tick - (global.last_player_teleport[player_index] or 0) >= 45 then
			local walking_state = player.walking_state
			if walking_state.walking then
				if walking_state.direction == defines.direction.north
				or walking_state.direction == defines.direction.northeast
				or walking_state.direction == defines.direction.northwest then
					-- Enter factory
					local factory = find_factory_by_building(player.surface, {{player.position.x-0.2, player.position.y-0.3},{player.position.x+0.2, player.position.y}})
					if factory ~= nil then
						if math.abs(player.position.x-factory.outside_x)<0.6 then
							enter_factory(player, factory)
						end
					end
				elseif walking_state.direction == defines.direction.south
				or walking_state.direction == defines.direction.southeast
				or walking_state.direction == defines.direction.southwest then
					local factory = find_surrounding_factory(player.surface, player.position)
					if factory ~= nil then
						if player.position.y > factory.inside_door_y+1 then
							leave_factory(player, factory)
						end
					end
				end
			end
		end
	end
end

-- POWER MANAGEMENT --

local function transfer_power(from, to)
	local energy = from.energy+to.energy
	local ebs = to.electric_buffer_size
	if energy > ebs then
		to.energy = ebs
		from.energy = energy - ebs
	else
		to.energy = energy
		from.energy = 0
	end
end

-- POLLUTION MANAGEMENT --

local function update_pollution(factory)
	local inside_surface = factory.inside_surface
	local pollution, cp = 0, 0
	local inside_x, inside_y = factory.inside_x, factory.inside_y
	
	cp = inside_surface.get_pollution({inside_x-16,inside_y-16})
	inside_surface.pollute({inside_x-16,inside_y-16},-cp)
	pollution = pollution + cp
	cp = inside_surface.get_pollution({inside_x+16,inside_y-16})
	inside_surface.pollute({inside_x+16,inside_y-16},-cp)
	pollution = pollution + cp
	cp = inside_surface.get_pollution({inside_x-16,inside_y+16})
	inside_surface.pollute({inside_x-16,inside_y+16},-cp)
	pollution = pollution + cp
	cp = inside_surface.get_pollution({inside_x+16,inside_y+16})
	inside_surface.pollute({inside_x+16,inside_y+16},-cp)
	pollution = pollution + cp
	if factory.built then
		factory.outside_surface.pollute({factory.outside_x, factory.outside_y}, pollution + factory.stored_pollution)
		factory.stored_pollution = 0
	else
		factory.stored_pollution = factory.stored_pollution + pollution
	end
end

-- ON TICK --

script.on_event(defines.events.on_tick, function(event)
	local factories = global.factories
	-- Transfer power
	for _, factory in pairs(factories) do
		if factory.built then
			if factory.transfers_outside then
				transfer_power(factory.inside_energy_receiver, factory.outside_energy_sender)
			else
				transfer_power(factory.outside_energy_receiver, factory.inside_energy_sender)
			end
		end
	end
	
	-- Transfer pollution
	local fn = #factories
	local offset = (23*event.tick)%60+1
	while offset <= fn do
		local factory = factories[offset]
		if factory ~= nil then update_pollution(factory) end
		offset = offset + 60
	end
	
	-- Update connections
	Connections.update() -- Duh
	
	-- Teleport players
	teleport_players() -- What did you expect
	
	update_all_construction_requester_chests()
end)

-- CONNECTION SETTINGS --

local CONNECTION_INDICATOR_NAMES = {}
for _,name in pairs(Connections.indicator_names) do
	CONNECTION_INDICATOR_NAMES["factory-connection-indicator-" .. name] = true
end

CONNECTION_INDICATOR_NAMES["factory-connection-indicator-energy-d0"] = true
for _,rate in pairs(Constants.VALID_POWER_TRANSFER_RATES) do
	CONNECTION_INDICATOR_NAMES["factory-connection-indicator-energy-d" .. rate] = true
end

script.on_event(defines.events.on_player_rotated_entity, function(event)
	--game.print("Rotated!")
	local entity = event.entity
	if CONNECTION_INDICATOR_NAMES[entity.name] then
		-- Skip
	elseif Connections.is_connectable(entity) then
		recheck_nearby_connections(entity)
		if entity.type == "underground-belt" then
			local neighbour = entity.neighbours
			if neighbour then
				recheck_nearby_connections(neighbour)
			end
		end
	end
end)

script.on_event("factory-rotate", function(event)
	local player = game.players[event.player_index]
	local entity = player.selected
	if not entity then return end
	if HasLayout(entity.name) then
		local factory = get_factory_by_building(entity)
		if factory then
			-- toggle_port_markers(factory)
			if player.force == factory.force then
				if can_rotate_factory(factory) then
					rotate_factory(factory, 0.25)
				end
			else
				player.print("That building belongs to another team")
			end
		end
	elseif CONNECTION_INDICATOR_NAMES[entity.name] then
		local factory = find_surrounding_factory(entity.surface, entity.position)
		if factory then
			if factory.energy_indicator and factory.energy_indicator.valid and factory.energy_indicator.unit_number == entity.unit_number then
				factory.transfers_outside = not factory.transfers_outside
				factory.inside_surface.create_entity{
					name = "flying-text",
					position = entity.position,
					color = {r = 228/255, g = 236/255, b = 0},
					text = (factory.transfers_outside and {"factory-connection-text.output-mode"}) or {"factory-connection-text.input-mode"}
				}
				update_power_settings(factory)
			else
				Connections.rotate(factory, entity)
			end
		end
	elseif entity.name == "factory-requester-chest" then
		init_factory_requester_chest(entity)
	end
end)

script.on_event("factory-increase", function(event)
	local entity = game.players[event.player_index].selected
	if not entity then return end
	if CONNECTION_INDICATOR_NAMES[entity.name] then
		local factory = find_surrounding_factory(entity.surface, entity.position)
		if factory then
			if factory.energy_indicator and factory.energy_indicator.valid and factory.energy_indicator.unit_number == entity.unit_number then
				adjust_power_transfer_rate(factory, true)
			else
				Connections.adjust(factory, entity, true)
			end
		end
	end
end)

script.on_event("factory-decrease", function(event)
	local entity = game.players[event.player_index].selected
	if not entity then return end
	if CONNECTION_INDICATOR_NAMES[entity.name] then
		local factory = find_surrounding_factory(entity.surface, entity.position)
		if factory then
			if factory.energy_indicator and factory.energy_indicator.valid and factory.energy_indicator.unit_number == entity.unit_number then
				adjust_power_transfer_rate(factory, false)
			else
				Connections.adjust(factory, entity, false)
			end
		end
	end
end)

-- MISC --

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
	local setting = event.setting
	if setting == "Microfactorio-hide-recursion" then
		if settings.global["Microfactorio-hide-recursion"] and settings.global["Microfactorio-hide-recursion"].value then
			for _, force in pairs(game.forces) do
				force.technologies["factory-recursion-t1"].enabled = false
				force.technologies["factory-recursion-t2"].enabled = false
			end
		else
			for _, force in pairs(game.forces) do
				force.technologies["factory-recursion-t1"].enabled = true
				force.technologies["factory-recursion-t2"].enabled = true
			end
		end
	end
end)

script.on_event(defines.events.on_research_finished, function(event)
	if not global.factories then return end -- In case any mod or scenario script calls LuaForce.research_all_technologies() during its on_init
	local research = event.research
	local name = research.name
	if name == "factory-connection-type-fluid" or name == "factory-connection-type-chest" or name == "factory-connection-type-circuit" then
		for _, factory in pairs(global.factories) do
			if factory.built then Connections.recheck_factory(factory, nil, nil) end
		end
	--elseif name == "factory-interior-upgrade-power" then
	--	for _, factory in pairs(global.factories) do build_power_upgrade(factory) end
	elseif name == "factory-interior-upgrade-lights" then
		for _, factory in pairs(global.factories) do build_lights_upgrade(factory) end
	elseif name == "factory-interior-upgrade-display" then
		for _, factory in pairs(global.factories) do build_display_upgrade(factory) end
	elseif name == "factory-interior-upgrade-roboport" then
		for _, factory in pairs(global.factories) do build_roboport_upgrade(factory) end
	-- elseif name == "factory-recursion-t1" or name == "factory-recursion-t2" then
		-- Nothing happens, because implementing stuff here would be horrible.
		-- You just gotta pick up and replace your invalid factories manually for them to work with the newly researched recursion.
	end
end) 
