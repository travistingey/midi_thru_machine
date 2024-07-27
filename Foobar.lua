-- TO DOs:
-- Sequencers not saving patterns and loading time divisions
-- Utility functions of MidiGrid like get_bounds should reference self rather than inputs.
-- Re-architect use of MidiGrid to allow for sub-grids. functions like get bounds, index of etc can reference themselves
-- App.chords are hard coded to run on Channel 14 with scale selection set to CC 21 in unipolar mode.

script_name = 'Foobar'
path_name = script_name .. '/lib/'

local utilities = require(path_name .. 'utilities')
App = require(path_name .. 'app')


function transform(x)
	-- Polynomial function
	local  y =  1.47169e-4 * x^3 - 0.03408 * x^2 + 2.72011 * x - 83.71316
	
	-- Define original and target ranges
	local a, b = -96, 12  -- Original dB range
	local c, d = -16, 125.5   -- Target range of 0 to 127, adjusted so the floored values are within 0 to 127 excactly
	-- Scale and offset the polynomial output
	y = math.floor(((y - a) / (b - a)) * (d - c) + c)
  
	return y
  end



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

function r() ----------------------------- execute r() in the repl to quickly rerun this script

	--App:panic()
	
	utilities.unrequire(path_name .. 'app')
	utilities.unrequire(path_name .. 'track')
	utilities.unrequire(path_name .. 'grid')
	utilities.unrequire(path_name .. 'mode')

	utilities.unrequire(path_name .. 'trackcomponent')
	utilities.unrequire(path_name .. 'components/input')
	utilities.unrequire(path_name .. 'components/seq')
	utilities.unrequire(path_name .. 'components/mute')
	utilities.unrequire(path_name .. 'components/scale')
	utilities.unrequire(path_name .. 'components/output')

	utilities.unrequire(path_name .. 'modecomponent')
	utilities.unrequire(path_name .. 'modes/mutegrid')
	utilities.unrequire(path_name .. 'modes/allclips')
	utilities.unrequire(path_name .. 'modes/scalegrid')
	utilities.unrequire(path_name .. 'modes/seqgrid')
	utilities.unrequire(path_name .. 'modes/seqclip')
	utilities.unrequire(path_name .. 'modes/scalegrid')
	utilities.unrequire(path_name .. 'modes/notegrid')
	utilities.unrequire(path_name .. 'modes/presetgrid')
	
	utilities.unrequire(path_name .. 'musicutil-extended')
	utilities.unrequire(path_name .. 'utilities')
	utilities.unrequire(path_name .. 'bitwise')
	norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
	-- norns.script.load('/home/we/dust/code/Foobar/Foobar.lua')
end

function cleanup() --------------- cleanup() is automatically called on script close
	clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end