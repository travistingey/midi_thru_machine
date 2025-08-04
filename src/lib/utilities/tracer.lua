-- tracer.lua - Comprehensive tracing system for data flow debugging
-- Supports Device Manager → Tracks → Track Components → Output flow
-- Handles shared components, events, params, and modes

local diagnostics = require('Foobar/lib/utilities/diagnostics')
local feature_flags = require('Foobar/lib/utilities/feature_flags')

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
    MIDI = 'midi',
    CC = 'cc', 
    TRANSPORT = 'transport',
    MIXER = 'mixer'
}

-- Global trace configuration - single source of truth
local trace_config = {
    -- Hierarchical filters
    devices = {}, -- device IDs to trace
    tracks = {}, -- track IDs to trace (1-16) - EMPTY means NO tracing by default
    components = {}, -- component names to trace ('seq', 'scale', etc.)
    chains = {}, -- chain types to trace ('midi', 'cc', 'transport')
    
    -- Feature filters
    events = false, -- trace event system
    params = false, -- trace param changes
    modes = false, -- trace mode/screen interactions
    load_order = false, -- trace load order
    
    -- Output options
    correlate_flows = false, -- add correlation IDs for flow tracking
    show_timestamps = false, -- add timestamps to logs
    max_data_length = 100, -- truncate long data strings
    verbose_level = 1 -- 1=minimal, 2=detailed, 3=full
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

function Tracer:evaluate_trace_conditions()
    local ctx = self.context
    
    -- Always trace if verbose mode is on
    if feature_flags.get('verbose') then
        return true
    end
    
    -- Default is OFF - only trace if explicitly enabled
    local should_trace = false
    
    -- Check if this context matches any enabled filters
    
    -- 1. Track level filtering - most common
    if ctx.track_id and #trace_config.tracks > 0 then
        should_trace = self:contains(trace_config.tracks, ctx.track_id)
    end
    
    -- 2. Device level filtering  
    if ctx.device_id and #trace_config.devices > 0 then
        should_trace = should_trace or self:contains(trace_config.devices, ctx.device_id)
    end
    
    -- 3. Component level filtering
    if ctx.component_name and #trace_config.components > 0 then
        should_trace = should_trace or self:contains(trace_config.components, ctx.component_name)
    end
    
    -- 4. Chain/Event type filtering
    if ctx.event_type and #trace_config.chains > 0 then
        should_trace = should_trace or self:contains(trace_config.chains, ctx.event_type)
    end
    
    -- 5. Feature-specific filtering
    if ctx.context_type then
        if ctx.context_type == 'load' and trace_config.load_order then
            should_trace = true
        elseif ctx.context_type == 'event' and trace_config.events then
            should_trace = true
        elseif ctx.context_type == 'param' and trace_config.params then
            should_trace = true
        elseif ctx.context_type == 'mode' and trace_config.modes then
            should_trace = true
        end
    end
    
    return should_trace
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
    
    if trace_config.correlate_flows then
        if type(data) == "table" and data.correlation_id then
            flow_id = data.correlation_id:sub(-4) -- Just show last 4 chars
        elseif type(output) == "table" and output.correlation_id then
            flow_id = output.correlation_id:sub(-4)
        end
    end
    
    local ctx = self.context
    local track_info = ""
    if ctx.track_id then
        track_info = string.format("Track %d\t", ctx.track_id)
    end
    
    -- Build bracket content based on step and settings
    local bracket_content = ""
    if step == "chain_start" then
        if flow_id ~= "" then
            bracket_content = "START:" .. flow_id
        else
            bracket_content = "START"
        end
    elseif step == "chain_complete" then
        if flow_id ~= "" then
            bracket_content = "END:" .. flow_id
        else
            bracket_content = "END"
        end
    elseif step == "chain_terminated" then
        if flow_id ~= "" then
            bracket_content = "STOP:" .. flow_id
        else
            bracket_content = "STOP"
        end
    else
        -- Component step
        if flow_id ~= "" then
            bracket_content = step:upper() .. ":" .. flow_id
        else
            bracket_content = step:upper()
        end
    end
    
    -- Apply verbose level filtering
    local verbose_level = trace_config.verbose_level or 1
    
    if step == "chain_start" then
        local event_info = ctx.event_type and (ctx.event_type .. ":\t") or ""
        diagnostics.log("┌─[%s] %s%s%s", bracket_content, track_info, event_info, self:format_data(data))
    elseif step == "chain_complete" then
        local event_info = ctx.event_type and (ctx.event_type .. ":\t") or ""
        diagnostics.log("└─[%s] %s%s%s", bracket_content, track_info, event_info, self:format_data(data))
    elseif step == "chain_terminated" then
        diagnostics.log("✗─[%s] %sterminated", bracket_content, track_info)
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
                diagnostics.log("  [%s] %s:\t%s", bracket_content, step, self:format_data(data))
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
        return tostring(data)
    end
    
    -- Create clean copy without correlation_id for display
    local clean_data = {}
    for k, v in pairs(data) do
        if k ~= "correlation_id" then
            clean_data[k] = v
        end
    end
    
    local parts = {}
    
    -- MIDI data formatting
    if clean_data.note then table.insert(parts, "note:" .. clean_data.note) end
    if clean_data.vel then table.insert(parts, "vel:" .. clean_data.vel) end
    if clean_data.ch then table.insert(parts, "ch:" .. clean_data.ch) end
    
    -- Transport data formatting
    if clean_data.type then table.insert(parts, "type:" .. clean_data.type) end
    if clean_data.beat then table.insert(parts, "beat:" .. clean_data.beat) end
    if clean_data.position then table.insert(parts, "pos:" .. clean_data.position) end
    if clean_data.bpm then table.insert(parts, "bpm:" .. clean_data.bpm) end
    
    -- CC data formatting  
    if clean_data.cc then table.insert(parts, "cc:" .. clean_data.cc) end
    if clean_data.val then table.insert(parts, "val:" .. clean_data.val) end
    
    -- Generic handling for any other fields
    for k, v in pairs(clean_data) do
        if not string.match(k, "^(note|vel|ch|type|beat|position|bpm|cc|val)$") then
            table.insert(parts, k .. ":" .. tostring(v))
        end
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
    if not self.enabled then return end
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

function Tracer.component(component_name, track_id, event_type)
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
    ctx.context_type = CONTEXT_TYPES.EVENT
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
    if not trace_config.correlate_flows then
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

-- CLI Functions - directly modify the main trace_config
function Tracer.trace_tracks(...)
    trace_config.tracks = {...}
    if next(trace_config.tracks) then
        print("Tracing tracks: " .. table.concat(trace_config.tracks, ", "))
    else
        print("Tracing tracks: NONE")
    end
    Tracer.clear_cache()
end

function Tracer.trace_clear()
    trace_config.tracks = {}
    trace_config.devices = {}
    trace_config.components = {}
    trace_config.chains = {}
    trace_config.verbose_level = 1
    trace_config.correlate_flows = false
    trace_config.events = false
    trace_config.params = false
    trace_config.modes = false
    trace_config.load_order = false
    Tracer.clear_cache()
    print("All tracing cleared")
end

function Tracer.trace_show()
    print("=== Trace Configuration ===")
    print("Tracks: " .. (next(trace_config.tracks) and 
        table.concat(trace_config.tracks, ", ") or "NONE"))
    print("Verbose Level: " .. trace_config.verbose_level)
    print("Flow Correlation: " .. (trace_config.correlate_flows and "ON" or "OFF"))
    print("Events: " .. (trace_config.events and "ON" or "OFF"))
    print("Params: " .. (trace_config.params and "ON" or "OFF"))
    print("Load Order: " .. (trace_config.load_order and "ON" or "OFF"))
end

function Tracer.verbose_level(level)
    if level then
        trace_config.verbose_level = level
        local level_names = {"minimal", "detailed", "full"}
        print("Verbose level: " .. level .. " (" .. (level_names[level] or "unknown") .. ")")
    else
        print("Current verbose level: " .. trace_config.verbose_level)
        print("Levels: 1=minimal, 2=detailed, 3=full")
    end
end

function Tracer.trace_flows(enabled)
    if enabled == nil then enabled = true end
    trace_config.correlate_flows = enabled
    print("Flow correlation: " .. (enabled and "ON" or "OFF"))
end

function Tracer.trace_events(enabled)
    if enabled == nil then enabled = true end
    trace_config.events = enabled
    print("Event tracing: " .. (enabled and "ON" or "OFF"))
end

function Tracer.trace_params(enabled)
    if enabled == nil then enabled = true end
    trace_config.params = enabled
    print("Parameter tracing: " .. (enabled and "ON" or "OFF"))
end

function Tracer.trace_load_order(enabled)
    if enabled == nil then enabled = true end
    trace_config.load_order = enabled
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
    print("  trace_load_order(true)   -- trace component loading")
    print("")
    print("Utility:")
    print("  trace_help()             -- show this help")
end

return Tracer
