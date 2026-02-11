-- Minimal NDJSON logger for debug instrumentation.
-- On Norns: writes to project root debug.log (e.g. /home/we/dust/code/Foobar/debug.log).
-- On Mac/Cursor: writes to workspace .cursor/debug.log for agent to read.
-- Usage: AgentDebugLog.log(message, data, hypothesisId, location)
local AgentDebugLog = {}
local function resolve_log_path()
	local info = debug.getinfo(1, 'S')
	local src = info and info.source and info.source:match('^@(.+)$')
	if src and src:find('dust') then
		-- Norns: e.g. /home/we/dust/code/Foobar/lib/utilities/agent_debug_log.lua -> .../Foobar/debug.log
		local root = src:gsub('/lib/utilities/.*$', ''):gsub('/lib$', '')
		return (root and #root > 0) and (root .. '/debug.log') or '/tmp/foobar_debug.log'
	end
	return '/Users/ttingey/Sites/_Personal/midi_thru_machine/.cursor/debug.log'
end
local LOG_PATH = resolve_log_path()

local function esc(s)
	if s == nil then return 'null' end
	if type(s) == 'number' then return tostring(s) end
	return '"' .. tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
end

function AgentDebugLog.log(message, data, hypothesisId, location)
	local ts = (os and os.time and os.time() or 0) * 1000
	local data_parts = {}
	if type(data) == 'table' then
		for k, v in pairs(data) do
			table.insert(data_parts, esc(k) .. ':' .. esc(v))
		end
	end
	local line = '{"message":'
		.. esc(message)
		.. ',"data":{'
		.. table.concat(data_parts, ',')
		.. '},"hypothesisId":'
		.. esc(hypothesisId or '')
		.. ',"location":'
		.. esc(location or '')
		.. ',"timestamp":'
		.. ts
		.. '}\n'
	pcall(function()
		local f = io.open(LOG_PATH, 'a')
		if f then
			f:write(line)
			f:close()
		end
	end)
end

return AgentDebugLog
