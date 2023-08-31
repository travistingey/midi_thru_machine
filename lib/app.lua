local path_name = 'Foobar/lib/'
local MidiGrid = require(path_name .. 'midigrid')
local Grid = require(path_name .. 'grid')
local Track = require(path_name .. 'track')
local Mode = require(path_name .. 'mode')

local musicutil = require(path_name .. 'musicutil-extended')

-- Define a new class for Control
local App = {}

function App:init()
	-- Model
	self.chord = {}
	self.scale = {{bits = 1, root = 0}, {bits = 1, root = 0}}
	self.track = {}
	self.mode = {}

	self.current_bank = 1
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
	
	
	self.context = {}
	self.key = {}
	self.alt_down = false
	self.key_down = 0

	self:set_scale(1,1)

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
	self.crow_out = {{},{},{},{}}

	self.crow_in[1] = {}
	self.crow_in[2] = {}
	
	--[[ for i = 1, 4 do
		local out = 'crow_out_' .. i .. '_'
		self.crow_out[i] = {
			type = params:get(out .. 'type'),
			source = params:get(out .. 'source'),
			trigger = params:get(out .. 'trigger')
		}
	end ]]

	-- Set Crow device input queries and stream handlers
	crow.send("input[1].query = function() stream_handler(1, input[1].volts) end")
	crow.send("input[2].query = function() stream_handler(2, input[2].volts) end")
	
	crow.input[1].stream = function (v) self.crow_in[1].volts = v end
	crow.input[2].stream = function (v) self.crow_in[2].volts = v end
	
	crow.input[1].mode('none')
	crow.input[2].mode('none')
	
	-- Create the tracks
	params:add_separator('tracks','Tracks')
	for i = 1, 16 do
		self.track[i] = Track:new({id = i})
	end
	
	-- Create the modes
	self.grid = Grid:new({
		grid_start = {x=1,y=1},
		grid_end = {x=9,y=9},
		display_start = {x=1,y=1},
		display_end = {x=9,y=9},
		midi = self.midi_grid,
		active = true
	})

	-- Track components are instantiated with parameter actions
	params:default()


	--[[
		This is the start of a new Mode class. Let's describe the patterns that work so that we can make the mode class a better wrapper.
		1.	The App's midi_grid event need to pass the raw event data to the Grid instances for the current mode using the :process method.
		2.	Function Pads: the arrow pads, bank select, alt pad and indicator will switch functions between modes.
			We can pass data from these grid events by calling other grid events directly using the components grid methods.
			We should be careful since the indices for the function pads are outside the main grid, which could cause issues.
			Can we use a callback pattern here?
		3.	Mode select executes at an App level and is responsible for enabling and disabling a track component's grids.
			This has been standardized by using the Grid enable/disable methods.
			The mode class will register the specific grid components that will need to be enabled and disabled
		4.	Initialization: Track components will assume to be disabled on load. We will need to enable the first mode

		]]
	
	

	-- We need to manage this at the App level
	self.midi_grid.event = function(msg)
		self.grid:process(msg)
		
		local mode = self.mode[self.current_mode]

		for i,component in ipairs(mode.components) do
			component:process(msg)
		end
	end
	
	self.arrow_pads = self.grid:subgrid({x=1,y=9},{x=4,y=9},function(s,data)

		local mode = self.mode[self.current_mode]

		for i,component in ipairs(mode.components) do
			component:event(data)
		end
	end)

	self.row_pads = self.grid:subgrid({x=9,y=8},{x=9,y=2},function(s,data)

		local mode = self.mode[self.current_mode]

		for i,component in ipairs(mode.components) do
			component:event(data)
		end
	end)


	-- Mode setup and instantiation must happen after components are initialized with the params:default() execution
	local session_mode = {
		id = 1,
		components = {App.track[10].seq.clip_grid, App.track[10].seq.seq_grid, App.track[10].mute.grid},
		on_load = function() print('Mode one loaded') end,
		on_reset = function() end,
	}

	local drum_mode = {
		id = 2,
		components = {},
		on_load = function() print('Mode two loaded') end,
	}

	local key_mode = {
		id = 3,
		components = {},
		on_load = function() print('Mode three loaded') end,

	}

	local user_mode = {
		id = 4,
		components = {},

	}

	self.mode = {session_mode,drum_mode,key_mode,user_mode}
	
	self.mode_select = self.grid:subgrid({x=5,y=9},{x=8,y=9},function(s,data)
			if data.state then
				local mode_select = s:grid_to_index(data)
				
				for i, mode in ipairs(App.mode) do
					if mode_select ~= mode.id then
						for i, component in ipairs(mode.components) do
							component:disable()
						end
					end
				end

				for i, mode in ipairs(App.mode) do
					if mode_select == mode.id then
						
						if mode.on_load ~= nil then
							mode.on_load()
						end

						for i, component in ipairs(mode.components) do
							component:enable()
						end

					end

					
				end

				s:reset()
				s.led[data.x][data.y] = 1
				s:refresh()
				
				self.current_mode = mode_select


			end
		end
	)

	

	local mode_led = self.mode_select:index_to_grid(self.current_mode)
	self.mode_select.led[mode_led.x][mode_led.y] = 1

	-- Alt pad
	self.alt_pad = self.grid:subgrid({x=9,y=1},{x=9,y=1}, function(s,data)
		if data.toggled then
			s.led[data.x][data.y] = 1
		else
			s.led[data.x][data.y] = 0
		end
		App.alt = data.toggled
		s:refresh()
	end)

	-- Using the on_reset callback in order to set App level properties.
	self.alt_pad.on_reset = function(s)
		App.alt = false
	end

	

	
	-- Enable Modes
	
	self.track[10].seq.clip_grid:enable()
	self.track[10].seq.seq_grid:enable()
	self.track[10].mute.grid:enable()
	
	-- swap a grid
	-- change grid display
	
	
end

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

	-- self.grid.toggled[9][9] = not self.grid.toggled[9][9]

	-- if self.grid.toggled[9][9] then
	-- 	self.grid.led[9][9] = 5
	-- else
	-- 	self.grid.led[9][9] = 3
	-- end

	for i = 1, #self.track do
		self.track[i]:process_transport({type = 'clock'})
	end
end

function App:crow_query(i)
	crow.send('input[' .. i .. '].query()')
end

-- Setter for static variables
function App:set(prop, value) self[prop] = value end

-- METHODS --
-- Sets the current scale from bits
-- i = bits
-- d = scale selection
function App:set_scale(i,d)
	self.scale[d].bits = i
	self.scale[d].intervals = musicutil.bits_to_intervals(i)
	self.scale[d].notes = {}

	for i=1,5 do
		for j=1,#self.scale[d].intervals do
			self.scale[d].notes[(i - 1) * #self.scale[d].intervals + j] = self.scale[d].intervals[j] + (i-1) * 12
		end
	end
	
	-- crow.input[d].mode('scale',scale)
	screen_dirty = true

--[[
	-- Update leds for Keys mode
	if Mode and Mode.select == 3 then
		Mode[3]:set_grid()
	end]]
end

-- shifts a App.scale to the target note degree
function App:shift_scale_to_note(s, n)
	local scale = musicutil.shift_scale(self.scale[s].bits, n - self.scale[s].root)
	self.scale[s].root = n - 48
	self:set_scale(scale, s)
end

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


-- -- toggle the alt pad and trigger alt functions for modes
-- function App:set_alt(state)
-- 	if(state) then
-- 		self.grid.led[9][1] = {3,true}
-- 		self.grid.toggled[9][1] = true
-- 		if(Mode[Mode.select].alt_event ~= nil) then
-- 			Mode[Mode.select]:alt_event(true)
-- 		end
-- 	else
-- 		self.grid.led[9][1] = 0
-- 		self.grid.toggled[9][1] = false
-- 		if(Mode[App.mode].alt_event ~= nil) then
-- 			Mode[App.mode]:alt_event(false)
-- 		end
-- 	end
-- end


-- function App:get_alt()
-- 	return self.grid.toggled[9][1]
-- end

-- -- The Alt button is the grid pad used to access secondary functions. 
-- -- Based on the toggle state, tapping Alt will toggle on or off
-- -- Methods using Alt check if the toggle state is true and should reset toggle state to false after event completes
-- function App:handle_function_grid(data)
-- 	local x = data.x
-- 	local y = data.y
-- 	local alt = self:get_alt()

-- 	-- Alt button
-- 	if x == 9 and y == 1 and data.state then
-- 		if(alt)then
-- 			self:set_alt(true)
-- 		else
-- 			self:set_alt(false)
-- 		end
-- 	end

-- 	--Bank Select
-- 	if x == 9 and y > 1 and data.state then

-- 		local bank_select = 9 - y

-- 		if(alt) then
-- 			if bank_select == self.current_bank then
-- 				print('we gonna save this PSET')
-- 			else
-- 				print('we gonna load this PSET')
-- 			end
			
-- 			self:set_alt(false)
			
-- 		elseif bank_select ~= self.current_bank then
-- 			self.current_bank = bank_select
--             Preset:set_grid()
--             Mute:set_grid()
            
-- 			for i = 2, 8 do			
-- 				self.grid.led[9][i] = 0
-- 			end

-- 			self.grid.led[9][y] = 3
-- 			params:set('drum_bank', self.current_bank)
-- 		end
-- 	end

-- 	Mode:grid_event(data)
-- end




-- MidiGrid Event Handler
-- Event triggered for every pad up and down event — TRUE state is a pad up event, FALSE state is a pad up event.
-- param s = self, MidiGrid instance
-- param data = { x = 1-9, y = 1-9, state = boolean }
-- function grid_event(s, data)
-- 	screen:ping()
-- 	App:handle_function_grid(data)
	
-- 	Mode[App.mode]:grid_event(data)
	
-- 	Mute.grid_event(s, data) -- Sets display of mute buttons
-- 	Preset.grid_event(s, data) -- Manages loading and saving of mute states

-- 	App.grid:redraw()
-- end


-- -- Transport Event occurs when a MIDI event is sent from the input device
-- function transport_event(data)

-- 	-- track whether transport is playing
-- 	if(data.type == 'start' or data.type == 'continue') then
--         App:play()
--     elseif(data.type == 'stop') then
--         App:stop()
--     end

	
    
-- 	-- process modes
-- 	for i = 1, 4 do
-- 		if Mode[i].transport_event ~= nil then
--         	Mode[i]:transport_event(data)
-- 		end
--     end

--     App.grid:redraw()
-- end

--
-- function midi_event(data)
-- 	-- process mutes
-- 	Mute.midi_event(data)
	
-- 	for i = 1, 4 do
-- 		if Mode[i].midi_event ~= nil then
--         	Mode[i]:midi_event(data)
-- 		end
--     end

-- 	if (data.ch == params:get('bsp_drum_channel')) then
--         process_drum_channel(data)
--     elseif(data.ch == params:get('bsp_seq1_channel'))then
--         process_seq_1_channel(data)
--     else
--         process_other_channels(data)
--     end

-- 	App.grid:redraw()
-- end

return App