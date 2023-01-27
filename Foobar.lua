-- TO DOs:
-- Make multimode sequencer
-- Manage global variables
-- Turn Mutes, Presets and OG_Seq into proper objects and remove from init
-- CLEANUP: Utility functions of MidiGrid like get_bounds should reference self rather than inputs.
script_name = 'Foobar'
path_name = script_name .. '/lib/'

MidiGrid = require(path_name .. 'midigrid')
Seq = require(path_name .. 'seq')
musicutil = require('musicutil')
util = require('util')

drum_map = {}
drum_map[36] = {x = 1, y = 1, index = 1, output = {{type='crow_voct', input = 1, out = 1},{type='crow_gate', input = 0, out = 2}}}
drum_map[37] = {x = 2, y = 1, index = 2, output = {{type='crow_voct', input = 2, out = 3},{type='crow_gate', input = 0, out = 4}} }
drum_map[38] = {x = 3, y = 1, index = 3}
drum_map[39] = {x = 4, y = 1, index = 4}
drum_map[40] = {x = 1, y = 2, index = 5}
drum_map[41] = {x = 2, y = 2, index = 6}
drum_map[42] = {x = 3, y = 2, index = 7}
drum_map[43] = {x = 4, y = 2, index = 8}
drum_map[44] = {x = 1, y = 3, index = 9}
drum_map[45] = {x = 2, y = 3, index = 10}
drum_map[46] = {x = 3, y = 3, index = 11}
drum_map[47] = {x = 4, y = 3, index = 12}
drum_map[48] = {x = 1, y = 4, index = 13}
drum_map[49] = {x = 2, y = 4, index = 14}
drum_map[50] = {x = 3, y = 4, index = 15}
drum_map[51] = {x = 4, y = 4, index = 16}

grid_map = {}
for i = 1, 16 do grid_map[i] = {} end

grid_map[1][1] = {note = 36, index = 1}
grid_map[2][1] = {note = 37, index = 2}
grid_map[3][1] = {note = 38, index = 3}
grid_map[4][1] = {note = 39, index = 4}
grid_map[1][2] = {note = 40, index = 5}
grid_map[2][2] = {note = 41, index = 6}
grid_map[3][2] = {note = 42, index = 7}
grid_map[4][2] = {note = 43, index = 8}
grid_map[1][3] = {note = 44, index = 9}
grid_map[2][3] = {note = 45, index = 10}
grid_map[3][3] = {note = 46, index = 11}
grid_map[4][3] = {note = 47, index = 12}
grid_map[1][4] = {note = 48, index = 13}
grid_map[2][4] = {note = 49, index = 14}
grid_map[3][4] = {note = 50, index = 15}
grid_map[4][4] = {note = 51, index = 16}
	
------------------------------------------------------------------------------

function set_scale(i,d)
	o = o or 0
	scale_name = musicutil.SCALES[i].name
	scale = musicutil.generate_scale(0,scale_name,5)
	crow.input[d].mode('scale',scale)
	screen_dirty = true
end

------------------------------------------------------------------------------

function set_alt(state)
	if(state) then
		g.led[9][1] = {3,true}
		g.toggled[9][1] = true
		Mode[Mode.select]:alt_event(true)
	else
		g.led[9][1] = 0
		g.toggled[9][1] = false
		Mode[Mode.select]:alt_event(false)
	end
end

function get_alt() return g.toggled[9][1] end

function init()
    
    -- Variables
    
    rainbow_on = {{127,0,0},{127,15,0},{127,45,0},{127,100,0},{75,127,0},{40,127,0},{0,127,0},{0,127,27},{0,127,127},{0,45,127},{0,0,127},{10,0,127},{27,0,127},{55,0,127},{127,0,75},{127,0,15}}
	rainbow_off = {}

	for i=1, 16 do
		rainbow_off[i] = {math.floor(rainbow_on[i][1]/4),math.floor(rainbow_on[i][2]/4),math.floor(rainbow_on[i][3]/4)}
	end
    Input = {{},{}}
    Output = {{},{},{},{}}

	Input[1] = {note = 0, octave = 0, volts = 0, index = 1}
	Input[2] = {note = 0, octave = 0, volts = 0, index = 1}
	
	

	set_scale(1,1)
	set_scale(1,2)
	
	scale_one = 1
	scale_two = 1
    scale_root = 0
    
	current_bank = 1

	message = ''
	screen_dirty = true
	redraw_clock_id = clock.run(redraw_clock)
	
	include(path_name .. 'inc/settings')
	include(path_name .. 'inc/strategies')
	include(path_name .. 'inc/mute')
	include(path_name .. 'inc/preset')
	include(path_name .. 'inc/mode')


	for i=1,4 do
		local out = 'crow_out_' .. i .. '_'
		Output[i] = {
			type = params:get(out .. 'type'),
			source = params:get(out .. 'source'),
			trigger = params:get(out .. 'trigger')
		}
	end

	-- Devices
    crow.input[1].scale = function(s)
		Input[1] = s
	end
	
	crow.input[2].scale = function(s)
		Input[2] = s
	end

	g = MidiGrid:new({event = grid_event, channel = 3})
	
	transport = midi.connect(1)
	midi_out = midi.connect(2)
		
    Mute:set_grid()
	
    
	
	-- Transport Event Handler for incoming MIDI notes from the Beatstep Pro.
	transport.event = transport_event
	params:default()
	Mode:load()
	g.led[9][9 - params:get('drum_bank')] = 3 -- Set Drum Bank
	Preset.load(1)
	g:redraw()
end -- end Init



function transport_event(msg)
	local data = midi.to_msg(msg)
	
	if (data.type == 'clock' or data.type == 'start' or data.type == 'stop' or
		data.type == 'continue') then midi_out:send(data) end

	-- clock events
	Mode[1]:transport_event(data)
	Mode[2]:transport_event(data)
	Mode[3]:transport_event(data)
	Mode[4]:transport_event(data)

	-- note on/off events
	Mute.transport_event(data)

	-- Process Outputs
	if (data.ch == 10) then
		
		for i = 1,4 do
			if Output[i].trigger == data.note then
				if(Output[i].type == 'v/oct') and data.type == 'note_on' then
					local root = scale_root * 1/12
					local volts = Input[Output[i].source].volts + root
					crow.output[i].volts = volts
				elseif(Output[i].type == 'gate')then
					if data.type == 'note_on' then
						crow.output[i].volts = 5
					elseif data.type == 'note_off' then
						crow.output[i].volts = 0
					end
				end
			end
		end
		
		if(drum_map[data.note].state) then
			midi_out:send(data)
		elseif(drum_map[data.note].state == false) then
		end
		
	end

	g:redraw()
end

-- MidiGrid Event Handler
-- Event triggered for every pad up and down event — TRUE state is a pad up event, FALSE state is a pad up event.
-- param s = self, MidiGrid instance
-- param data = { x = 1-9, y = 1-9, state = boolean }
function grid_event(s, data)
	screen:ping()
	handle_function_grid(s, data)
	
	Mode[Mode.select]:grid_event(data)
	
	Mute.grid_event(s, data) -- Sets display of mute buttons
	Preset.grid_event(s, data) -- Manages loading and saving of mute states
	g:redraw()
end

-- The Alt button is the grid pad used to access secondary functions. 
-- Based on the toggle state, tapping Alt will toggle on or off
-- Methods using Alt check if the toggle state is true and should reset toggle state to false after event completes
function handle_function_grid(s, data)
	local x = data.x
	local y = data.y
	local alt = get_alt()

	-- Alt button
	if x == 9 and y == 1 then
		if(alt)then
			set_alt(true)
		else
			set_alt(false)
		end
	end

	--Bank Select
	if x == 9 and y > 1 and data.state then

		local bank_select = 9 - y

		if(alt) then
			if bank_select == current_bank then
				print('we gonna save this PSET')
			else
				print('we gonna load this PSET')
			end
			
			set_alt(false)
			
		elseif bank_select ~= current_bank then
			current_bank = bank_select
            Preset:set_grid()
            Mute:set_grid()
            
			for i = 2, 8 do			
				s.led[9][i] = 0
			end

			s.led[9][y] = 3
			params:set('drum_bank', current_bank)
		end
	end

	Mode:grid_event(data)
end


function enc(e, d) --------------- enc() is automatically called by norns
    local bank = 'bank_' .. Preset.select .. '_'
   
	if e == 1 then
	    scale_root = util.clamp(scale_root + d,-24,24)
	end -- turn encoder 1
	
	if e == 2 then
	    scale_one = util.clamp(scale_one + d,1,41)
	    set_scale(scale_one,1)
	end -- turn encoder 2
	if e == 3 then
	    scale_two = util.clamp(scale_two + d,1,41)
	    set_scale(scale_two,2)
	end -- turn encoder 3
	
	screen_dirty = true ------------ something changed
end

function key(k, z) ------------------ key() is automatically called by norns
	if z == 0 then return end --------- do nothing when you release a key
	if k == 2 then press_down(2) end -- but press_down(2)
	if k == 3 then press_down(3)
	    message = Strategies:draw()
	    screen_dirty = true
	end -- and press_down(3)
	screen_dirty = true --------------- something changed
end

function press_down(i) ---------- a key has been pressed
	message = "press down " .. i -- build a message
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
	screen.move(2,10)
	screen.text(musicutil.note_num_to_name(scale_root, false) .. ' ' .. musicutil.SCALES[scale_one].name )
	screen.move(2,20)
	screen.text(musicutil.note_num_to_name(scale_root, false) .. ' ' .. musicutil.SCALES[scale_two].name )

	screen.move(127,10)
	screen.text_right(scale_root)

	local display = message
	local y = 40
	local l = 25 -- lines
	
	
	while (display) do
		screen.move(2,y)
		if(display:len() > l) then
			local a,b = display:sub(1,l):match('(.*)%s([%w-]*)')
			if a then
				screen.text(a)
				display = b .. display:sub(l + 1)

				
				if display:len() < l then
					y = y + 10
					screen.move(2,y)
					screen.text(display)
					break
				end
				y = y + 10
			else
				break
			end
		else
			screen.text(display)
			break
		end
	end
	
	screen.fill() ---------------- fill the termini and message at once
	screen.update() -------------- update space
	
end

------------------------------------------------------------------------------------------------------------------------------------
function removeDuplicates(arr)
	local newArray = {}
	local checkerTbl = {}
	for _, element in ipairs(arr) do
		if not checkerTbl[element] then
			checkerTbl[element] = true
			table.insert(newArray, element)
		end
	end
	return newArray
end

function unrequire(name)
	package.loaded[name] = nil
	_G[name] = nil
end

function concat_table(t1,t2)
	for i=1,#t2 do
	   t1[#t1+1] = t2[i]
	end
	return t1
 end
 
function r() ----------------------------- execute r() in the repl to quickly rerun this script
	unrequire(path_name .. 'midigrid')
	unrequire(path_name .. 'seq')
	norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
	clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end