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
  
  -- Extract track number from param_id for filtering
  local track_match = string.match(param_id, 'track_(%d+)_')
  local track_num = track_match and tonumber(track_match)
  
  -- Check track filtering
  if track_num and #flags.trace_config.tracks > 0 then
    local track_allowed = false
    for _, allowed_track in ipairs(flags.trace_config.tracks) do
      if allowed_track == track_num then
        track_allowed = true
        break
      end
    end
    if not track_allowed then return end
  end
  
  -- Determine log tag based on source
  local log_tag = 'param:change'
  if source == 'set_action' then
    log_tag = 'param:set_action'
  elseif source and source ~= 'set_action' then
    log_tag = 'param:caller'
  end
  
  Tracer.event{
    context_type = 'param',
    param_id     = param_id,
    source       = source,
    track_id     = track_num,
  }:log(log_tag, '%s ← %s (%s)', tostring(param_id), tostring(value), tostring(source))
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
-- Manual tracing for direct params:set() calls
-------------------------------------------------------------------------------
function ParamTrace.trace_set(param_id, value, source)
  ParamTrace.log_value_change(param_id, value, source or 'manual_set')
end

-- Traced wrapper for params:set() that logs the change and then sets the value
function ParamTrace.set(param_id, value, source)
  ParamTrace.log_value_change(param_id, value, source or 'traced_set')
  return params:set(param_id, value)
end

-------------------------------------------------------------------------------
-- Return the module
-------------------------------------------------------------------------------
return ParamTrace
