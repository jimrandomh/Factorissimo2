
Constants = {
	-- Range of IDs for initialized factories. To change this, you also need to
	-- change the range of strings in the local files.
	factory_id_min = 10,
	factory_id_max = 99,
	
	factory_type_names = {"factory-tiny","factory-1", "factory-2", "factory-3"},
	
	overlay_slot_count = 4,

	-- Don't mess with this unless you mess with prototypes/entity/component.lua too (in the place marked <E>).
	-- Every number needs to correspond to a valid indicator entity name
	VALID_POWER_TRANSFER_RATES = {1,2,5,10,20,50,100,200,500,1000,2000,5000,10000,20000,50000,100000} -- MW
}

