-- Define a new class for Control
local App = {}

local path_name = 'Foobar/lib/'
local Grid = require(path_name .. 'grid')
local Track = require(path_name .. 'track')
local Scale = require(path_name .. 'components/scale')
local Output = require(path_name .. 'components/output')
local Mode = require(path_name .. 'mode')

local musicutil = require(path_name .. 'musicutil-extended')

function App:init()
	self.screen_dirty = true
	-- Model
	self.chord = {}
	self.scale = {}
	self.output = {}
	self.track = {}
	self.mode = {}

	self.current_mode = 1
	self.current_trigger = nil
	
	self.bsp_record = false -- need a flag to control when notes flow into BSP from the keys

	self.preset = 1
	
	self.ppqn = 24
	self.swing = 0.5
	self.swing_div = 6 -- 1/16 note swing

	-- start_time, last_time are represented in beat time
	self.tick = 0
	self.start_time = 0
	self.last_time = 0
	
	self.triggers = {} -- Track which notes are used for triggers


	self.context = {}
	self.key = {}
	self.alt_down = false
	self.key_down = 0

	self.midi_device = {} -- container for connected midi devices
	local midi_device = self.midi_device
  	self.midi_device_names = {}

	for i = 1,#midi.vports do -- query all ports
		midi_device[i] = midi.connect(i) -- connect each device
		table.insert( -- register its name:
		  self.midi_device_names, -- table to insert to
		  ""..util.trim_string_to_width(midi_device[i].name,70) -- value to insert
		)
	  end
	
	-- Instantiate
	self.midi_in = {}
	self.midi_out = {}
	self.midi_grid = {} -- NOTE: must use Launch Pad Device 2
	self.mixer_led = {}
	self.mixer_in = {}
	self.mixer_out = {}
	self.keys = {}


	-- Crow Setup
	self.crow = {input = {0,0},output = {}}
	
	-- Set Crow device input queries and stream handlers
	crow.send("input[1].query = function() stream_handler(1, input[1].volts) end")
	crow.send("input[2].query = function() stream_handler(2, input[2].volts) end")
	
	crow.input[1].stream = function (v) self.crow.input[1] = v end
	crow.input[2].stream = function (v) self.crow.input[2] = v end
	
	crow.input[1].mode('none')
	crow.input[2].mode('none')

	-- Register parameters and instatiate classes
	-- App classes register params themselves during instatiation
	App:register_params()

	-- Create the tracks
	params:add_separator('tracks','Tracks')
	for i = 1, 16 do
		self.track[i] = Track:new({id = i})
	end

	-- Create the Scales
	params:add_separator('scales','Scales')
	for i = 0, 3 do
		self.scale[i] = Scale:new({id = i})
		Scale:register_params(i)
	end

	-- Create the Outputs
	for i = 1, 16 do
		self.output[i] = Output:new({id = i, type='midi', channel = i })
	end

	for i = 1, 2 do
		self.crow.output[i] = Output:new({id = i, type='crow', channel = i })
	end

	--Start your enginges!
	App:register_midi_in(1)
	App:register_midi_out(2)
	App:register_midi_grid(3)
	App:register_mixer_led(9)
	App:register_mixer_in(4)
	App:register_mixer_out(5)
	App:register_keys(6)
	App:register_modes()
	
end -- end App:init

-- Start playback
function App:start(continue)
	print('App start')
	self.playing = true
	self.tick = 0

	self.start_time = clock.get_beats()
	self.last_time = clock.get_beats()


	local event
	if continue then
		event = { type ='continue' }
		self.midi_in:continue()
		self.midi_out:continue()
		self.mixer_out:continue()
	else
		event = { type ='start' }
		self.midi_in:start()
		self.midi_out:start()
		self.mixer_out:start()
	end
	
	-- handle ticks
	if params:get('clock_source') == 1 then
		self.clock = clock.run(function()
			while(true) do
				clock.sync(1/self.ppqn)
				App:send_tick()
			end
		end)
		
		for i = 1, #self.track do
			self.track[i]:process_transport(event)
		end
	else
		self.midi_out:clock()
	end
end

-- Stop playback
function App:stop()
	print('App stop')
	self.playing = false
	
	if params:get('clock_source')  > 1 then
		if self.clock then
			clock.cancel(self.clock)
		end

		self.midi_in:stop()
		self.midi_out:stop()
		self.mixer_out:stop()

		if params:get('clock_source') == 1 then
			for i = 1, #self.track do
				self.track[i]:process_transport({ type ='stop' })
			end
		end
	end
end

-- Send tick event through system
function App:send_tick()
	local data = midi.to_data({ type ='clock' })
	
	self.midi_out:clock()
end

-- Transport events triggered from MIDI In device
function App:on_transport(data)
	if data.type == "start" then
		self:start()
	elseif data.type == "continue" then
		self:start(true)
	elseif data.type == "stop" then
		self:stop()
	end			
	
	for i=1,#self.track do
		self.track[i]:process_transport(data)
	end

end

-- MIDI events triggered from MIDI In device
function App:on_midi(data)
	for i=1,#self.track do
		self.track[i]:process_midi(data)
	end

end

-- Clock events
function App:on_tick()
	self.last_time = clock.get_beats()
	self.tick = self.tick + 1
	self.midi_out:clock()

	for i = 1, #self.track do
		self.track[i]:process_transport({type = 'clock'})
	end
end

function App:crow_query(i)
	crow.send('input[' .. i .. '].query()')
end

-- Setter for static variables
function App:set(prop, value) self[prop] = value end



-- CONTROL HANDLING --
function App:set_context(newContext)
	-- newContext is a table with functions for the new state.
	-- It might not define every possible function, so we use the original "context" as a fallback.
	self.context = setmetatable(newContext, { __index = self.context })
end

function App:draw()
	screen.ping()
	screen.clear() --------------- clear space
	screen.aa(1) ----------------- enable anti-aliasing

	self.mode[self.current_mode]:draw()
	screen.update()
	
end

-- Norns Encoders
function App:handle_enc(e,d)
	local context = self.mode[self.current_mode].context
	-- encoder 1
	if e == 1 then
		if (context.enc1_alt and self.alt_down) then
			context.enc1_alt(d)
		elseif (context.enc1) then
			context.enc1(d)
		end 
	end
	
	-- encoder 2
	if e == 2 then
		if (context.enc2_alt and self.alt_down) then
			context.enc2_alt(d)
		elseif (context.enc2) then
			context.enc2(d)
		end 
	end
	
	-- encoder 3
	if e == 3 then
		if (context.enc3_alt and self.alt_down) then
			context.enc3_alt(d)
		elseif (context.enc3) then
			context.enc3(d)
		end 
	end
end

-- Norns Buttons
function App:handle_key(k,z)
	local context = self.mode[self.current_mode].context
	if k == 1 then
		self.alt_down = z == 1
	elseif ( self.alt_down and z == 1 and context['alt_fn_' .. k] ) then
		context['alt_fn_' .. k]()
	elseif z == 1 then
		self.key_down = util.time()
	elseif not self.alt_down then
		local hold_time = util.time() - self.key_down
		if hold_time > 0.3  and context['long_fn_' .. k] then
			context['long_fn_' .. k]()
		elseif context['press_fn_' .. k] then
			context['press_fn_' .. k]()
		end
	end
end

function App:panic()
	for i = 1,4 do
		crow.output[i].volts = 0
	end
	
	clock.run(function()
		for c = 1,16 do
			for i = 0, 127 do
				
				local off = {
					note = i,
					type = 'note_off',
					ch = c,
					vel = 0
				}
				
				App.midi_out:send(off)
				clock.sleep(.01)
			end
		end
	end)
	print('done')
	
end

function App:register_params()

	params:add_group('DEVICES',7)
	params:add_option("midi_in", "MIDI In",self.midi_device_names,1)
	params:add_option("midi_out", "MIDI Out",self.midi_device_names,2)
	params:add_option("midi_grid", "Grid",self.midi_device_names,3)
	params:add_option("mixer_in", "Mixer In",self.midi_device_names,4)
	params:add_option("mixer_led", "Mixer LED",self.midi_device_names,9)
	params:add_option("mixer_out", "Mixer Out",self.midi_device_names,5)
	params:add_option("keys", "Keys",self.midi_device_names,6)
	params:add_trigger('panic', "Panic")
	params:set_action('panic', function()
		App:panic()
	end)

	params:set_action("midi_in", function(x)
		App:register_midi_in(x)
	end)

	params:set_action("midi_out", function(x)
		App:register_midi_out(x)
	end)
	
	params:set_action("midi_grid", function(x)
			App:register_midi_grid(x)
	end)

	params:set_action("mixer_in", function(x)
		App:register_mixer_in(x)
	end)

	params:set_action("mixer_led", function(x)
		App:register_mixer_led(x)
	end)
	
	params:set_action("mixer_out", function(x)
			App:register_mixer_out(x)
	end)

	params:set_action("keys", function(x)
		App:register_keys(x)
end)
	
end


function App:register_keys(n)
	self.keys.event = nil
		
	self.keys = midi.connect(n)
	self.keys.event = function(msg)
		local data = midi.to_msg(msg)
		
		if self.bsp_record then
			
			data.ch = 1
			tab.print(data)
			App.midi_in:send(data)
		end

	end
end

-- Bezier curve control points
-- when plotted, x represents the input message and y is the curved response
local A = {x = 0, y = 0} -- A.x is set to 0, use A.y to set the minimum output
local B = {x = 0, y = 1.13} -- Shape the curve using points B and C
local C = {x = 0.77, y = 0.64}
local D = {x = 1, y = 1} -- D.x is set to 1, use D.y to set the maximum output


-- Cubic Bezier Curve Mapping
local function bezier_transform(input, P0, P1, P2, P3)
  -- Normalize the input value of [0,127] to range [0, 1]
  local t = input / 127
  local output = {}
  output.input = input

  -- Bezier transform
  local u = 1 - t
  local tt = t * t
  local uu = u * u
  local uuu = uu * u
  local ttt = tt * t

  output.x = uuu * P0.x + 3 * uu * t * P1.x + 3 * u * tt * P2.x + ttt * P3.x
  output.y = uuu * P0.y + 3 * uu * t * P1.y + 3 * u * tt * P2.y + ttt * P3.y

  output.value = math.floor(output.y * 127) -- scaling and flooring output for use as CC message

  return output
end

local MUTE = 1
local SOLO = 2
local ARM = 3
local SEND = 4
local CUE = 5

local RED_LOW = 13
local RED_HIGH = 15
local AMBER_LOW = 29
local AMBER_HIGH = 63 
local YELLOW = 62
local GREEN_LOW = 28
local GREEN_HIGH = 60

local trackCount = 8



Mixer = {
	control = MUTE,
	track = {},	
}

-- Initialize track states
for i = 1, trackCount do
    Mixer.track[i] = { [CUE] = false, [MUTE] = false, [SOLO] = false, [ARM] = false, [SEND] = false }
end

function Mixer:set_led ()
		
	local t = self.track
	local s = self.control
	local HIGH = YELLOW
	local LOW = YELLOW
	
	if s == MUTE then
		HIGH = 0
	end

	if s == SOLO then
		HIGH = GREEN_LOW
	end

	if s == ARM then
		HIGH = RED_HIGH
	end

	local led = {}

	for i=1,8 do

		if t[i][SOLO] then 
			led[i] = GREEN_HIGH
		elseif t[i][MUTE] then
			led[i] = 0
		elseif t[i][CUE] then
			led[i] = YELLOW
		elseif t[i][ARM] then
			led[i] = RED_HIGH
		else
			led[i] = GREEN_LOW
		end
		
	end

	local sysex_message = {
		240, 0, 32, 41, 2, 17, 120, 0, 
		0, led[1], 1, led[2], 2, led[3], 3, led[4], 4, led[5], 5, led[6], 6, led[7], 7, led[8],     -- Top row knobs bright green
		8, led[1], 9, led[2], 10, led[3], 11, led[4], 12, led[5], 13, led[6], 14, led[7], 15, led[8], -- Middle row knobs bright green
		16, led[1], 17, led[2], 18, led[3], 19, led[4], 20, led[5], 21, led[6], 22, led[7], 23, led[8], -- Bottom row knobs bright green
		24, (t[1][SEND] and GREEN_HIGH or 0) , 25, (t[2][SEND] and GREEN_HIGH or 0), 26, (t[3][SEND] and GREEN_HIGH or 0), 27, (t[4][SEND] and GREEN_HIGH or 0), 28, (t[5][SEND] and GREEN_HIGH or 0), 29, (t[6][SEND] and GREEN_HIGH or 0), 30, (t[7][SEND] and GREEN_HIGH or 0), 31, (t[8][SEND] and GREEN_HIGH or 0), -- Top channel buttons low amber
		32, led[1], 33, led[2], 34, led[3], 35, led[4], 36, led[5], 37, led[6], 38, led[7], 39, led[8], -- Bottom channel buttons full green
		40, (self.control == CUE and 60 or 0), -- Device off
		41, (self.control == MUTE and 60 or 0), -- Mute button full
		42, (self.control == SOLO and 60 or 0), -- Solo button low
		43, (self.control == ARM and 60 or 0), -- Record Arm button low
		44,0, -- Up off
		45,0, -- Up off
		46,0, -- Up off
		47,0, -- Up off
		247
	}

	App.mixer_led:send(sysex_message)
end




function App:register_mixer_in(n)
    self.mixer_in.event = nil
        
    self.mixer_in = midi.connect(n)
    
    
    Mixer:set_led()
	
	self.mixer_in.event = function(msg)
        local data = midi.to_msg(msg)
        
        -- Handle MIDI CC data
        if data.type == 'cc' then
            if data.cc >= 13 and data.cc <= 20 then
                -- Handle Top Row Knobs
            elseif data.cc >= 29 and data.cc <= 36 then
                -- Handle Middle Row Knobs
            elseif data.cc >= 49 and data.cc <= 56 then
                -- Handle Bottom Row Knobs
            elseif data.cc >= 77 and data.cc <= 84 then
                -- Handle Faders
				local value = bezier_transform(data.val,A,B,C,D)
				data.val = value.value
            else
                -- Handle other CC data if needed
            end

			if data.type == 'cc' then
				self.mixer_out:send(data)
			end
        end

        -- Handle MIDI note_on data
        if data.type == 'note_on' then
            if data.note >= 0 and data.note <= 7 then
                -- Handle Top Row Channel Buttons
				local index = data.note + 1

				local state = not Mixer.track[index][SEND]
				Mixer.track[index][SEND] = state

				local send = {
					type = 'cc',
					val = state and 127 or 0,
				}
				tab.print(Mixer.track[index])
				send.cc = data.note

				App.mixer_out:send(send)
                
            elseif data.note >= 12 and data.note <= 19 then

                -- Handle Bottom Row Channel Buttons
                local index = data.note - 11
				local state = not Mixer.track[index][Mixer.control]
				Mixer.track[index][Mixer.control] = state

				tab.print(Mixer.track[index])

				local send = {
					type = 'cc',
					val = state and 127 or 0,
				}

				if Mixer.control == MUTE then
					send.cc = index + 36
				end

				if Mixer.control == SOLO then
					send.cc = index + 57
				end

				if Mixer.control == ARM then
					send.cc = index + 85
				end

				if Mixer.control == CUE then
					send.cc = index + 99
				end

				App.mixer_out:send(send)

            elseif data.note >= 120 and data.note <= 127 then
				print('control', data.note)
                -- Handle Device, Mute, Solo, Record Arm, Up, Down, Left, Right Buttons
                -- UP
				if data.note == 120 then
					
				end

				-- DOWN
				if data.note == 121 then
				
				end
				
				-- LEFT
				if data.note == 122 then
				
				end
				
				-- RIGHT
				if data.note == 123 then
				
				end

				-- DEVICE
				if data.note == 124 then
					Mixer.control = CUE
				end

				-- MUTE
				if data.note == 125 then
					Mixer.control = MUTE
				end

				-- SOLO
				if data.note == 126 then
					Mixer.control = SOLO
				end

				-- ARM
				if data.note == 127 then
					Mixer.control = ARM
				end
            else
                -- Handle other note data if needed
				print('other')
                tab.print(data)
            end
			
			Mixer:set_led()
        end
    end
end


-- function App:register_mixer_in(n)
-- 	self.mixer_in.event = nil
		
-- 	self.mixer_in = midi.connect(n)
-- 	self.mixer_in.event = function(msg)
-- 		local data = midi.to_msg(msg)
		
-- 		--Make volume faders act logorithmically by transforming CC values
-- 		if data.type == 'cc' and data.ch == 1 and data.cc >=77 and data.cc <=84 then
-- 			local value = bezier_transform(data.val,A,B,C,D)
			
-- 			data.val = value.value
-- 		end

-- 		if data.type == 'cc' then
-- 			self.mixer_out:send(data)
-- 		end
-- 	end
-- end



function App:register_mixer_led(n)
	self.mixer_led.event = nil
		
	self.mixer_led = midi.connect(n)
	
end

function App:register_mixer_out(n)		
	self.mixer_out = midi.connect(n)
end

function App:register_midi_in(n)
	-- Note: We must change existing events to nil to break the event handling.
	-- If the App.midi_in pointer is changed, the event will still be bound to the connected device in memory.
	-- So much confusion ensues when old devices are still bound, wreaking havoc like ghosts.

	self.midi_in.event = nil
		
	self.midi_in = midi.connect(n)

	self.midi_in.event = function(msg)
		
		local data = midi.to_msg(msg)

		if self.debug then
			print('Incoming MIDI')
			tab.print(data)
		end

		--external midi transport
		if params:get('clock_source') > 1 and (data.type == "start" or data.type == "continue" or data.type == "stop") then
			App:on_transport(data)
		end

		if data.type == 'clock'then
			App:on_tick()
		end
		
		if data.type == 'cc'then
			if data.cc == 50 then
				self.bsp_record = (data.val > 0)
			end

			App.midi_out:send(data)
		end

		if not (data.type == "cc" or data.type == "start" or data.type == "continue" or data.type == "stop" or data.type == "clock") then
			App:on_midi(data)
		end
		
		App.screen_dirty = true

	end
end

function App:register_midi_out(n)
	self.midi_out = midi.connect(n)
end

function App:register_midi_grid(n)
	
	self.midi_grid.event = nil
	self.midi_grid = midi.connect(n)

	self.midi_grid:send({240,0,32,41,2,13,0,127,247}) -- Set to Launchpad to Programmer Mode

	self:register_modes()
end

App.default = {}

App.default.screen = function()
			
	if App.playing then
		local beat = 15 - math.floor( (App.tick % 24) / 24 * 16)
		screen.level( beat )
	else
		screen.level(5)
	end
	screen.rect(0,0,56,32)
	screen.fill()
	screen.move(28, 26)
	screen.font_face(58)
	screen.font_size(32)
	screen.level(0)
	screen.text_center(math.floor(clock.get_tempo() + 0.5))
	screen.fill()

	screen.level(10)
	screen.move(66,10)
	screen.font_size(8)
	screen.font_face(1)
	if App.track[1].midi_in == 0 then
		screen.text('NO INPUT')
	else
		screen.text('CHANNEL ' .. App.track[1].midi_in)
	end

	if App.current_trigger then
		screen.move(0,40)
		screen.text(App.current_trigger)
		for i=1,16 do
			if App.track[i].triggered and App.track[i].trigger == App.current_trigger then
				screen.move(0,48)
				screen.text('Track ' .. i)
			end
		end

		screen.fill()
	end
end

function App:register_modes()

	-- Create the modes
	self.grid = Grid:new({
		grid_start = {x=1,y=1},
		grid_end = {x=4,y=1},
		display_start = {x=1,y=1},
		display_end = {x=4,y=1},
		offset = {x=4,y=8},
		midi = App.midi_grid,
		event = function(s,data)
			if data.state then
				s:reset()
				local mode = App.mode[App.current_mode]
				mode.arrow_pads:reset()
				mode.alt_pad:reset()
				mode.row_pads:reset()

				App.current_mode = s:grid_to_index(data)
				for i = 1, #App.mode do
					if i ~= App.current_mode then
						App.mode[i]:disable()
					end					
				end
				App.mode[App.current_mode]:enable()
				s.led[data.x][data.y] = 1
				s:refresh()
			end
		end,
		active = true
	})

	self.midi_grid.event = function(msg)
		local mode = self.mode[self.current_mode]
		self.grid:process(msg)
		mode.grid:process(msg)
	end
	
	local AllClips = require(path_name .. 'modes/allclips') 
	local SeqClip = require(path_name .. 'modes/seqclip') 
	local SeqGrid = require(path_name .. 'modes/seqgrid') 
	local ScaleGrid = require(path_name .. 'modes/scalegrid') 
	local MuteGrid = require(path_name .. 'modes/mutegrid') 
	local NoteGrid = require(path_name .. 'modes/notegrid')
	local PresetGrid = require(path_name .. 'modes/presetgrid')
	
	local draw_things = function() end
	
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
	font = fonts[1]


	
	self.mode[1] = Mode:new({
		components = {
			PresetGrid:new({track=1}),
			MuteGrid:new({track=1}),
			NoteGrid:new({track=1})
		},
		on_row = function(s,data)
			if data.state and data.row <= #s.components[3].action then
				s.layer[1] = function()
					screen.font_face(1)
					screen.font_size(8)
					screen.level(16)
					screen.move(64,16)
					screen.text(NoteGrid.action[data.row].name)
					screen.fill() 
				end
				
				s.components[3]:select_action(data.row)
				for i = 2, 8 do
					s.row_pads.led[9][i] = 0
				end

				s.row_pads.led[9][9 - data.row] = 1
				s.row_pads:refresh()

				App.screen_dirty = true
			end
		end,
		default = {screen = App.default.screen},
		context = {
			enc1 = function(d)
				local midi = App.track[1].midi_out + d
				
				params:set('track_1_midi_out', midi)
				params:set('track_1_midi_in', midi)
				
				App.mode[App.current_mode]:enable()
				App.screen_dirty = true

			end 
		}
	})

	self.mode[2] = Mode:new({
		components = {SeqGrid:new({track=1})}
	})

	self.mode[3] = Mode:new({
		components = {
			ScaleGrid:new({id=1, offset = {x=0,y=6}}),
			ScaleGrid:new({id=2, offset = {x=0,y=4}}),
			ScaleGrid:new({id=3, offset = {x=0,y=2}})
		}
	})

	self.mode[4] = Mode:new({
		components = {
		SeqClip:new({ track = 1, offset = {x=0,y=7}, active = true  }),
		SeqClip:new({ track = 2, offset = {x=0,y=6} }),
		SeqClip:new({ track = 3, offset = {x=0,y=5} }),
		SeqClip:new({ track = 4, offset = {x=0,y=4} }),
		SeqClip:new({ track = 5, offset = {x=0,y=3} }),
		SeqClip:new({ track = 6, offset = {x=0,y=2} }),
		SeqClip:new({ track = 7, offset = {x=0,y=1} }),
		SeqClip:new({ track = 8, offset = {x=0,y=0} })
		},
		on_arrow = function(s,data)
			if data.type == 'down' then
				print('down town charlie brown')
			end
		end
	})

	self.mode[1]:disable() --clear out the old junk
	self.mode[1]:enable()
	
end

return App