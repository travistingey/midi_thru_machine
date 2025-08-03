-- lib/utilities/diagnostics.lua
local flags = require("Foobar/lib/utilities/feature_flags")

-- global load counter
local load_counter = 0

local M = {}

function M.next_load_id()
	load_counter = load_counter + 1
	return load_counter
end

-- Component/Track logger
function M.log(fmt, ...)
	print(string.format(fmt, ...))
end

function M.table_line(tbl)
	if type(tbl) ~= "table" then
		return tbl
	end
	local delimiter = ":"
	local parts = {}

	for k, v in pairs(tbl) do
		table.insert(parts, tostring(k) .. delimiter .. tostring(v))
	end
	return table.concat(parts, "\t")
end

-- One-shot load-order print
function M.trace_load(fmt, ...)
	if not flags.get('load_trace') then
		return
	end
	local id = M.next_load_id()
	print(string.format("[LOAD:%02d] %s", id, string.format(fmt, ...)))
end

return M
