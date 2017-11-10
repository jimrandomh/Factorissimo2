data:extend({
	-- Startup

	{
		type = "bool-setting",
		name = "microfactorio-easy-research",
		setting_type = "startup",
		default_value = false,
		order = "a"
	},

	-- Global

	{
		type = "bool-setting",
		name = "microfactorio-free-recursion",
		setting_type = "runtime-global",
		default_value = false,
		order = "a-a",
	},
	{
		type = "bool-setting",
		name = "microfactorio-hide-recursion",
		setting_type = "runtime-global",
		default_value = false,
		order = "a-b",
	},

	-- Per user

	{
		type = "bool-setting",
		name = "microfactorio-preview-enabled",
		setting_type = "runtime-per-user",
		default_value = true,
		order = "a-a",
	},
	{
		type = "int-setting",
		name = "microfactorio-preview-size",
		setting_type = "runtime-per-user",
		minimum_value = 50,
		default_value = 300,
		maximum_value = 1000,
		order = "a-b",
	},
	{
		type = "double-setting",
		name = "microfactorio-preview-zoom",
		setting_type = "runtime-per-user",
		minimum_value = 0.2,
		default_value = 1,
		maximum_value = 2,
		order = "a-c",
	},
})
