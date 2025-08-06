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

-- Helper function to detect calling component from stack trace
local function detect_calling_component()
  -- Look through multiple stack levels to find the actual calling component
  for level = 3, 10 do  -- Check levels 3-10
    local info = debug.getinfo(level, "S")
    
    if not info then break end
    
    local source = info.source
    if not source then break end
    
    -- Skip param_trace.lua itself
    if string.find(source, "param_trace.lua") then
      goto continue
    end
    
    -- Extract component name from file path
    local component_match = string.match(source, "/([^/]+)%.lua$")
    if component_match and component_match ~= "param_trace" then
      return component_match
    end
    
    -- Try to match specific patterns
    if string.find(source, "track/") then
      local track_component = string.match(source, "track/([^/]+)%.lua$")
      if track_component then
        return track_component
      end
    end
    
    if string.find(source, "components/") then
      local component = string.match(source, "components/([^/]+)%.lua$")
      if component then
        return component
      end
    end
    
    ::continue::
  end
  
  return nil
end

-- Helper function to check component filtering with hierarchy
local function check_component_filtering(component_name)
  if not component_name or #flags.trace_config.components == 0 then
    return true  -- No filtering if no component or no component filter
  end
  
  -- Check exact component match
  for _, allowed_component in ipairs(flags.trace_config.components) do
    if allowed_component == component_name then
      return true
    end
  end
  
  -- Check hierarchical matches
  if component_name == 'track' then
    -- Track components are always allowed if 'track' is in the filter
    for _, allowed_component in ipairs(flags.trace_config.components) do
      if allowed_component == 'track' then
        return true
      end
    end
  elseif component_name == 'trackcomponent' then
    -- TrackComponent is allowed if 'trackcomponent' is in the filter
    for _, allowed_component in ipairs(flags.trace_config.components) do
      if allowed_component == 'trackcomponent' then
        return true
      end
    end
  end
  
  return false
end

-------------------------------------------------------------------------------
-- Core logging functions
-------------------------------------------------------------------------------

function ParamTrace.log_registration(param_id, registration_type)
  if not flags.trace_config.load_trace then return end
  
  -- Extract component ID from param_id for filtering
  local component_id = nil
  local component_type = nil
  
  -- Try different component ID patterns
  local track_match = string.match(param_id, 'track_(%d+)_')
  if track_match then
    component_id = tonumber(track_match)
    component_type = 'track'
  else
    local scale_match = string.match(param_id, 'scale_(%d+)_')
    if scale_match then
      component_id = tonumber(scale_match)
      component_type = 'scale'
    else
      local device_match = string.match(param_id, 'device_(%d+)_')
      if device_match then
        component_id = tonumber(device_match)
        component_type = 'device'
      end
    end
  end
  
  -- Check ID filtering for load-time registration
  if component_id and #flags.trace_config.tracks > 0 then
    local id_allowed = false
    for _, allowed_id in ipairs(flags.trace_config.tracks) do
      if allowed_id == component_id then
        id_allowed = true
        break
      end
    end
    if not id_allowed then return end
  end
  
  -- Detect calling component for filtering
  local calling_component = detect_calling_component()
  
  -- Check component filtering for registration
  if not check_component_filtering(calling_component) then
    return
  end
  
  Tracer.load():log('param:register', '%s %s', tostring(registration_type), tostring(param_id))
end

function ParamTrace.log_set_action(param_id)
  if not flags.trace_config.load_trace then return end
  
  -- Extract component ID from param_id for filtering
  local component_id = nil
  local component_type = nil
  
  -- Try different component ID patterns
  local track_match = string.match(param_id, 'track_(%d+)_')
  if track_match then
    component_id = tonumber(track_match)
    component_type = 'track'
  else
    local scale_match = string.match(param_id, 'scale_(%d+)_')
    if scale_match then
      component_id = tonumber(scale_match)
      component_type = 'scale'
    else
      local device_match = string.match(param_id, 'device_(%d+)_')
      if device_match then
        component_id = tonumber(device_match)
        component_type = 'device'
      end
    end
  end
  
  -- Check ID filtering for set_action registration
  if component_id and #flags.trace_config.tracks > 0 then
    local id_allowed = false
    for _, allowed_id in ipairs(flags.trace_config.tracks) do
      if allowed_id == component_id then
        id_allowed = true
        break
      end
    end
    if not id_allowed then return end
  end
  
  -- Detect calling component for filtering
  local calling_component = detect_calling_component()
  
  -- Check component filtering for set_action
  if not check_component_filtering(calling_component) then
    return
  end
  
  Tracer.load():log('param:set_action', 'set_action %s', tostring(param_id))
end

function ParamTrace.log_value_change(param_id, value, source)
  if not flags.trace_config.params then return end
  
  -- Extract component ID from param_id for filtering
  local component_id = nil
  local component_type = nil
  
  -- Try different component ID patterns
  local track_match = string.match(param_id, 'track_(%d+)_')
  if track_match then
    component_id = tonumber(track_match)
    component_type = 'track'
  else
    local scale_match = string.match(param_id, 'scale_(%d+)_')
    if scale_match then
      component_id = tonumber(scale_match)
      component_type = 'scale'
    else
      local device_match = string.match(param_id, 'device_(%d+)_')
      if device_match then
        component_id = tonumber(device_match)
        component_type = 'device'
      end
    end
  end
  
  -- Check ID filtering (generalized from track filtering)
  if component_id and #flags.trace_config.tracks > 0 then
    local id_allowed = false
    for _, allowed_id in ipairs(flags.trace_config.tracks) do
      if allowed_id == component_id then
        id_allowed = true
        break
      end
    end
    if not id_allowed then return end
  end
  
  -- Detect calling component for filtering
  local calling_component = detect_calling_component()
  
  -- Check component filtering
  if not check_component_filtering(calling_component) then
    return
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
    track_id     = component_id,  -- Use component_id for backward compatibility
    component_name = calling_component,
    component_type = component_type,
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
