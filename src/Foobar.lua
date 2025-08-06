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
	redraw_clock_id = clock.run(redraw_clock)
end -- end Init

function enc(e, d) --------------- enc() is automatically called by norns
	App:handle_enc(e,d)
end

function key(k, z) ------------------ key() is automatically called by norns
	App:handle_key(k,z)
end

function redraw_clock() ----- a clock that draws space
	while true do ------------- "while true do" means "do this forever"
		clock.sleep(1 / 24) ------- pause for a fifteenth of a second (aka 15fps)
		if App.screen_dirty then ---- only if something changed
			redraw() -------------- redraw space
			App.screen_dirty = false -- and everything is clean again
		end
	end
end

function redraw() -------------- redraw() is automatically called by norns
	App:draw()
	screen.update()
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
	clock.cancel(redraw_clock_id) -- melt our clock via the id we noted
	App:cleanup() -- clean up app-specific resources
end
