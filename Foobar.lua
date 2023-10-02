-- TO DOs:
-- Sequencers not saving patterns and loading time divisions
-- Utility functions of MidiGrid like get_bounds should reference self rather than inputs.
-- Re-architect use of MidiGrid to allow for sub-grids. functions like get bounds, index of etc can reference themselves
-- App.chords are hard coded to run on Channel 14 with scale selection set to CC 21 in unipolar mode.

script_name = 'Foobar'
path_name = script_name .. '/lib/'

local utilities = require(path_name .. 'utilities')
 App = require(path_name .. 'app')

------------------------------------------------------------------------------
function init()
	App:init()
end -- end Init

function enc(e, d) --------------- enc() is automatically called by norns
	App:handle_enc(e,d)
end

function key(k, z) ------------------ key() is automatically called by norns
	App:handle_key(k,z)
end

function redraw_clock() ----- a clock that draws space
	while true do ------------- "while true do" means "do this forever"
		clock.sleep(1 / 15) ------- pause for a fifteenth of a second (aka 15fps)
		if screen_dirty then ---- only if something changed
			redraw() -------------- redraw space
			screen_dirty = false -- and everything is clean again
		end
	end
end

fonts = {
	{name = '04B_03', face = 1, size = 8},
	{name = 'ALEPH', face = 2, size = 8},
	{name = 'tom-thumb', face = 25, size = 6},
	{name = 'creep', face = 26, size = 16},
	{name = 'ctrld', face = 27, size = 10},
	{name = 'ctrld', face = 28, size = 10},
	{name = 'ctrld', face = 29, size = 13},
	{name = 'ctrld', face = 30, size = 13},
	{name = 'ctrld', face = 31, size = 13},
	{name = 'ctrld', face = 32, size = 13},
	{name = 'ctrld', face = 33, size = 16},
	{name = 'ctrld', face = 34, size = 16},
	{name = 'ctrld', face = 35, size = 16},
	{name = 'ctrld', face = 36, size = 16},
	{name = 'scientifica', face = 37, size = 11},
	{name = 'scientifica', face = 38, size = 11},
	{name = 'scientifica', face = 39, size = 11},
	{name = 'ter', face = 40, size = 12},
	{name = 'ter', face = 41, size = 12},
	{name = 'ter', face = 42, size = 14},
	{name = 'ter', face = 43, size = 14},
	{name = 'ter', face = 44, size = 14},
	{name = 'ter', face = 45, size = 16},
	{name = 'ter', face = 46, size = 16},
	{name = 'ter', face = 47, size = 16},
	{name = 'ter', face = 48, size = 18},
	{name = 'ter', face = 49, size = 18},
	{name = 'ter', face = 50, size = 20},
	{name = 'ter', face = 51, size = 20},
	{name = 'ter', face = 52, size = 22},
	{name = 'ter', face = 53, size = 22},
	{name = 'ter', face = 54, size = 24},
	{name = 'ter', face = 55, size = 24},
	{name = 'ter', face = 56, size = 28},
	{name = 'ter', face = 57, size = 28},
	{name = 'ter', face = 58, size = 32},
	{name = 'ter', face = 59, size = 32},
	{name = 'unscii', face = 60, size = 16},
	{name = 'unscii', face = 61, size = 16},
	{name = 'unscii', face = 62, size = 8},
	{name = 'unscii', face = 63, size = 8},
	{name = 'unscii', face = 64, size = 8},
	{name = 'unscii', face = 65, size = 8},
	{name = 'unscii', face = 66, size = 16},
	{name = 'unscii', face = 67, size = 8}
}
font_select = 1

function redraw() -------------- redraw() is automatically called by norns
	local font = fonts[font_select]
	screen.clear() --------------- clear space
	screen.aa(1) ----------------- enable anti-aliasing
	screen.font_face(font.face)
	screen.font_size(font.size)
	screen.level(15) ------------- max
end

function r() ----------------------------- execute r() in the repl to quickly rerun this script
	utilities.unrequire(path_name .. 'app')
	utilities.unrequire(path_name .. 'track')
	utilities.unrequire(path_name .. 'trackcomponent')
	utilities.unrequire(path_name .. 'input')
	utilities.unrequire(path_name .. 'output')
	utilities.unrequire(path_name .. 'grid')
	utilities.unrequire(path_name .. 'mode')
	utilities.unrequire(path_name .. 'modecomponent')
	utilities.unrequire(path_name .. 'modes/mutegrid')
	utilities.unrequire(path_name .. 'modes/allclips')
	utilities.unrequire(path_name .. 'modes/scalegrid')
	utilities.unrequire(path_name .. 'modes/seqgrid')
	utilities.unrequire(path_name .. 'modes/seqclip')
	utilities.unrequire(path_name .. 'modes/scalegrid')
	utilities.unrequire(path_name .. 'seq')
	utilities.unrequire(path_name .. 'mute')
	utilities.unrequire(path_name .. 'scale')
	utilities.unrequire(path_name .. 'musicutil-extended')
	utilities.unrequire(path_name .. 'utilities')
	norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
	-- norns.script.load('/home/we/dust/code/Foobar/Foobar.lua')
end

function cleanup() --------------- cleanup() is automatically called on script close
	clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end