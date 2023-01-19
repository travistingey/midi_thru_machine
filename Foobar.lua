-- TO DOs:
-- Make multimode sequencer
-- Manage global variables
-- Turn Mutes, Presets and OG_Seq into proper objects and remove from init
-- CLEANUP: Utility functions of MidiGrid like get_bounds should reference self rather than inputs.

local path_name = 'Foobar/lib/'
MidiGrid = require(path_name .. 'midigrid')
Seq = require(path_name .. 'seq')
musicutil = require('musicutil')
util = require('util')

Input = {{},{}}
Output= {{},{},{},{}}

rainbow_off = {5,60,9,61,13,17,21,25,33,41,45,49,52,54,57,59}
rainbow_on = {7,62,11,63,15,19,23,27,35,43,47,51,54,56,59,61}

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
	
---------------------------------------

function set_scale(i,d)
	o = o or 0
	scale_name = musicutil.SCALES[i].name
	scale = musicutil.generate_scale(0,scale_name,5)
	crow.input[d].mode('scale',scale)
end

-------------------

function init()

	include(path_name .. 'inc/settings')
	include(path_name .. 'inc/strategies')
	
	Input[1] = {note = 0, octave = 0, volts = 0, index = 1}
	Input[2] = {note = 0, octave = 0, volts = 0, index = 1}
	
	Output[1] = {}
	Output[2] = {}
	Output[3] = {}
	Output[4] = {}
	
    crow.input[1].scale = function(s)
		Input[1] = s
	end
	
	crow.input[2].scale = function(s)
		Input[2] = s
	end

    -- Variables
	set_scale(1,1)
	set_scale(1,2)
	scale_one = 1
	scale_two = 1
    scale_root = 0
	current_bank = 1
	current_mode = 1

	message = ''
	screen_dirty = true
	redraw_clock_id = clock.run(redraw_clock)
	
	-- Devices
	
	g = MidiGrid:new({event = grid_event, channel = 3})
	seq_1 = Seq:new({
	    grid = g,
	    actions = 8,
		div = 96,
		length = 4,
	    action = function(i)
			print('load preset ' .. i)
	        Preset.load(i)
	    end
	})
	seq_2 = Seq:new({
	    grid = g,
	    actions = 8,
		length = 1,
	    action = function(i)

	    end
	})
	
	seq_3 = Seq:new({
	    grid = g,
	    actions = 8,
		length = 5,
	    action = function(i)

	    end
	})
	
	seq_4 = Seq:new({
	    grid = g,
	    actions = 8,
	    action = function(i)
	    end
	})

	transport = midi.connect(1)
	midi_out = midi.connect(2)


	---- DATA STRUCTURE ------------------------------
	-- I'll keep shimming stuff into these tables until it makes sense
	Mute = {
		grid_start = {x = 1, y = 1},
		grid_end = {x = 4, y = 4},
		state = {},
		transport = handle_mute_transport,
		grid = handle_mute_grid,
		bounds = MidiGrid.get_bounds({x = 1, y = 1}, {x = 4, y = 4}),
		set_grid = function ()
            for i, state in pairs(Mute.state) do
                local x = drum_map[i].x
                local y = drum_map[i].y

				if state then
                    g.led[x][y] = rainbow_off[Preset.select]
                else
                    g.led[x][y] = 0
                end
            end
        end
	}

	Preset = {
		grid_start = {x = 5, y = 4},
		grid_end = {x = 8, y = 1},
		select = 1,
		bank = {},
		transport = handle_preset_transport,
		grid = handle_preset_grid,
		bounds = MidiGrid.get_bounds({x = 5, y = 4}, {x = 8, y = 1}),
		set_grid = function()
		    local current  = MidiGrid.index_to_grid(Preset.select,Preset.grid_start,Preset.grid_end)
			for px = math.min(Preset.grid_start.x,Preset.grid_end.x), math.max(Preset.grid_start.x,Preset.grid_end.x) do
				for py = math.min(Preset.grid_start.y,Preset.grid_end.y), math.max(Preset.grid_start.y,Preset.grid_end.y) do
					if(current.x == px and current.y == py) then
						g.led[px][py] = rainbow_off[Preset.select]
					else
						g.led[px][py] = {20,20,20}
					end
					
				end 
			end
		end,
		load = function (i)
        	Preset.select = i
			local bank = 'bank_' .. i .. '_'
           
            local pattern = params:get( bank .. 'drum_pattern')
            local scale_one = params:get( bank .. 'scale_one')
            local scale_two = params:get(bank .. 'scale_two')
        
        	transport:program_change(pattern - 1,10)
        	set_scale(scale_one,1)
        	set_scale(scale_two,2)
        	
			local pset = Preset.bank[Preset.select]
			if (pset) then
				for k, v in pairs(pset) do
					local target = drum_map[k]
					Mute.state[k] = pset[k]
					g.toggled[target.x][target.y] = pset[k]

					if pset[k] then
						g.led[target.x][target.y] = rainbow_off[Preset.select]
					else
						g.led[target.x][target.y] = 0
					end
				end
			else
				print('No Preset Saved')
				for k, v in pairs(drum_map) do
					local target = v
					Mute.state[k] = false
					g.toggled[target.x][target.y] = false
					g.led[target.x][target.y] = 0
				end
			end
			
			Preset:set_grid()
		end,
        save = function (i)
        	local current_bank = 'bank_' .. Preset.select .. '_'
            local bank = 'bank_' .. i .. '_'
            local pattern = params:get( current_bank .. 'drum_pattern')
            
            scale_root = params:get( current_bank .. 'scale_root')
            scale_one = params:get( current_bank .. 'scale_one')
            scale_two = params:get( current_bank .. 'scale_two')
            
            params:set( bank .. 'drum_pattern', pattern )
            params:set( bank .. 'scale_root', scale_root )
            params:set( bank .. 'scale_one', scale_one )
            params:set( bank .. 'scale_two', scale_two )
			
			Preset.bank[i] = {}
			
			for k, v in pairs(drum_map) do
				Preset.bank[i][k] = (Mute.state[k] == true)
			end
			
			g.toggled[9][1] = false
			g.led[9][1] = 0
        end
	}
    
    Modes = {seq_1,seq_2,seq_3,seq_4}
    Modes[1].display = true

    Mute.set_grid()
    Preset.load(1)
    
	-- Transport Event Handler for incoming MIDI notes from the Beatstep Pro.
	transport.event = function(msg)
		local data = midi.to_msg(msg)
		
		if (data.type == 'clock' or data.type == 'start' or data.type == 'stop' or
			data.type == 'continue') then midi_out:send(data) end

		-- clock events
			
		    Modes[1]:transport_event(data)
			Modes[2]:transport_event(data)
			Modes[3]:transport_event(data)
			Modes[4]:transport_event(data)
    
		-- note on/off events
		Mute.transport(data)
		
		-- Process Outputs
		if (data.ch == 10) then
		    
		    for i = 1,4 do
		        if Output[i].trigger == data.note then
		            print('output trigger, line 206')
		        end
		    end
		    
			if drum_map[data.note].output then
				for i=1, #drum_map[data.note].output do
				    
					local output = drum_map[data.note].output[i]
					
					if output.type == 'crow_voct' and data.type == 'note_on' then
						local root = scale_root * 1/12
						crow.output[output.out].volts = Input[output.input].volts + root
					elseif output.type == 'crow_gate' then
						if (data.type == 'note_on') then
							crow.output[output.out].volts = 5
						elseif(data.type == 'note_off') then
							crow.output[output.out].volts = 0
						end
					end
				end
			else
				if(drum_map[data.note].state) then
					midi_out:send(data)
				elseif(drum_map[data.note].state == false) then
				end
			end
		end

		g:redraw()
	end
end -- end Init

function play_note(note, vel, ch, duration)
	clock.run(function()
		midi_out:note_on(note, vel, ch)
		drum_map[note].state = true
		clock.sleep(duration)
		midi_out:note_off(note, 0, ch)
		drum_map[note].state = false
	end)
end

--[[ SAVE THIS STRUCTURE FOR A LATER REFACTOR -----------

function handle_grid(s, data)
	local x = data.x
	local y = data.y
	
	local index = MidiGrid.grid_to_index({x=x,y=y},Seq.grid_start,Seq.grid_end)
	
	if (index ~= false and data.state) then
	
		--> Valid pad is pressed 
	
	end
end

]]

function handle_mute_transport(data)
	-- react only to drum pads
	if data.ch == 10 and drum_map[data.note] then
		local target = drum_map[data.note]

		if (not Mute.state[data.note]) then
			drum_map[data.note].state = true
			
			-- Mute is off
			if data.type == 'note_on' then
				g.led[target.x][target.y] = 3 -- note_on unmuted.
			elseif data.type == 'note_off' then
				g.led[target.x][target.y] = 0 -- note_on unmuted.
			end
		else
			-- Mute is on
			drum_map[data.note].state = false

			midi_out:note_off(data.note, 64, 10)
			if data.type == 'note_on' then
				g.led[target.x][target.y] = rainbow_on[Preset.select] -- note_on muted.
				data.type = 'note_off'
			elseif data.type == 'note_off' then
				g.led[target.x][target.y] = rainbow_off[Preset.select] -- note_off muted.
			end
		end
	end
end


-- MidiGrid Event Handler
-- Event triggered for every pad up and down event — TRUE state is a pad up event, FALSE state is a pad up event.
-- param s = self, MidiGrid instance
-- param data = { x = 1-9, y = 1-9, state = boolean }
function grid_event(s, data)
	handle_function_grid(s, data) -- Toggles alt button state
	
	seq_1:grid_event(data)
	
	Mute.grid(s, data) -- Sets display of mute buttons
	Preset.grid(s, data) -- Manages loading and saving of mute states
	g:redraw()
end

-- The Alt button is the grid pad used to access secondary functions. 
-- Based on the toggle state, tapping Alt will toggle on or off
-- Methods using Alt check if the toggle state is true and should reset toggle state to false after event completes
function handle_function_grid(s, data)
	local x = data.x
	local y = data.y
	local alt = s.toggled[9][1]

	-- Alt button
	if x == 9 and y == 1 then
		if(s.toggled[x][y])then
			s.led[9][1] = {3, true}
		else
			s.led[9][1] = 0
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
			g.toggled[9][1] = false
			g.led[9][1] = 0
		elseif bank_select ~= current_bank then
			current_bank = bank_select
            Preset:set_grid()
            Mute:set_grid()
            
			for i = 2, 8 do			
				s.led[9][i] = 0
			end

			s.led[9][y] = 1
			params:set('drum_bank', current_bank)
		end
	end

	-- Mode Select
	if x > 4 and y == 9 and data.state then
		current_mode = x - 4
		print('Current Mode ' .. current_mode)
		Modes[current_mode].display = true
		Modes[current_mode]:set_grid()
		
		for i = 5, 8 do 
			if i == x then
				s.led[i][9] = 3
			else
			    Modes[current_mode].display = false
				s.led[i][9] = 0
			end
		end
	end
end


-- Mute are used to prevent incoming MIDI notes from passing through.
-- Based on toggle state
function handle_mute_grid(s, data)
	local x = data.x
	local y = data.y
	local alt = g.toggled[9][1]

	if data.state and MidiGrid.in_bounds(data, Mute.bounds) then

		if alt then 
			g.toggled[9][1] = false
			print('alt' .. g.toggled[9][1])
		else
			local index = grid_map[x][y].note
			Mute.state[index] = s.toggled[x][y]

			if Mute.state[index] then 
				g.led[x][y] = rainbow_off[Preset.select]
			else
				g.led[x][y] = 0
			end
		end
	end
end

-- Preset are used to store different combination of mute settings, stored as a 2D table
-- Ony one preset in a bank is active at a time.
-- Pressing pad will load preset. Pressing alt + pad will save current mutes as a preset
function handle_preset_grid(s, data)
	local x = data.x
	local y = data.y
	local index = MidiGrid.grid_to_index({x = x, y = y}, Preset.grid_start, Preset.grid_end)
	local alt = s.toggled[9][1]

	if (index ~= false and data.state) then

		if alt then
			-- Save Preset
			print('Saved Preset ' .. Preset.select .. ' ' .. x .. ',' .. y)
            Preset.save( index )
		else
			-- Load Preset
			print('Load Preset ' .. Preset.select .. ' ' .. x .. ',' .. y)
			Preset.select = index
			Preset.load( Preset.select )
		end

	end
end

function enc(e, d) --------------- enc() is automatically called by norns
    local bank = 'bank_' .. Preset.select .. '_'
   
	if e == 1 then
	    scale_root = util.clamp(scale_root + d,-11,11)
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

function redraw() -------------- redraw() is automatically called by norns
	screen.clear() --------------- clear space
	screen.aa(1) ----------------- enable anti-aliasing
	screen.font_face(1) ---------- set the font face to "04B_03"
	screen.font_size(8) ---------- set the size to 8
	screen.level(15) ------------- max
	screen.move(2,10)
	screen.text(musicutil.note_num_to_name(scale_root, false) .. ' ' .. musicutil.SCALES[scale_one].name )
	screen.move(2,20)
	screen.text(musicutil.note_num_to_name(scale_root, false) .. ' ' .. musicutil.SCALES[scale_two].name )

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

function r() ----------------------------- execute r() in the repl to quickly rerun this script
	unrequire(path_name .. 'midigrid')
	unrequire(path_name .. 'seq')
	norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
	clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end