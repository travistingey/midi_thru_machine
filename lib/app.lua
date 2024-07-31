-- Define a new class for Control
local App = {}

local path_name = 'Foobar/lib/'


local LaunchControl = require(path_name .. 'launchcontrol')
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
	self.launchcontrol = {}
	self.mixer = {}
	self.bluebox = {}
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
	App:register_launchcontrol(9)
	App:register_mixer(4)
	App:register_bluebox(5)
	App:register_keys(6)
	App:register_modes()
	
	params:default()
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
		-- self.bluebox:continue()
	else
		event = { type ='start' }
		self.midi_in:start()
		self.midi_out:start()
		-- self.bluebox:start()
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
		-- self.bluebox:stop()

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

	params:add_group('DEVICES',8)
	params:add_option("midi_in", "MIDI In",self.midi_device_names,1)
	params:add_option("midi_out", "MIDI Out",self.midi_device_names,2)
	params:add_option("keys", "Keys",self.midi_device_names,6)
	params:add_option("mixer", "Mixer",self.midi_device_names,4)
	params:add_option("midi_grid", "Grid",self.midi_device_names,3)
	params:add_separator()
	params:add_option("launchcontrol", "LaunchControl",self.midi_device_names,9)
	params:add_option("bluebox", "BlueBox",self.midi_device_names,5)
	
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

	params:set_action("mixer", function(x)
		App:register_mixer(x)
	end)

	params:set_action("launchcontrol", function(x)
		App:register_launchcontrol(x)
	end)
	
	params:set_action("bluebox", function(x)
			App:register_bluebox(x)
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
		data.device = 'keys'
		
		if not (data.type == "cc" or data.type == "start" or data.type == "continue" or data.type == "stop" or data.type == "clock") then
			App:on_midi(data)
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

function App:register_mixer(n)
    self.mixer.event = nil
        
    self.mixer = midi.connect(n)
    
	self.mixer.event = function(msg)
        local data = midi.to_msg(msg)
        
        -- Handle MIDI CC data
        if data.type == 'cc' then
            if data.cc >= LaunchControl.cc_map['faders'][1] and data.cc <= LaunchControl.cc_map['faders'][8] then
                -- Handle Faders
				-- Bezier transform translations a linear value to a logarithmic value for bluebox
				local value = bezier_transform(data.val,A,B,C,D)
				data.val = value.value
            end

			self.bluebox:send(data)
        end

        -- Handle MIDI note_on data
        if data.type == 'note_on' then
			
			local send = LaunchControl:handle_note(data)

			if send then 
				App.bluebox:send(send)
			end
			
			LaunchControl:set_led()
        end
    end
end




function App:register_launchcontrol(n)
	LaunchControl:register(n)
	LaunchControl:set_led()
end

function App:register_bluebox(n)		
	self.bluebox = midi.connect(n)
end

function App:register_midi_in(n)
	-- Note: We must change existing events to nil to break the event handling.
	-- If the App.midi_in pointer is changed, the event will still be bound to the connected device in memory.
	-- So much confusion ensues when old devices are still bound, wreaking havoc like ghosts.

	self.midi_in.event = nil
		
	self.midi_in = midi.connect(n)

	self.midi_in.event = function(msg)
		
		local data = midi.to_msg(msg)
		data.device = 'midi_in'

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
	local PresetSeq = require(path_name .. 'modes/presetseq')
	
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
		id = 1,
		components = {
			PresetSeq:new({track=1}),
			MuteGrid:new({track=1}),
			NoteGrid:new({track=1})
		},
		on_load = function(s,data)
		 	s.row_pads.led[9][8] = 1
			s.row_pads:refresh()
			 App.screen_dirty = true
		end,
		on_row = function(s,data)
			if data.state then
				local text = ''
				if data.row == 1 then
					s.components[3]:set_channel(10)
					text = 'DRUMS'
				elseif data.row == 2 then
					s.components[3]:set_channel(1)
					text = 'SEQ 1'
				elseif data.row == 3 then
					s.components[3]:set_channel(2)
					text = 'SEQ 2'
				end
				
				
				s.layer[1] = function()
					screen.font_face(1)
					screen.font_size(8)
					screen.level(16)
					screen.move(64,16)
					screen.text(text)
					screen.fill() 
				end
				
				for i = 2, 8 do
					s.row_pads.led[9][i] = 0
				end

				s.row_pads.led[9][9 - data.row] = 1
				s.row_pads:refresh()

				App.screen_dirty = true
			end
		end,
		default = {
			screen = App.default.screen
		},
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
		id = 2,
		components = {SeqGrid:new({track=1})}
	})

	self.mode[3] = Mode:new({
		id = 3,
		components = {
			ScaleGrid:new({id=1, offset = {x=0,y=6}}),
			ScaleGrid:new({id=2, offset = {x=0,y=4}}),
			ScaleGrid:new({id=3, offset = {x=0,y=2}})
		}
	})

	self.mode[4] = Mode:new({
		id = 4,
		components = {
		SeqClip:new({ track = 1, offset = {x=0,y=7}, active = true  }),
		SeqClip:new({ track = 2, offset = {x=0,y=6} }),
		SeqClip:new({ track = 3, offset = {x=0,y=5} }),
		SeqClip:new({ track = 4, offset = {x=0,y=4} }),
		SeqClip:new({ track = 5, offset = {x=0,y=3} }),
		SeqClip:new({ track = 6, offset = {x=0,y=2} }),
		SeqClip:new({ track = 7, offset = {x=0,y=1} }),
		SeqClip:new({ track = 8, offset = {x=0,y=0} })
		}
	})

	self.mode[1]:disable() --clear out the old junk
	self.mode[1]:enable()
	
end

return App