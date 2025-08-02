-- lib/utilities/diagnostics.lua
local flags = require('Foobar/lib/utilities/feature_flags')

-- global load counter
local load_counter = 0

local M = {}

function M.next_load_id()
  load_counter = load_counter + 1
  return load_counter
end

-- Component/Track logger
function M.log(scope, name, fmt, ...)
  if not flags.verbose then return end
  

  local tag = string.format("[%s:%s] ",'T'.. scope.id, (scope.name or '?'))
  print(tag .. string.format(fmt, ...))
end

-- One-shot load-order print
function M.trace_load(scope, name, extra)
  if not flags.load_trace then return end
  local id = M.next_load_id()
  print(string.format("[LOAD:%02d] %s %s%s",
        id, scope, name or "unnamed", extra and (" " .. extra) or ""))
end

return M