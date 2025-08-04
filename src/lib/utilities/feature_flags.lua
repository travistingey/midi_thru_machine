-- feature_flags.lua  (excerpt – only the bits that change)

--   BOOL toggles that apply everywhere
local boolean_flags = {
    unit_test  = false,
    verbose    = false,
    load_trace = true,
    correlate_flows = true,
    events      = false,
    params      = false,
    modes       = false,
}

--   All the tracer-specific knobs live here now
local trace_config = {
    -- Hierarchy filters
    devices     = {},
    tracks      = {1},
    components  = {},
    chains      = {'midi', 'transport'},

    -- Output options
    show_timestamps = false,
    max_data_length = 100,
    verbose_level   = 3,
}

--   Merge once; every module shares the resulting table
local flags = {}
for k, v in pairs(boolean_flags)  do flags[k] = v end
for k, v in pairs(trace_config)   do flags[k] = v end

-----------------------------------------------------------------
--   Flag helpers (now work for *any* key inside `flags`)
-----------------------------------------------------------------
local function toggle_flag(name)
    if flags[name] ~= nil then
        flags[name] = not flags[name]
        print(("Feature flag '%s' set to %s"):format(name,tostring(flags[name])))
    else
        print(("Cannot toggle unknown feature flag: %s"):format(name))
    end
end

local function set_flag(name, value)
    if flags[name] ~= nil and value ~= nil then
        flags[name] = value
        print(("Feature flag '%s' set to %s"):format(name,tostring(value)))
    else
        print(("Unknown feature flag: %s"):format(name))
    end
end
-----------------------------------------------------------------

return {
    flags = flags,       -- <- single shared table
    toggle = toggle_flag,
    set    = set_flag,
    get    = function(n) return flags[n] end,
    list   = function() for k,v in pairs(flags) do print(k,v) end end,
}