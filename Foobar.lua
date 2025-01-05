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
	params:default()
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
	clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end