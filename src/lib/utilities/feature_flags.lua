-- feature_flags.lua - central toggle for runtime modes
-- Usage: local flags = require('Foobar/lib/utilities/feature_flags')
--        if flags.test_mode then ... end
-- Flags are set once at startup and cached by Lua’s require mechanism.

local flags = {
  unit_test  = false, -- runs unit tests in scripts
  verbose = true, -- flip this inside a script for extra prints
  load_trace = false, -- trace the load order of scripts
  device_trace = false, -- trace events propegating through devices in devicemanager
  param_trace = false, -- trace param changes over time
}

return flags
