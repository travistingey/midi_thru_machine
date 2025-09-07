-- trace_cli.lua - Command line interface for tracing system
local Tracer = require('Foobar/lib/utilities/tracer')
local flags = require('Foobar/lib/utilities/flags')

-- Global CLI functions for easy access from Norns REPL

-- Core functions
function trace_tracks(...)
    Tracer.trace_tracks(...)
end

function trace_clear()
    Tracer.trace_clear()
end

function trace_show()
    Tracer.trace_show()
end

function trace_verbose(level)
    Tracer.verbose_level(level)
end

function trace_flow(enabled)
    Tracer.trace_flows(enabled)
end

function trace_events(enabled)
    Tracer.trace_events(enabled)
end

function trace_params(enabled)
    Tracer.trace_params(enabled)
end

function trace_help()
    Tracer.trace_help()
end

return {
    Tracer = Tracer
}