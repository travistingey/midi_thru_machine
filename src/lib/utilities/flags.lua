-- lib/utilities/flags.lua
--
-- Centralised feature-flag system with nested configuration tables.
-- Each flag table is wrapped with a metatable that
--   • exposes helper methods (toggle / set / get / list)
--   • prevents writes to unknown keys
--   • propagates the same behaviour to every nested flag table.
--
-- Example usage:
--   local flags = require('Foobar/lib/utilities/flags')
--   flags.toggle('verbose')                 -- top-level flag
--   flags.trace_config.set('tracks', {1})   -- nested table mutation
--   if flags.state.playing then ... end     -- runtime state
--
---------------------------------------------------------------------------
--  Helper factories
---------------------------------------------------------------------------

-- Toggle a boolean flag
local function toggle_factory(tbl, tbl_name)
  return function(name)
    if rawget(tbl, name) ~= nil then
      tbl[name] = not tbl[name]
      print(('%s "%s" set to %s'):format(tbl_name, name, tostring(tbl[name])))
    else
      print(('%s "%s" does not exist'):format(tbl_name, name))
    end
  end
end

-- Assign a value to an existing flag
local function set_factory(tbl, tbl_name)
  return function(name, value)
    if rawget(tbl, name) ~= nil and value ~= nil then
      tbl[name] = value
      print(('%s "%s" set to %s'):format(tbl_name, name, tostring(value)))
    else
      print(('%s "%s" does not exist'):format(tbl_name, name))
    end
  end
end

local function get_factory(tbl)
  return function(name) return rawget(tbl, name) end
end

local function list_factory(tbl, tbl_name)
  return function()
    print('Listing ' .. tbl_name)
    for k, v in pairs(tbl) do print(k, v) end
  end
end

-- __index dispatcher that returns helpers or flag values
local function method_factory(tbl, tbl_name)
  return function(_, key)
    if key == 'toggle' then      return toggle_factory(tbl, tbl_name)
    elseif key == 'set' then     return set_factory(tbl, tbl_name)
    elseif key == 'get' then     return get_factory(tbl)
    elseif key == 'list' then    return list_factory(tbl, tbl_name)
    else                         return rawget(tbl, key) end
  end
end

local function flag_factory(tbl, tbl_name)
  setmetatable(tbl, {
    __index = method_factory(tbl, tbl_name),
    __newindex = function(_, key, _)
      print('Flag does not exist in ' .. tbl_name .. ': ' .. key)
    end,
  })
  return tbl
end

---------------------------------------------------------------------------
--  Concrete flag tables
---------------------------------------------------------------------------

-- Global feature toggles
local feature_flag_values = {
  unit_test  = false,
  verbose    = false,
}

-- Application runtime state flags (mutated by the app itself)
local state_flag_values = {
  initializing   = true,
  playing        = false,
  recording      = false,
  current_mode   = 1,
  current_track  = 1,
}

-- Tracer-specific configuration
local trace_config_values = {
  -- Filters
  devices      = {},
  tracks       = {1},
  components   = {},
  chains       = {},
  event_types  = {'midi'},

  -- Behaviours
  correlate_flows = true,
  show_timestamps = false,
  events          = false,
  params          = true,
  modes           = false,
  load_trace      = true,

  -- Verbosity
  verbose_level   = 3,
}

---------------------------------------------------------------------------
--  Assemble and export
---------------------------------------------------------------------------

local flags        = flag_factory(feature_flag_values, 'Flags')
local trace_config = flag_factory(trace_config_values, 'Trace config')
local state_flags  = flag_factory(state_flag_values, 'State')

-- Inject nested tables using rawset to bypass the __newindex guard
rawset(flags, 'trace_config', trace_config)
rawset(flags, 'state',        state_flags)

return flags
