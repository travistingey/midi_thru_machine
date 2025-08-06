-- lib/utilities/param_trace.lua
--
-- Clean parameter tracing utilities that don't interfere with the environment.
-- This module provides manual tracing functions that can be called explicitly
-- where needed, without any global monkey-patching.
--
-- Usage: 
--   local param_trace = require('Foobar/lib/utilities/param_trace')
--   param_trace.log_registration('my_param', 'add_number')
--   param_trace.log_set_action('my_param')
--   param_trace.log_value_change('my_param', 42, 'user_input')
-----------------------------------------------------------------------------

local Tracer = require('Foobar/lib/utilities/tracer')
local flags  = require('Foobar/lib/utilities/feature_flags')

local ParamTrace = {}

-------------------------------------------------------------------------------
-- Core logging functions
-------------------------------------------------------------------------------

function ParamTrace.log_registration(param_id, registration_type)
  if not flags.trace_config.load_trace then return end
  Tracer.load():log('param:register', '%s %s', tostring(registration_type), tostring(param_id))
end

function ParamTrace.log_set_action(param_id)
  if not flags.trace_config.load_trace then return end
  Tracer.load():log('param:set_action', 'set_action %s', tostring(param_id))
end

function ParamTrace.log_value_change(param_id, value, source)
  if not flags.trace_config.params then return end
  Tracer.event{
    context_type = 'param',
    param_id     = param_id,
    source       = source,
  }:log('param:change', '%s ← %s (%s)', tostring(param_id), tostring(value), tostring(source))
end

-------------------------------------------------------------------------------
-- Convenience wrapper for set_action that includes tracing
-------------------------------------------------------------------------------
function ParamTrace.set_action_with_trace(param_id, callback)
  ParamTrace.log_set_action(param_id)
  
  if not callback then
    return params:set_action(param_id, nil)
  end
  
  local wrapped = function(value, ...)
    ParamTrace.log_value_change(param_id, value, 'set_action')
    return callback(value, ...)
  end
  
  return params:set_action(param_id, wrapped)
end

-------------------------------------------------------------------------------
-- Helper for tracking parameter registration with automatic ID extraction
-------------------------------------------------------------------------------
function ParamTrace.add_with_trace(registration_type, ...)
  local param_id = select(1, ...)
  ParamTrace.log_registration(param_id, registration_type)
  return params[registration_type](params, ...)
end

-------------------------------------------------------------------------------
-- Return the module
-------------------------------------------------------------------------------
return ParamTrace
