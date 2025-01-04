-- Define a new class for Control
local App = {}

local path_name = 'Foobar/lib/'

local DeviceManager = require('Foobar/components/app/devicemanager')
local LaunchControl = require(path_name .. 'launchcontrol')
local Grid = require(path_name .. 'grid')
local Track = require('Foobar/components/app/track')
local Scale = require('Foobar/components/track/scale')
local Output = require('Foobar/components/track/output')
local Mode = require('Foobar/components/app/mode')

local musicutil = require(path_name .. 'musicutil-extended')


local LATCH_CC = 64

function App:init()

	self.screen_dirty = true
	self.device_manager = DeviceManager:new()

	-- Model
	self.scale = {}
	self.output = {}
	self.track = {}
	self.mode = {}
	self.settings = {}
	
	self.playing = false
	self.current_mode = 1
	self.current_track = 1

	self.preset = {}
	self.preset_props = {
		track = {
			'program_change',
			'scale_select',
			'arp',
			'slew',
			'note_range_upper',
			'note_range_lower',
			'chance',
			'step',
			'step_length',
			'reset_step'
		}, 
		scale = {
			'bits',
			'root',
			'follow_method',
			'chord_set',
			'follow'
		}
	}

	for i=1,16 do
		self.preset[i] = {}
		self.preset[i]['track_1_program_change'] = i
	end

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

	self.cc_subscribers = {}

	-- State for modes
	self.send_out = true
	self.send_in = true

	-- Instantiate
	self.midi_in = {}
	self.midi_out = {}
	self.midi_grid = {} -- NOTE: must use Launch Pad Device 2
	self.launchcontrol = {}
	self.mixer = {}
	self.bluebox = {}
	self.keys = {}


	-- Crow Setup
	self.crow = self.device_manager.crow

	App:register_params()

	-- Create the tracks
	params:add_separator('tracks','Tracks')
	for i = 1, 16 do
		self.track[i] = Track:new({id = i})
	end

	-- Creating Shared TrackComponents
	-- Create the Scales
	params:add_separator('scales','Scales')
	for i = 0, 3 do
		self.scale[i] = Scale:new({id = i})
		-- Scale:register_params(i)
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
				App.screen_dirty = true
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
		self.midi_in:stop()
		self.midi_out:stop()
		-- self.bluebox:stop()
	end

	if params:get('clock_source') == 1 then
		if self.clock then
			clock.cancel(self.clock)
		end
		for i = 1, #self.track do
			self.track[i]:process_transport({ type ='stop' })
		end
	end

end


function App.apply(settings)
	for k,v in pairs(settings) do
		params:set(k,v)
	end
end

-- Send tick event through system
function App:send_tick()
	self:on_tick()
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
	-- for i=1,#self.track do
	-- 	self.track[i]:process_midi(data)
	-- end
end

-- CC Events
function App:on_cc(data)
	
    if self.cc_subscribers[data.cc] then
        for _, func in ipairs(self.cc_subscribers[data.cc]) do
            func(data)
        end
    end

    -- Pass CC event to the current mode
    if self.mode[self.current_mode] and self.mode[self.current_mode].on_cc then
        self.mode[self.current_mode]:on_cc(data)
    end
	
	self.midi_out:send(data)

end

function App:subscribe_cc(cc_number, func)
    if not self.cc_subscribers[cc_number] then
        self.cc_subscribers[cc_number] = {}
    end
    table.insert(self.cc_subscribers[cc_number], func)
end

function App:unsubscribe_cc(cc_number, func)
    if self.cc_subscribers[cc_number] then
        for i, subscriber in ipairs(self.cc_subscribers[cc_number]) do
            if subscriber == func then
                table.remove(self.cc_subscribers[cc_number], i)
                break
            end
        end
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
end

function App:register_params()
	local midi_devices =  self.device_manager.midi_device_names
	params:add_group('DEVICES',8)
	params:add_option("midi_in", "MIDI In",midi_devices,1)
	params:add_option("midi_out", "MIDI Out",midi_devices,2)
	params:add_option("keys", "Keys",midi_devices,6)
	params:add_option("mixer", "Mixer",midi_devices,4)
	params:add_option("midi_grid", "Grid",midi_devices,3)
	params:add_option("launchcontrol", "LaunchControl",midi_devices,9)
	params:add_option("bluebox", "BlueBox",midi_devices,5)
	
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
	
	params:add_separator()

	App:register_song()
end


function App:save_preset(d, param)
    if self.preset[d] == nil then self.preset[d] = {} end
    local preset = self.preset[d]
    
    if type(param) == 'string' then
        local value = self.settings[param]

        if preset[param] ~= value then
            preset[param] = value
        end
    elseif type(param) == 'table' then
        for index, name in ipairs(param) do
            local value = self.settings[name]
            if preset[name] ~= value then
                preset[name] = value
            end
        end
    else
        for name, value in pairs(self.settings) do
            if preset[name] ~= value then
                preset[name] = value
            end
        end
    end
end

function App:load_preset(d, param, force)
    local preset = self.preset[d]

    if preset == nil then error('App:load_preset was nil') return end
    
    if type(param) == 'string' then
        local value = preset[param]

        if force or (self.settings[param] ~= value) then
            params:set(param, value)    
        end
    elseif type(param) == 'table' then
        for index, name in ipairs(param) do
            local value = preset[name]
			if force or (value and self.settings[name] ~= value) then
                params:set(name, value)
            end
        end
    else
        for name, value in pairs(preset) do
            if self.settings[name] ~= value then
                params:set(name, value)    
            end
        end
    end
end

function App:register_song()
	local swing_spec = controlspec.UNIPOLAR:copy()
	swing_spec.default = 0.5

	self.swing =  0.5
	params:add_control('swing', 'Swing', swing_spec)
	params:set_action('swing', function(d)
		self.swing = d
	end)
end

function App:register_keys(n)
	-- self.keys.event = nil
		
	-- self.keys = midi.connect(n)
	-- self.keys.event = function(msg)
	-- 	local data = midi.to_msg(msg)
	-- 	data.device = 'keys'
		
	-- 	if data.type == 'cc' then
	-- 		self:on_cc(data)
	-- 	end

	-- 	if not (data.type == "cc" or data.type == "start" or data.type == "continue" or data.type == "stop" or data.type == "clock") then
	-- 		App:on_midi(data)
	-- 	end

	-- 	if data.type == "note_on" then
	-- 		App.screen_dirty = true
	-- 	end
	-- end
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
            -- if data.cc >= LaunchControl.cc_map['faders'][1] and data.cc <= LaunchControl.cc_map['faders'][8] then
            --     -- Handle Faders
			-- 	-- Bezier transform translations a linear value to a logarithmic value for bluebox
			-- 	local value = bezier_transform(data.val,A,B,C,D)
			-- 	data.val = value.value
            -- end

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

	function LaunchControl:on_up (state)
		App.send_in = state
	end

	function LaunchControl:on_down (state)
		App.send_out = state
	end
end

function App:register_launchcontrol(n)
	LaunchControl:register(n)
	LaunchControl:set_led()
end

function App:register_bluebox(n)		
	self.bluebox = midi.connect(n)
end

function App.midi_in_event(data)
	data.device = 'midi_in'

	if App.debug then
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
		App:on_cc(data)
		
	end

	if not (data.type == "cc" or data.type == "start" or data.type == "continue" or data.type == "stop" or data.type == "clock") then
		App:on_midi(data)
	end
	
	App.screen_dirty = true
end

-- App.midi_in represents the primary transport and input device
function App:register_midi_in(n)
	if self.midi_in and self.midi_in.type == 'midi' then
		self.midi_in:off('event', App.midi_in_event) -- remove event listener from previous midi device
	end

	self.midi_in = self.device_manager:get(n)

	self.midi_in:on('event', App.midi_in_event)

end

function App:register_midi_out(n)
	self.midi_out = self.device_manager:get(n)
end

function App:register_midi_grid(n)
	
	self.midi_grid = self.device_manager:get(n)

	self.midi_grid:send({240,0,32,41,2,13,0,127,247}) -- Set to Launchpad to Programmer Mode

	self:register_modes('from midi grid')
end

-- Screens and such
App.default = {
	enc1 = function(d) print('default enc 1 ' .. d) end,
	enc2 = function(d) print('default enc 2 ' .. d) end,
	enc3 = function(d) print('default enc 3 ' .. d) end,
	alt_enc1 = function(d) print('default alt enc 1 ' .. d) end,
	alt_enc2 = function(d) print('default alt enc 2 ' .. d) end,
	alt_enc3 = function(d) print('default alt enc 3 ' .. d) end,
	long_fn_2 = function() print('Long 2') end,
	long_fn_3 = function() print('Long 3') end,
	alt_fn_2 = function() print('Alt 2') end,
	alt_fn_3 = function() print('Alt 3') end,
	press_fn_2 = function()
	
		if App.playing then
			App:stop()
		else
			App:start()
		end
	
	end,
	press_fn_3 = function() print('press 3') end

}

App.font = 1
local function set_font(n)
	local fonts = {
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

	screen.font_face(fonts[n].face)
	screen.font_size(fonts[n].size)
end


App.default.screen = function()
	-- Tempo	
	if App.playing then -- Pulse screen level
		local beat = 15 - math.floor( (App.tick % 24) / 24 * 16)
		screen.level( beat )
	else
		screen.level(5)
	end
	
	screen.rect(0,0,56,32)
	screen.fill()
	
	screen.move(28, 26)
	set_font(37)
	screen.level(0)
	screen.text_center(math.floor(clock.get_tempo() + 0.5))
	screen.fill()
	--------

	-- Track Name
	local track_name = params:get('track_' .. App.current_track .. '_name')

	
	if App.track[App.current_track].enabled then
		screen.level(10)
	else
		screen.level(2)
	end

	

	--local chord = musicutil.interval_lookup[App.scale[1].bits]
	local chord = App.scale[1].chord
	if chord and #App.scale[1].intervals  > 2 then
		local name =  chord.name
		local root = chord.root + App.scale[1].root
		local bass = App.scale[1].root
		
		screen.level(15)
		set_font(37)
		screen.move(60,26)
		screen.text(musicutil.note_num_to_name(root))
		local name_offset = screen.text_extents(musicutil.note_num_to_name(root)) + 61
		-- set_font(6)
		set_font(9)
		
		screen.move(name_offset,14)
		screen.text(name)
		screen.fill()

		if bass ~= root then
			screen.move(name_offset,26)
			screen.text('/' .. musicutil.note_num_to_name(bass) )
		end
		
	end

	local plaits = App.scale[3].chord
	if plaits and #App.scale[3].intervals  > 2 then
		local name =  plaits.name
		local root = plaits.root + App.scale[3].root
		local bass = App.scale[3].root
		
		screen.level(15)
		set_font(1)
		screen.move(60,46)
		screen.text(musicutil.note_num_to_name(root) .. name)
		screen.fill()
	end


	screen.move(127,41)

	local interval_names = {'R','b2','2','b3','3','4','b5','5','b6','6','b7','7'}

	set_font(1)
	for i=1, #interval_names do
		
		if App.scale[1].bits & 1 << (i - 1) > 0 then
			screen.level(15)
		else
			-- NO INTERVAL
			screen.level(1)
		end
		screen.move(i * 10,63)
		screen.text_center(interval_names[i])
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
		midi = App.midi_grid.device,
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
	
	local AllClips = require('Foobar/components/mode/allclips') 
	local SeqClip = require('Foobar/components/mode/seqclip') 
	local SeqGrid = require('Foobar/components/mode/seqgrid') 
	local ScaleGrid = require('Foobar/components/mode/scalegrid') 
	local MuteGrid = require('Foobar/components/mode/mutegrid') 
	local NoteGrid = require('Foobar/components/mode/notegrid')
	local PresetGrid = require('Foobar/components/mode/presetgrid')
	local PresetSeq = require('Foobar/components/mode/presetseq')
	
	local SessionMode = {
		presetseq = PresetSeq:new({track=1}),
		mutegrid = MuteGrid:new({track=1}),
		notegrid = NoteGrid:new({track=1}),
		presetgrid = PresetGrid:new({
			track=1,
			param_type = 'track',
            param_ids = function() return {App.current_track} end,
		})
	}

	self.mode[1] = Mode:new({
		id = 1,
		components = {
			SessionMode.presetseq,
			MuteGrid:new({track=1}),
			SessionMode.presetgrid
		},
		on_load = function(s,data)
		 	s.row_pads.led[9][8] = 1
			s.row_pads:refresh()
			 App.screen_dirty = true
		end,
		on_row = function(s,data)
			local presetseq = s.components[1]
			local presetgrid = s.components[3]
			
			presetseq:on_row(data, true)
			presetgrid:on_row(data)

			for i = 2, 8 do
				s.row_pads.led[9][i] = 0
			end
		
			s.row_pads.led[9][9 - data.row] = 1
			s.row_pads:refresh()
		end,
		
	})

	self.mode[5] = Mode:new({
		id = 1,
		components = {
			SessionMode.presetseq,
			SessionMode.mutegrid,
			SessionMode.notegrid
		},
		on_load = function(s,data)
		 	s.row_pads.led[9][8] = 1
			s.row_pads:refresh()
			 App.screen_dirty = true
		end,
		on_row = function(s,data)
			local presetseq = s.components[1]
			local notegrid = s.components[3]
			
			presetseq:on_row(data, true)
			notegrid:on_row(data)

			for i = 2, 8 do
				s.row_pads.led[9][i] = 0
			end
		
			s.row_pads.led[9][9 - data.row] = 1
			s.row_pads:refresh()
			
		end
		
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
			ScaleGrid:new({id=3, offset = {x=0,y=2}}),
			PresetGrid:new({
				id = 2,
				track=1,
				grid_start = {x=1,y=2},
				grid_end = {x=8,y=1},
				display_start = {x=1,y=1},
				display_end = {x=8,y=2},
				offset = {x=0,y=0},
				param_list={
					'scale_1_bits',
					'scale_1_root',
					'scale_2_bits',
					'scale_2_root',
					'scale_3_bits',
					'scale_3_root',
				}
			})
		},
		on_load = function() App.screen_dirty = true end,
		on_row = function(s,data)
			if data.row < 7 then
				local scalegrid = s.components[math.ceil(data.row/2)]
				scalegrid:on_row(data)
			end
		end,
		context = {
			enc1 = function(d)
				params:set('scale_1_root',App.scale[1].root + d)
				App.screen_dirty = true
			end,
			alt_enc1 = function(d)
				App.scale[1]:shift_scale_to_note(App.scale[1].root + d)
				App.screen_dirty = true
			end,

		}

	})

	self.mode[4] = Mode:new({
		id = 4,
		components = {
		-- SeqClip:new({ track = 1, offset = {x=0,y=7}, active = true  }),
		-- SeqClip:new({ track = 2, offset = {x=0,y=6} }),
		-- SeqClip:new({ track = 3, offset = {x=0,y=5} }),
		-- SeqClip:new({ track = 4, offset = {x=0,y=4} }),
		-- SeqClip:new({ track = 5, offset = {x=0,y=3} }),
		-- SeqClip:new({ track = 6, offset = {x=0,y=2} }),
		-- SeqClip:new({ track = 7, offset = {x=0,y=1} }),
		-- SeqClip:new({ track = 8, offset = {x=0,y=0} })
		}
	})

	-- self.mode[1]:disable() --clear out the old junk
	self.mode[1]:enable()
end

return App