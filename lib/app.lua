local path_name = 'Foobar/lib/'
local Grid = require(path_name .. 'grid')
local Track = require(path_name .. 'track')
local Scale = require(path_name .. 'scale')
local Output = require(path_name .. 'output')
local Mode = require(path_name .. 'mode')



local musicutil = require(path_name .. 'musicutil-extended')

-- Define a new class for Control
local App = {}

function App:init()
	-- Model
	self.chord = {}
	self.scale = {}
	self.output = {}
	self.track = {}
	self.mode = {}


	self.current_mode = 1
	self.current_track = 10
	
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

	local midi_device = {} -- container for connected midi devices
  	local midi_device_names = {}

	for i = 1,#midi.vports do -- query all ports
		midi_device[i] = midi.connect(i) -- connect each device
		table.insert( -- register its name:
		  midi_device_names, -- table to insert to
		  ""..util.trim_string_to_width(midi_device[i].name,70) -- value to insert
		)
	  end
	
	params:add_group('Devices',3)
	params:add_option("midi_in", "MIDI In",midi_device_names,1)
	params:add_option("midi_out", "MIDI Out",midi_device_names,6)
	params:add_option("midi_grid", "Grid",midi_device_names,3)

	params:set_action("midi_in", function(x) App.midi_in = midi.connect(x) end)
	params:set_action("midi_out", function(x) App.midi_out = midi.connect(x) end)
	params:set_action("midi_grid", function(x)
		App.midi_grid = midi.connect(x)
		self.midi_grid:send({240,0,32,41,2,13,0,127,247}) -- Set to Launchpad to Programmer Mode
	end)
	
	params:bang()
	
	-- Set up transport event handler for incoming MIDI from the Transport device
    self.midi_in.event = function(msg)
		local data = midi.to_msg(msg)

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


	-- Crow Setup
	self.crow_in = {{},{}}

	-- Set Crow device input queries and stream handlers
	crow.send("input[1].query = function() stream_handler(1, input[1].volts) end")
	crow.send("input[2].query = function() stream_handler(2, input[2].volts) end")
	
	crow.input[1].stream = function (v) self.crow_in[1].volts = v end
	crow.input[2].stream = function (v) self.crow_in[2].volts = v end
	
	crow.input[1].mode('none')
	crow.input[2].mode('none')

	-- Create shared scales
	for i = 0, 16 do
		self.scale[i] = Scale:new({id = i})
	end

	-- Create shared outputs
	for i = 1, 16 do
		self.output[i] = Output:new({
			id = i,
			midi_event = Output.types['midi'].midi_event
		})
	end

	-- Create the tracks
	params:add_separator('tracks','Tracks')
	for i = 1, 16 do
		self.track[i] = Track:new({id = i})
	end

  params:set('track_1_midi_out',1)

	-- Track components are instantiated with parameter actions
	params:default()

	self.midi_grid.event = function(msg)
		local mode = self.mode[self.current_mode]
		self.grid:process(msg)
		mode.grid:process(msg)
	end

	-- Create the modes

	-- TODO: Modes required after App is instantiated. May want to fix this...
	local AllClips = require(path_name .. 'modes/allclips') 
	local SeqClip = require(path_name .. 'modes/seqclip') 
	local SeqGrid = require(path_name .. 'modes/seqgrid') 
	local ScaleGrid = require(path_name .. 'modes/scalegrid') 
	local MuteGrid = require(path_name .. 'modes/mutegrid') 


	self.mode[1] = Mode:new({
		components = {AllClips:new({track=1}),MuteGrid:new({track=1})}
	})

	self.mode[2] = Mode:new({
		components = {SeqGrid:new({track=1})}
	})

	self.mode[3] = Mode:new({
		components = {ScaleGrid:new({id=1})}
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
	
	-- Create the modes
	self.grid = Grid:new({
		grid_start = {x=1,y=1},
		grid_end = {x=4,y=1},
		display_start = {x=1,y=1},
		display_end = {x=4,y=1},
		offset = {x=4,y=8},
		midi = self.midi_grid,
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
				print(App.current_mode)
				App.mode[App.current_mode]:enable()
				s.led[data.x][data.y] = 1
				s:refresh()
			end
		end,
		active = true
	})
  
  self.current_mode = 1
	self.mode[1]:enable()
	
	self.grid:event({x=1,y=1, state = true})

	
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

-- Norns Encoders
function App:handle_enc(e,d)
	local context = self.context
	-- encoder 1
	if e == 1 then
	  if (context.enc1_alt and self.alt_down) then context.enc1_alt(d)
	  elseif (context.enc1) then context.enc1(d) end 
	end
	
	-- encoder 2
	if e == 2 then
	  if (context.enc2_alt and self.alt_down) then context.enc2_alt(d)
	  elseif (context.enc2) then context.enc2(d) end 
	end
	
	-- encoder 3
	if e == 3 then
	  if (context.enc3_alt and self.alt_down) then context.enc3_alt(d)
	  elseif (context.enc3) then context.enc3(d) end 
	end
end

-- Norns Buttons
function App:handle_key(press_fn,long_fn,alt_fn,k,z)
	local context = self.context
	
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

return App