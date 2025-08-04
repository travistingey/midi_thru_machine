-- feature_flags.lua - central toggle for runtime modes
-- Usage: local feature_flags = require('Foobar/lib/utilities/feature_flags')
--        local flags = feature_flags.flags
--        if flags.test_mode then ... end
--        -- Or use convenience methods:
--        feature_flags.toggle_flag('verbose')
--        feature_flags.set_flag('verbose', true)
--        local value = feature_flags.get_flag('verbose')
--        feature_flags.list_flags()
-- Flags are set once at startup and cached by Lua's require mechanism.

local boolean_flags = {
	unit_test = false, -- runs unit tests in scripts
	verbose = false, -- flip this inside a script for extra prints
	load_trace = true, -- trace the load order of scripts
}
local trace_flags = {
  trace_device = false, -- trace events propegating through devices in devicemanager
  trace_track = false, -- trace track events
  trace_chain = false, -- trace the chain of events through a track
	trace_component = false, -- trace component events
}

-- Merge the tables
local flags = {}
for k, v in pairs(boolean_flags) do
	flags[k] = v
end
for k, v in pairs(trace_flags) do
	flags[k] = v
end

-- Feature flag management methods
local function toggle_flag(flag_name)
	if boolean_flags[flag_name] ~= nil then
		flags[flag_name] = not flags[flag_name]
		print("Feature flag '" .. flag_name .. "' set to: " .. tostring(flags[flag_name]))
	else
		print("Connot toggle feature flag: " .. flag_name)
	end
end

local function set_flag(flag_name, value)
	if flags[flag_name] ~= nil and value ~= nil then -- protect against setting to nil
		flags[flag_name] = value
		print("Feature flag '" .. flag_name .. "' set to: " .. tostring(flags[flag_name]))
	else
		print("Unknown feature flag: " .. flag_name)
	end
end

local function get_flag(flag_name)
	if flags[flag_name] ~= nil then
		return flags[flag_name]
	else
		print("Unknown feature flag: " .. flag_name)
		return nil
	end
end

local function list_flags()
	print("Available feature flags:")
	for flag_name, value in pairs(flags) do
		print("  " .. flag_name .. " = " .. tostring(value))
	end
end

-- Return both the flags table and the management methods
return {
	flags = flags,
	toggle = toggle_flag,
	set = set_flag,
	get = get_flag,
	list = list_flags,
}
