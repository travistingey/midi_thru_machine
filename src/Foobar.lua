-- Just remember you're doing
-- as good as you can today.
-- There are no stakes and
-- it's just for fun. ^_^


script_name = 'Foobar'
path_name = script_name .. '/lib/'

local utilities = require(path_name .. 'utilities')
App = require(path_name .. 'app')

print('\n============' .. script_name .. '============')
print('When things blow up, manually reload using: norns.script.load("/home/we/dust/code/Foobar/Foobar.lua")\n')
------------------------------------------------------------------------------
function init()
	App:init()
	-- Start UI redraw metro and watchdog
	start_redraw_metro()
	start_watchdog_metro()
end -- end Init

function enc(e, d) --------------- enc() is automatically called by norns
	App:handle_enc(e,d)
end

function key(k, z) ------------------ key() is automatically called by norns
	App:handle_key(k,z)
end

-- UI redraw and watchdog
local ui_redraw_metro = nil
local ui_watchdog_metro = nil

function start_redraw_metro()
	if ui_redraw_metro then
		ui_redraw_metro:stop()
		ui_redraw_metro = nil
	end

	ui_redraw_metro = metro.init()
	ui_redraw_metro.time = 1 / 24
	ui_redraw_metro.count = -1 -- repeat indefinitely
	ui_redraw_metro.event = function(stage)
		if App.screen_dirty then
			redraw()
			App.screen_dirty = false
		end
		-- Update heartbeat each tick so watchdog knows UI loop is alive
		if App and App.ui_last_redraw then
			App:ui_heartbeat()
		end
	end
	ui_redraw_metro:start()
end

function start_watchdog_metro()
	if ui_watchdog_metro then
		ui_watchdog_metro:stop()
		ui_watchdog_metro = nil
	end

	ui_watchdog_metro = metro.init()
	ui_watchdog_metro.time = 1.0 -- check once per second
	ui_watchdog_metro.count = -1
	ui_watchdog_metro.event = function(stage)
		local now = (util and util.time and util.time()) or os.time()
		local last = (App and App.ui_last_redraw) or 0
		-- If no redraw activity for > 2.5s, restart the redraw metro
		if (now - last) > 2.5 then
			print('[ui] redraw stalled, restarting metro')
			start_redraw_metro()
			App.screen_dirty = true
			App:ui_heartbeat()
		end
	end
	ui_watchdog_metro:start()
end

function redraw() -------------- redraw() is automatically called by norns
	App:draw()
	screen.update()
	-- Mark successful redraw for watchdog heartbeat
	if App and App.ui_last_redraw then
		App:ui_heartbeat()
	end
end

function test() 
	-- Define bit flag constants
	local BLINK       = 1          -- 0000001
	local VALUE       = 1 << 1     -- 0000010
	local INSIDE_LOOP = 1 << 2     -- 0000100
	local LOOP_END    = 1 << 3     -- 0001000
	local STEP        = 1 << 4     -- 0010000
	local SELECTED    = 1 << 5     -- 0100000
	local ALT         = 1 << 6     -- 1000000

	-- ALL represents the union of all flags
	local ALL = BLINK | VALUE | INSIDE_LOOP | LOOP_END | STEP | SELECTED | ALT

	-- Helper function to convert a number to a binary string (7-bit representation)
	local function to_binary(n)
	local t = {}
	for i = 6, 0, -1 do
		local bit = (n >> i) & 1
		table.insert(t, tostring(bit))
	end
	return table.concat(t)
	end

	-- Example table of conditions that mirror our UI color mapping.
	-- Each condition is defined as the mask that is expected.
	local conditions = {
		{ name = "Rainbow On", mask = BLINK | SELECTED | INSIDE_LOOP | VALUE },
		{ name = "Rainbow Off", mask = SELECTED | VALUE | INSIDE_LOOP },
		{ name = "Default with STEP", mask = STEP | VALUE },
		{ name = "Simple VALUE", mask = VALUE }
	}

	-- Now iterate through each test state and condition, computing the extra flags.
	print("Testing flag combinations for potential overlaps:")
	print("---------------------------------------------------")
	for _, state in ipairs(conditions) do
		local extra = state.mask ~ ALL
		print(string.format("For %s (flags: %s): extra %s", state.name, to_binary(state.mask), to_binary(extra)))

	for _, cond in ipairs(conditions) do
		print(string.format("  Condition '%s' flags %s : %s",
			cond.name, to_binary(cond.mask), to_binary(extra & cond.mask)))
	end

	print("")
	end
end

function r()
	for script,value in pairs(package.loaded) do		
		if util.string_starts(script, script_name) then
			utilities.unrequire(script)
		end
	end
	norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
	-- norns.script.load('/home/we/dust/code/Foobar/Foobar.lua')
end

function cleanup() --------------- cleanup() is automatically called on script close
	-- Stop UI metros
	if ui_redraw_metro then
		ui_redraw_metro:stop()
		ui_redraw_metro = nil
	end
	if ui_watchdog_metro then
		ui_watchdog_metro:stop()
		ui_watchdog_metro = nil
	end
	App:cleanup() -- clean up app-specific resources
end
