-- TO DOs:
-- Sequencers not saving patterns and loading time divisions
-- Utility functions of MidiGrid like get_bounds should reference self rather than inputs.
-- Re-architect use of MidiGrid to allow for sub-grids. functions like get bounds, index of etc can reference themselves
-- App.chords are hard coded to run on Channel 14 with scale selection set to CC 21 in unipolar mode.

script_name = 'Foobar'
path_name = script_name .. '/lib/'

local Seq = require(path_name .. 'seq')
local Keys = require(path_name .. 'keys')

local musicutil = require(path_name .. 'musicutil-extended')
local utilities = require(path_name .. 'utilities')
 App = require(path_name .. 'app')

------------------------------------------------------------------------------
function init()
   

    

    -- Additional setup
    last_tick = 0
    tick_time = 0
    message = ''
    screen_dirty = true
    redraw_clock_id = clock.run(redraw_clock)


    -- Include additional scripts
    -- include(path_name .. 'inc/mode')
	-- include(path_name .. 'inc/settings')
    -- include(path_name .. 'inc/strategies')
    -- include(path_name .. 'inc/mute')
    -- include(path_name .. 'inc/preset')

	App:init()
	
    --[[
    -- Set up mute grid
    Mute:set_grid()
    
    
    
    -- Load default parameters
    params:default()

    -- Set Drum Bank
    App.grid.led[9][9 - params:get('drum_bank')] = 3

    -- Load preset and mode
    Preset.load(1)
    Mode:load(Mode)

    -- Redraw grid
    ]]


end -- end Init





-- Update the Input table
function update_input(s)
	
	App.crow_in[s].last_interval = App.crow_in[s].interval or 0
	App.crow_in[s].last_note = App.crow_in[s].note or 0
	App.crow_in[s].last_octave = App.crow_in[s].octave  or 0
	App.crow_in[s].last_volts = App.crow_in[s].volts  or 0
	
	crow.send('input[' .. s .. '].query()')
	
	local note = math.floor(App.crow_in[s].volts * 12)
	local octave = math.floor( note / 12 )

	App.crow_in[s].note = note
	App.crow_in[s].interval = note - octave * 12
	App.crow_in[s].octave = octave

	
	
end


----- REFACTOR
function process_drum_channel(data)
		for i = 1,4 do
			if App.crow_out[i].trigger == data.note then
				
				if(App.crow_out[i].type == 'v/oct') and data.type == 'note_on' then
					local s = App.crow_out[i].source
				    update_input(s)
					
					local volts = App.crow_in[s].volts
					
					if(#App.scale[s].intervals > 0) then
						volts = ( musicutil.snap_note_to_array(App.crow_in[s].note, App.scale[s].notes) + App.scale[s].root )  / 12
					end

					if (params:get('scale_' .. s .. '_follow') > 1 ) then
						volts = volts + (App.chord.root/12)
					end
					
					crow_note_out(i,s,volts)
					
				elseif(App.crow_out[i].type == 'interval') and data.type == 'note_on' then
					local s = App.crow_out[i].source
				    update_input(s)
				    
					local next = App.crow_in[s].last_note
					local score = math.fmod(App.crow_in[s].volts,1)
					local octave = math.floor(App.crow_in[s].volts)
					local ratio = 0.68

					local direction = 1
					local range = params:get('crow_out_' .. i .. '_range')
					local ceil = App.scale[s].root + 12 * range

					if octave > App.crow_in[s].last_octave or App.crow_in[s].last_note < App.scale[s].root then
						direction = 2
					elseif octave < App.crow_in[s].last_octave or App.crow_in[s].last_note > ceil  then
						direction = 1
					end
					
					if(App.crow_in[s].volts < 0.2)then
						next = App.scale[s].root					
					elseif score < ratio then
						if direction == 2 or direction == 0 and math.random() > 0.5 then
							-- Step up
							next = util.clamp(next + 1,App.scale[s].root,ceil)
							local count = 0
							while(1 << math.fmod(next - App.scale[s].root,12) & App.scale[s].bits == 0 and App.scale[s].bits > 0 and count < 12) do
								next = util.clamp(next + 1,0,ceil)
								count = count + 1
							end
						else
							-- Step down
							next = util.clamp(next - 1,App.scale[s].root,ceil)
							local count = 0
							while(1 << math.fmod(next - App.scale[s].root,12) & App.scale[s].bits == 0 and App.scale[s].bits > 0 and count < 12) do
								next = util.clamp(next - 1,0,ceil)
								count = count + 1
							end
						end
					else
						-- Skipwise Motion
						local interval = App.scale[s].intervals[math.random(1,#App.scale[s].intervals)]
						next = util.clamp(App.crow_in[s].last_octave * 12 + interval + App.scale[s].root,0,ceil)
					end

					App.crow_in[s].interval = next % 12
					App.crow_in[s].note = next
					App.crow_in[s].octave = math.floor(App.crow_in[s].note / 12)
					
					local volts = (App.crow_in[s].note + App.scale[s].root) /12
					
					if (params:get('scale_' .. s .. '_follow') > 1 ) then
						volts = volts + (App.chord.root/12)
					end

					crow_note_out(i,s,volts)
				elseif(App.crow_out[i].type == 'gate')then
					if data.type == 'note_on' then
						crow.output[i].volts = 5
					elseif data.type == 'note_off' then
						crow.output[i].volts = 0
					end
				end
			end
		end
		
		-- pass midi to output if mute is off
		if(not Mute.state[data.note]) then
		App.midi_out:send(data)
		end
end

function process_seq_1_channel(data)
    if EO_Learn then

	App.midi_out:send(data)
	elseif(data.type == 'note_on') then
		
		local current = App.chord[data.note % 12 + 1]
		for i = 1,2 do

			if App.scale[i].follow == 2 then
				-- Transpose
				App.scale[i].root = current.note
			elseif App.scale[i].follow == 3 then
				-- App.scale Degree
				App:shift_scale_to_note(i,current.note + 48)
			elseif App.scale[i].follow == 4 then
				-- App.chord
				set_scale(musicutil.intervals_to_bits(current.intervals),i)
				App.scale[i].root = current.note
			elseif App.scale[i].follow == 5 then
				-- Pentatonic
				local chord = musicutil.intervals_to_bits(current.intervals)
				local major = musicutil.intervals_to_bits({0,4})
				local minor = musicutil.intervals_to_bits({0,3})

				if chord & major == major then
					set_scale(661,i)
					App.scale[i].root = current.note
				elseif chord & minor == minor then
					set_scale(1193,i)
					App.scale[i].root = current.note
				else
					set_scale(1,i)
					App.scale[i].root = current.note
				end
			end
			
			screen_dirty = true
				
			if Mode.select == 3 then
				Mode[3]:set_grid()
				g:redraw()
			end
		end

		local selection = util.clamp((current.slot - 1) * 14,0,127)
	App.midi_out:cc(21,selection,14)

	end
	
	data.ch = 14
	
	if data.note ~= nil then
		local current = App.chord[data.note % 12 + 1]
		data.note = math.floor(data.note / 12) * 12 + current.note + App.chord.root
	end
	
	if data.type == 'note_on' then
	App.midi_out:note_off(App.chord.last_note,0,14)
		App.chord.last_note = data.note
	end

	local mute = params:get('chord_mute')

	if not ( Mute.state[mute] and data.type == 'note_on' ) then
	App.midi_out:send(data)
	end
end

function process_other_channels(data)
    -- pass through other channels
App.midi_out:send(data)
end






function crow_note_out(index,input,volts)
	crow.output[1].action = '{to(dyn{note = 0},dyn{slew = 0})}'
	crow.output[index].dyn.note = volts
					
	if(App.crow_in[input].last_note > App.crow_in[input].note) then
		crow.output[index].dyn.slew = params:get('crow_out_' .. index .. '_slew_down')
	else
		crow.output[index].dyn.slew = params:get('crow_out_' .. index .. '_slew_up')
	end
	
	crow.send('output[' .. index .. ']()')
	
end

function enc(e, d) --------------- enc() is automatically called by norns
	App:handle_enc(e,d)
    local bank = 'bank_' .. App.preset .. '_'
   
	if e == 1 then
		local root = params:get('chord_root')
		params:set('chord_root',root + d)
	end -- turn encoder 1
	
	if e == 2 then 
	    set_scale(util.clamp(App.scale[1].bits + d,1,4095),1)
	end -- turn encoder 2
	if e == 3 then
	    set_scale(util.clamp(App.scale[2].bits + d,1,4095),2)
	end -- turn encoder 3
	
	screen_dirty = true ------------ something changed
end

function key(k, z) ------------------ key() is automatically called by norns
	App:handle_key(k,z)
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
	--[[
	if(musicutil.interval_lookup[App.scale[1].bits] ~= nil)then
		if params:get('scale_1_follow') > 1 then
			screen.text(musicutil.note_num_to_name(App.scale[1].root + App.chord.root, false) .. ' ' .. musicutil.interval_lookup[App.scale[1].bits].name )
		else
			screen.text(musicutil.note_num_to_name(App.scale[1].root, false) .. ' ' .. musicutil.interval_lookup[App.scale[1].bits].name )
		end
	else
		screen.text(musicutil.note_num_to_name(App.scale[1].root, false) .. ' ' .. App.scale[1].bits )
	end
	
	screen.move(2,20)
	
	if(musicutil.interval_lookup[App.scale[2].bits] ~= nil)then
		if params:get('scale_2_follow') > 1 then
			screen.text(musicutil.note_num_to_name(App.scale[2].root + App.chord.root, false) .. ' ' .. musicutil.interval_lookup[App.scale[2].bits].name )
		else
			screen.text(musicutil.note_num_to_name(App.scale[2].root, false) .. ' ' .. musicutil.interval_lookup[App.scale[2].bits].name )
		end
	else
		screen.text(musicutil.note_num_to_name(App.scale[2].root, false) .. ' ' .. App.scale[2].bits )
	end


	screen.move(127,10)
	screen.text_right(App.chord.root)
	

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
	]]
end

function r() ----------------------------- execute r() in the repl to quickly rerun this script
	utilities.unrequire(path_name .. 'app')
	utilities.unrequire(path_name .. 'track')
	utilities.unrequire(path_name .. 'trackcomponent')
	utilities.unrequire(path_name .. 'input')
	utilities.unrequire(path_name .. 'output')
	utilities.unrequire(path_name .. 'grid')
	utilities.unrequire(path_name .. 'mode')
	utilities.unrequire(path_name .. 'seq')
	utilities.unrequire(path_name .. 'mute')
	utilities.unrequire(path_name .. 'scale')
	utilities.unrequire(path_name .. 'musicutil-extended')
	utilities.unrequire(path_name .. 'utilities')
	norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
	clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end