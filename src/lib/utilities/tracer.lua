-- tracer.lua - Comprehensive tracing system for data flow debugging
-- Supports Device Manager → Tracks → Track Components → Output flow
-- Handles shared components, events, params, and modes

local diagnostics    = require('Foobar/lib/utilities/diagnostics')
local flags  = require('Foobar/lib/utilities/feature_flags')
local cfg = flags.trace_config

local Tracer = {}
Tracer.__index = Tracer

-- Trace context types for different parts of the system
local CONTEXT_TYPES = {
    DEVICE = 'device',
    TRACK = 'track', 
    COMPONENT = 'component',
    CHAIN = 'chain',
    EVENT = 'event',
    PARAM = 'param',
    MODE = 'mode',
    LOAD = 'load'
}

-- Data flow event types
local EVENT_TYPES = {
    EMIT = 'emit',
    MIDI = 'midi',
    CC = 'cc', 
    PROGRAM_CHANGE = 'program_change',
    SEND = 'send',
    TRANSPORT = 'transport',
    MIXER = 'mixer'
}

-- Performance cache for trace decisions
local trace_cache = {
    cache = {},
    cache_expires = 0,
    cache_duration = 60 -- seconds
}

--==============================================================================
-- Core Tracer Class
--==============================================================================

function Tracer:new(context)
    local instance = {
        context = context or {},
        enabled = false
    }
    setmetatable(instance, self)
    
    -- Determine if this tracer instance should be enabled
    instance.enabled = instance:should_trace()
    
    return instance
end

function Tracer:should_trace()
    
    -- Check cache first for performance
    local cache_key = self:build_cache_key()
    local now = util.time()
    
    if trace_cache.cache[cache_key] and now < trace_cache.cache_expires then
        return trace_cache.cache[cache_key]
    end
    
    -- Evaluate trace conditions
    local should_trace = self:evaluate_trace_conditions()
    

    
    -- Cache the result
    if now >= trace_cache.cache_expires then
        trace_cache.cache = {} -- Clear expired cache
        trace_cache.cache_expires = now + trace_cache.cache_duration
    end
    trace_cache.cache[cache_key] = should_trace
    return should_trace
end

-----------------------------------------------------------------
-- Tracer:evaluate_trace_conditions()
-----------------------------------------------------------------
function Tracer:evaluate_trace_conditions()
    local ctx = self.context

    -- 1. honour global hammer
    if flags.verbose then return true end

    -- 2. using the feature flags
    local hit = false
    
    if ctx.track_id   and #cfg.tracks      > 0 then hit = self:contains(cfg.tracks, ctx.track_id)   end
    if ctx.device_id  and #cfg.devices     > 0 then hit = hit or self:contains(cfg.devices, ctx.device_id) end
    if ctx.component_name and #cfg.components > 0 then hit = hit or self:contains(cfg.components, ctx.component_name) end
    if ctx.event_type and #cfg.event_types      > 0 then hit = hit or self:contains(cfg.event_types, ctx.event_type) end

    if ctx.context_type == 'load'  and cfg.load_trace then hit = true end
    if ctx.context_type == 'event' and cfg.events     then hit = true end
    if ctx.context_type == 'param' and cfg.params     then hit = true end
    if ctx.context_type == 'mode'  and cfg.modes      then hit = true end

    return hit
end

function Tracer:contains(table, value)
    for _, v in ipairs(table) do
        if v == value then return true end
    end
    return false
end

function Tracer:build_cache_key()
    local ctx = self.context
    return string.format("%s:%s:%s:%s:%s", 
        ctx.device_id or "nil",
        ctx.track_id or "nil", 
        ctx.component_name or "nil",
        ctx.event_type or "nil",
        ctx.context_type or "nil"
    )
end

--==============================================================================
-- Logging Methods
--==============================================================================

function Tracer:log(level, fmt, ...)
    if not self.enabled then return end
    local message = self:format_message(level, fmt, ...)
    diagnostics.log(message, ...)
end

function Tracer:log_flow(step, data, output)
    if not self.enabled then return end
    
    -- Extract correlation ID from the data itself
    local flow_id = ""
    
    if cfg.correlate_flows then
        if type(data) == "table" and data.correlation_id then
            flow_id = data.correlation_id:sub(-4) -- Just show last 4 chars
        elseif type(output) == "table" and output.correlation_id then
            flow_id = output.correlation_id:sub(-4)
        end
    end
    
    local ctx = self.context
    local track_info = ""
    if ctx.track_id then
        track_info = string.format("TRACK %d", ctx.track_id)
    end
    
    -- Build bracket content based on step and settings
    local bracket_content = ""
    if step == "chain_start" then
        if flow_id ~= "" then
            bracket_content = track_info .. ":" .. flow_id
        else
            bracket_content = "START"
        end
    elseif step == "chain_complete" then
            bracket_content = "END"
        
    elseif step == "chain_terminated" then
            bracket_content = "STOP"
    else
        -- Component step
        bracket_content = step:upper()
    end
    
    -- Apply verbose level filtering
    local verbose_level = cfg.verbose_level or 1
    
    if step == "chain_start" then
        local event_info = ctx.event_type and (ctx.event_type .. ":\t") or ""
        diagnostics.log("┌─[%s]\t%s%s", bracket_content, event_info, self:format_data(data))
    elseif step == "chain_complete" then
        local event_info = ctx.event_type and (ctx.event_type .. ":\t") or ""
        diagnostics.log("└─[%s]\t%s%s", bracket_content, event_info, self:format_data(data))
    elseif step == "chain_terminated" then
        diagnostics.log("✗─[%s]\t%sterminated", bracket_content, track_info)
    else
        -- Component step - only show based on verbose level
        if verbose_level >= 2 then
            -- Check if this is a transformation (data changed)
            local show_component = true
            if verbose_level == 2 then
                -- Level 2: only show if transformation occurred
                show_component = self:has_transformation(data, output)
            end
            -- Level 3: show all components
            
            if show_component then
                diagnostics.log("| [%s] %s:\t%s", bracket_content, step, self:format_data(data))
            end
        end
    end
end

function Tracer:has_transformation(input, output)
    -- Simple transformation detection
    if not input or not output then return false end
    
    -- Check if any key values changed
    for k, v in pairs(output) do
        if k ~= "correlation_id" and input[k] ~= v then
            return true
        end
    end
    
    -- Check if input has keys that output doesn't
    for k, v in pairs(input) do
        if k ~= "correlation_id" and output[k] == nil then
            return true
        end
    end
    
    return false
end

function Tracer:format_data(data)
    if type(data) ~= "table" then
		return data
	end

	local delimiter = ":"
	local parts = {}

	for k, v in pairs(data) do
		table.insert(parts, tostring(k) .. delimiter .. tostring(v))
	end
    
    if #parts > 0 then
        return table.concat(parts, "\t")
    else
        return "(empty)"
    end
end

function Tracer:log_event(event_name, data, listener_count)
    -- Minimal implementation for now
    if not self.enabled then return end
    diagnostics.log("EVENT: %s", event_name)
end

function Tracer:log_load(component_name, load_id)
    -- Minimal implementation for now
    if not cfg.load_trace then return end
    diagnostics.log("LOAD: %s", component_name)
end

function Tracer:format_message(level, fmt, ...)
    return string.format("[%s] %s", level:upper(), fmt)
end

--==============================================================================
-- Factory Methods
--==============================================================================

function Tracer.device(device_id, event_type)
    return Tracer:new({
        context_type = CONTEXT_TYPES.DEVICE,
        device_id = device_id,
        event_type = event_type
    })
end

function Tracer.track(track_id, event_type)
    return Tracer:new({
        context_type = CONTEXT_TYPES.TRACK,
        track_id = track_id,
        event_type = event_type
    })
end

function Tracer.component(component, track, event_type)
    local track_id = nil
    local component_name = component.name
    if component.track then
        track_id = component.track.id
    elseif track then
        track_id = track.id
    end
    return Tracer:new({
        context_type = CONTEXT_TYPES.COMPONENT,
        component_name = component_name,
        track_id = track_id,
        event_type = event_type
    })
end

function Tracer.chain(track_id, event_type)
    return Tracer:new({
        context_type = CONTEXT_TYPES.CHAIN,
        track_id = track_id,
        event_type = event_type
    })
end

function Tracer.event(source_context)
    local ctx = {}
    if source_context then
        for k, v in pairs(source_context) do
            ctx[k] = v
        end
    end
    -- Only set context_type to EVENT if not already specified
    if not ctx.context_type then
        ctx.context_type = CONTEXT_TYPES.EVENT
    end
    return Tracer:new(ctx)
end

function Tracer.load()
    return Tracer:new({
        context_type = CONTEXT_TYPES.LOAD
    })
end

function Tracer.for_track_component(component, track, event_type)
    local track_id = nil
    if component.track then
        track_id = component.track.id
    elseif track then
        track_id = track.id
    end
    return Tracer.component(component.name, track_id, event_type)
end

function Tracer.add_correlation_id(data)
    if not cfg.correlate_flows then
        return data
    end
    
    -- Don't add if already present
    if type(data) == "table" and data.correlation_id then
        return data
    end
    
    -- Create a copy to avoid modifying original
    local data_with_id = {}
    if type(data) == "table" then
        for k, v in pairs(data) do
            data_with_id[k] = v
        end
    else
        data_with_id = {value = data}
    end
    
    -- Generate correlation ID
    data_with_id.correlation_id = string.format("flow_%d_%d", 
        math.floor(util.time() * 1000), 
        math.random(1000, 9999))
    
    return data_with_id
end

-- CLI Functions - directly modify the feature flags
function Tracer.trace_tracks(...)

    flags.trace_config.set('tracks', {...})
    if next(cfg.tracks) then
        print("Tracing tracks: " .. table.concat(cfg.tracks, ", "))
    else
        print("Tracing tracks: NONE")
    end
    Tracer.clear_cache()
end

function Tracer.trace_clear()
    flags.trace_config.set('tracks', {})
    flags.trace_config.set('devices', {})
    flags.trace_config.set('components', {})
    flags.trace_config.set('chains', {})
    flags.trace_config.set('verbose_level', 1)
    flags.trace_config.set('correlate_flows', false)
    flags.trace_config.set('events', false)
    flags.trace_config.set('params', false)
    flags.trace_config.set('modes', false)
    flags.trace_config.set('load_trace', false)
    Tracer.clear_cache()
    print("All tracing cleared")
end

function Tracer.trace_show()
    print("=== Trace Configuration ===")
    print("Tracks: " .. (next(cfg.tracks) and 
        table.concat(cfg.tracks, ", ") or "NONE"))
    print("Verbose Level: " .. cfg.verbose_level)
    print("Flow Correlation: " .. (cfg.correlate_flows and "ON" or "OFF"))
    print("Events: " .. (cfg.events and "ON" or "OFF"))
    print("Params: " .. (cfg.params and "ON" or "OFF"))
    print("Load Order: " .. (cfg.load_trace and "ON" or "OFF"))
end

function Tracer.verbose_level(level)
    if level then
        flags.trace_config.set('verbose_level', level)
        local level_names = {"minimal", "detailed", "full"}
        print("Verbose level: " .. level .. " (" .. (level_names[level] or "unknown") .. ")")
    else
        print("Current verbose level: " .. cfg.verbose_level)
        print("Levels: 1=minimal, 2=detailed, 3=full")
    end
end

function Tracer.trace_flows(enabled)
    if enabled == nil then enabled = true end
    flags.trace_config.set('correlate_flows', enabled)
    print("Flow correlation: " .. (enabled and "ON" or "OFF"))
end

function Tracer.trace_events(enabled)
    if enabled == nil then enabled = true end
    flags.trace_config.set('events', enabled)
    print("Event tracing: " .. (enabled and "ON" or "OFF"))
end

function Tracer.trace_params(enabled)
    if enabled == nil then enabled = true end
    flags.trace_config.set('params', enabled)
    print("Parameter tracing: " .. (enabled and "ON" or "OFF"))
end

function Tracer.trace_load_trace(enabled)
    if enabled == nil then enabled = true end
    flags.trace_config.set('load_trace', enabled)
    print("Load order tracing: " .. (enabled and "ON" or "OFF"))
end

function Tracer.clear_cache()
    -- Clear the performance cache when settings change
    trace_cache.cache = {}
    trace_cache.cache_expires = 0
end

function Tracer.trace_help()
    print("=== Trace CLI Commands ===")
    print("Quick setup:")
    print("  trace_tracks(1)          -- trace track 1")
    print("  trace_clear()            -- clear all tracing")
    print("  trace_show()             -- show current config")
    print("")
    print("Options:")
    print("  trace_verbose(1)         -- 1=minimal, 2=detailed, 3=full")
    print("  trace_flows(true)        -- enable correlation IDs")
    print("")
    print("Features:")
    print("  trace_events(true)       -- trace event system")
    print("  trace_params(true)       -- trace parameter changes")
    print("  trace_load_trace(true)   -- trace component loading")
    print("")
    print("Utility:")
    print("  trace_help()             -- show this help")
end

return Tracer
