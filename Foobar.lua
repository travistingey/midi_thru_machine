-- Just remeber you're doing as good as you can today. There's no stakes and it's fun. :)


script_name = 'Foobar'
path_name = script_name .. '/lib/'

local utilities = require(path_name .. 'utilities')
App = require(path_name .. 'app')

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
	utilities.unrequire(path_name .. 'launchcontrol')
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
	utilities.unrequire(path_name .. 'modes/presetseq')
	
	utilities.unrequire(path_name .. 'musicutil-extended')
	utilities.unrequire(path_name .. 'utilities')
	utilities.unrequire(path_name .. 'bitwise')
	norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
	-- norns.script.load('/home/we/dust/code/Foobar/Foobar.lua')
end

function cleanup() --------------- cleanup() is automatically called on script close
	clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end