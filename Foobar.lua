-- HTTPS://NOR.THE-RN.INFO
-- NORNSILERPLATE
-- >> k1: exit
-- >> k2:
-- >> k3:
-- >> e1:
-- >> e2:
-- >> e3:
local path_name = 'Foobar/lib/'
MidiGrid = require(path_name .. 'midigrid')
musicutil = require('musicutil')
util = require('util')

------------------------------------------------------------------------------------------------------------------------------


function init()
	include(path_name .. 'inc/settings')
	Input = {{},{}}
	
	scale_select = 1
	scale_name = musicutil.SCALES[scale_select]
	scale = musicutil.generate_scale(0,scale_name,1)
	
	crow.input[1].mode('scale',scale)
	crow.input[1].scale = function(s)
		Input[1] = s
	end

	crow.input[2].mode('scale',scale)
	crow.input[2].scale = function(s)
		Input[2] = s
	end

	rainbow_off = {7,11,15,23,39,47,51,55}
  	rainbow_on = {5,9,13,21,37,45,49,53}
	
	message = "Foobar"
	screen_dirty = true
	redraw_clock_id = clock.run(redraw_clock)

	transport = midi.connect(1)
	
	
	g = MidiGrid:new({event = grid_event})

	midi_out = midi.connect(3)
	
	input_one = 1
	
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

	---- DATA STRUCTURE ------------------------------
	-- I'll keep shimming stuff into these tables until it makes sense
	Mute = {
		grid_start = {x = 1, y = 1},
		grid_end = {x = 4, y = 4},
		state = {},
		transport = handle_mute_transport,
		grid = handle_mute_grid,
		bounds = MidiGrid.get_bounds({x = 1, y = 1}, {x = 4, y = 4})
	}

	Preset = {
		grid_start = {x = 5, y = 4},
		grid_end = {x = 8, y = 1},
		select = 1,
		bank = {},
		transport = handle_preset_transport,
		grid = handle_preset_grid,
		bounds = MidiGrid.get_bounds({x = 5, y = 4}, {x = 8, y = 1})
	}

	Seq = {
		grid_start = {x = 1, y = 8},
		grid_end = {x = 8, y = 5},
		div = 12,
		transport = handle_seq_transport,
		grid = handle_seq_grid,
		select_note = 36,
		select_step = 1,
		select_action = 1,
		map = {},
		value = {},
		length = 32,
		tick = 1,
		step = 1,
		actions = {
			[0] = function() end,
			[1] = seq_action,
			[2] = function() end,
			[3] = function() end,
			[4] = function() end,
			[5] = function() end,
			[6] = function() end,
			[7] = function() end,
			[8] = function() end
	
		}
	}

	for i = 1, Seq.length do
		Seq.map[i] = MidiGrid.index_to_grid(i, Seq.grid_start, Seq.grid_end)
	end

	-- Transport Event Handler for incoming midi notes from the Beatstep Pro.
	transport.event = function(msg)
		local data = midi.to_msg(msg)
		if(data.type ~= 'clock') then tab.print(data) end
		
		if (data.type == 'clock' or data.type == 'start' or data.type == 'stop' or
			data.type == 'continue') then midi_out:send(data) end

		-- clock events
		Seq.transport(data)

		-- note on/off events
		Mute.transport(data)
		
		-- Process Outputs
		if (data.ch == 10) then
			if drum_map[data.note].output then
				for i=1, #drum_map[data.note].output do
					local output = drum_map[data.note].output[i]
					if output.type == 'crow_voct' and data.type == 'note_on' then
						crow.output[output.out].volts = Input[output.input].volts
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

seq_action = function()
	clock.run(function()

		local count = 0
		local delta = 20
		local length = math.random(4)
		local b = math.random(4)
		local probability = 0

		if (math.random() > probability) then
			while count < length do
				if (not (drum_map[41].state) and not (Mute.state[41])) then
					play_note(41, (100 - delta * count), 10, 0.1)
				end
				count = count + 1
				clock.sleep(300)

			end
		end
	end)
end

function handle_seq_transport(data)
	-- Tick based sequencer running on 16th notes at 24 PPQN
	if data.type == 'clock' then
		Seq.tick = util.wrap(Seq.tick + 1, 1, Seq.div * Seq.length)
		local next_step = util.wrap(math.floor(Seq.tick / Seq.div) + 1, 1,
									Seq.length)
		local last_step = Seq.step

		-- Enter new step. c = current step, l = last step
		if next_step > last_step or next_step == 1 and last_step == Seq.length then

			local l = Seq.map[last_step]
			local c = Seq.map[next_step]

			local last_value = Seq.value[last_step] or 0
			local value = Seq.value[next_step] or 0
			
			if last_value == 0 then
				g.led[l.x][l.y] = 0
			else
				g.led[l.x][l.y] = rainbow_off[last_value]
			end
			if value == 0 then
				g.led[c.x][c.y] = 1
			else
				g.led[c.x][c.y] = rainbow_on[value]
			end

			

		end

		Seq.step = next_step
	end

	-- Note: 'Start' is called at the beginning of the sequence
	if data.type == 'start' then
		Seq.tick = 0
		Seq.step = 1
	end

	
end

function handle_seq_grid(s, data)
	local x = data.x
	local y = data.y

	local index = MidiGrid.grid_to_index({x = x, y = y}, Seq.grid_start, Seq.grid_end)
	if(x == 1 and y == 9 and data.state) then
		-- up
		Seq.select_action = util.wrap(Seq.select_action + 1, 1, #Seq.actions)
		local current = MidiGrid.index_to_grid(Seq.select_step, Seq.grid_start, Seq.grid_end)
		g.led[1][9] = rainbow_off[Seq.select_action]
		g.led[2][9] = rainbow_off[Seq.select_action]

		if Seq.value[Seq.select_step] and Seq.value[Seq.select_step] > 0 then
			Seq.value[Seq.select_step] = Seq.select_action
			g.led[current.x][current.y] = rainbow_off[Seq.select_action]
		end

		g:redraw()
	end
	if(x == 2 and y == 9 and data.state) then
		-- down
		Seq.select_action = util.wrap(Seq.select_action - 1, 1, #Seq.actions)
		local current = MidiGrid.index_to_grid(Seq.select_step, Seq.grid_start, Seq.grid_end)
		g.led[1][9] = rainbow_off[Seq.select_action]
		g.led[2][9] = rainbow_off[Seq.select_action]
		
		if Seq.value[Seq.select_step] and Seq.value[Seq.select_step] > 0 then
			Seq.value[Seq.select_step] = Seq.select_action
			g.led[current.x][current.y] = rainbow_off[Seq.select_action]
		end

		g:redraw()
	end
	
	if(x == 3 and y == 9 and data.state) then
		-- left
	end
	if(x == 4 and y == 9 and data.state) then
		-- right
	end

	if (index ~= false and data.state) then
		local value = Seq.value[index] or 0

		if value == 0 then
			-- Turn on
			Seq.note_select = index
			Seq.value[index] = Seq.select_action
			g.led[x][y] = rainbow_off[Seq.select_action]
			Seq.select_step = index
			g:redraw()
		else
			-- Turn off
			Seq.value[index] = 0
			Seq.select_step = index
			g.led[x][y] = 0
		end		
	end
	g:redraw()
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
				g.led[target.x][target.y] = 5 -- note_On muted.
				data.type = 'note_off'
			elseif data.type == 'note_off' then
				g.led[target.x][target.y] = 7 -- note_off muted.
			end
		end
	end
end

-- MidiGrid Event Handler
-- Event triggered for every pad up and down event — TRUE state is a pad up event, FALSE state is a pad up event.
-- param s = self, MidiGrid instance
-- param data = { x = 1-9, y = 1-9, state = boolean }
function grid_event(s, data)
	handle_alt_grid(s, data) -- Toggles alt button state
	Seq.grid(s, data) -- Toggles Seq actions
	Mute.grid(s, data) -- Sets display of mute buttons
	Preset.grid(s, data) -- Manages loading and saving of mute states

	g:redraw()

end

-- The Alt button is the grid pad used to access secondary functions. 
-- Based on the toggle state, tapping Alt will toggle on or off
-- Methods using Alt check if the toggle state is true and should reset toggle state to false after event completes
function handle_alt_grid(s, data)
	local x = data.x
	local y = data.y

	-- Alt button
	if x == 9 and y == 1 and s.toggled[x][y] then
		s.led[9][1] = {3, true}
	else
		s.led[9][1] = 0
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
			Seq.current = grid_map[x][y].note
			print(Seq.current)
			g.toggled[9][1] = false
		else
			local index = grid_map[x][y].note
			Mute.state[index] = s.toggled[x][y]

			if Mute.state[index] then
				g.led[x][y] = 7
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

		Preset.select = MidiGrid.grid_to_index({x = x, y = y},Preset.grid_start, Preset.grid_end)
		for px = 5, 8 do
			for py = 1, 4 do
				if px == x and py == y then
					g.led[x][y] = rainbow_on[drum_map[Seq.select_note].index]
				else
					g.led[px][py] = rainbow_off[drum_map[Seq.select_note].index]
				end
			end
		end

		if alt then
			-- Save Preset
			Preset.bank[Preset.select] = {}
			for k, v in pairs(drum_map) do
				Preset[Preset.select][k] = (Mute.state[k] == true)
			end

			print('Saved Preset ' .. Preset.select .. ' ' .. x .. ',' .. y)

			s.toggled[9][1] = false
		else
			print('Load Preset ' .. Preset.select .. ' ' .. x .. ',' .. y)
			-- Load Preset
			local pset = Preset[Preset.select]

			if (pset) then
				for k, v in pairs(pset) do
					local target = drum_map[k]
					Mute.state[k] = pset[k]
					s.toggled[target.x][target.y] = pset[k]

					if pset[k] then
						s.led[target.x][target.y] = 7
					else
						s.led[target.x][target.y] = 0
					end
				end
			else
				print('no preset')
				local foo = {}
				for k, v in pairs(drum_map) do
					foo[k] = false
					s.toggled[v.x][v.y] = false
					s.led[v.x][v.y] = 0
				end
				Preset[Preset.select] = foo
			end

		end

	end

	-- Preset Select
	if data.state and MidiGrid.in_bounds(data, Preset.bounds) then
		

	end
end

function enc(e, d) --------------- enc() is automatically called by norns
	if e == 1 then turn(e, d) end -- turn encoder 1
	if e == 2 then turn(e, d) end -- turn encoder 2
	if e == 3 then turn(e, d) end -- turn encoder 3
	screen_dirty = true ------------ something changed
end

function turn(e, d) ----------------------------- an encoder has turned
	message = "encoder " .. e .. ", delta " .. d -- build a message
end

function key(k, z) ------------------ key() is automatically called by norns
	if z == 0 then return end --------- do nothing when you release a key
	if k == 2 then press_down(2) end -- but press_down(2)
	if k == 3 then press_down(3) end -- and press_down(3)
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
	screen.move(64, 32) ---------- move the pointer to x = 64, y = 32
	screen.text_center(message) -- center our message at (64, 32)
	screen.move(64, 24)
	screen.pixel(0, 0) ----------- make a pixel at the north-western most terminus
	screen.pixel(127, 0) --------- and at the north-eastern
	screen.pixel(127, 63) -------- and at the south-eastern
	screen.pixel(0, 63) ---------- and at the south-western
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
	norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
	clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end
