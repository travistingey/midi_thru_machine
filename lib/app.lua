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
	self.current_track = 1
	
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
	for i = 0, 4 do
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
	else
		event = { type ='start' }
		self.midi_in:start()
		self.midi_out:start()
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
	print('handle_key',k,z)
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
		elseif press_fn then
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

	params:add_group('Devices',4)
	params:add_option("midi_in", "MIDI In",self.midi_device_names,1)
	params:add_option("midi_out", "MIDI Out",self.midi_device_names,2)
	params:add_option("midi_grid", "Grid",self.midi_device_names,3)
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
	
end

function App:register_midi_in(n)
	-- Note: We must change existing events to nil to break the event handling.
	-- If the App.midi_in pointer is changed, the event will still be bound to the connected device in memory.
	-- So much confusion ensues when old devices are still bound, wreaking havoc like ghosts.

	self.midi_in.event = nil
		
	self.midi_in = midi.connect(n)

	self.midi_in.event = function(msg)
		
		App.screen_dirty = true

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
		
		if not (data.type == "start" or data.type == "continue" or data.type == "stop" or data.type == "clock") then
			App:on_midi(data)
		end
		
	end
end

function App:register_midi_out(n)
	self.midi_out.event = nil
	self.midi_out = midi.connect(n)
end

function App:register_midi_grid(n)
	
	self.midi_grid.event = nil
	self.midi_grid = midi.connect(n)

	self.midi_grid:send({240,0,32,41,2,13,0,127,247}) -- Set to Launchpad to Programmer Mode

	self:register_modes()
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
			screen.ping()
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
			ScaleGrid:new({id=1, offset = {x=0,y=6}}),
			ScaleGrid:new({id=2, offset = {x=0,y=4}}),
			MuteGrid:new({track=1}),
			NoteGrid:new({track=1})
		},
		on_row = function(s,data)
			
			if data.state then
				s.layer[1] = function()
					screen.font_face(1)
					screen.font_size(8)
					screen.level(16)
					screen.move(66,16)
					screen.text(NoteGrid.action[data.row].name)
					screen.fill() 
				end
				
				s.components[4]:select_action(data.row)
				for i = 2, 8 do
					s.row_pads.led[9][i] = 0
				end

				s.row_pads.led[9][9 - data.row] = 1
				s.row_pads:refresh()

				App:draw()
			end
		end,
		default = function()
			screen.level(6)
			screen.rect(0,0,64,32)
			screen.fill()
			screen.move(0, 28)
			screen.font_face(58)
			screen.font_size(32)
			screen.level(0)
			screen.text(math.floor(clock.get_tempo() + 0.5))
			screen.fill()

		screen.fill() ---------------- fill the termini and message at once
		end,
		context = {
			enc3 = function(d)
				local midi = App.track[1].midi_out + d
				
				params:set('track_1_midi_out', midi)
				params:set('track_1_midi_in', midi)
				App.mode[1].layer[2] = function()
					screen.move(66,10)
					screen.font_size(8)
					screen.font_face(1)
					screen.text('CHANNEL ' .. midi)
					screen.level(10)
					screen.fill()
				end
				
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