local path_name = 'Foobar/lib/'
local musicutil = require(path_name .. 'musicutil-extended')
local ModeComponent = require(path_name .. 'components/mode/modecomponent')
local UI = require(path_name .. 'ui')
local Registry = require(path_name .. 'utilities/registry')
local textentry = require('textentry')
local Input = require(path_name .. 'components/track/input')

--[[
Default Mode Component

This component implements the default mode for the application, providing the main menu and
default menus for components. Registered as a mode component.

Key Functions:
- enable_event: Activates the default mode and sets up the initial context and screen.
- default_context: Returns the default context table, including menu and navigation handlers.
- sub_menu: Handles transitions to sub-menus and manages returning to the previous context.
- default_menu: Constructs the status .
- track_menu: Constructs the menu for the current track, including MIDI input/output, type, and scale selection.
- scale_menu: Constructs the scale menu for a given scale id.
- input_menu: Constructs the input type menu for the current track.
- default_screen: Returns a function that draws the default screen for the mode.
]]

local Default = ModeComponent:new({})
local menu_style = { inactive_color = 15 }

--[[
  Function: enable_event
  Purpose: Activates the default mode and sets up the initial context and screen.
]]
function Default:enable_event()
	local context = self:default_context()
	local screen = self:default_screen()
	local options = { timeout = false }

	if not self.mode.default_menu then options.set_default = true end

	self.current = { context = context, screen = screen, options = options }
	self.mode:use_context(context, screen, options)
end

-- Build an Output submenu based on current output type
function Default:output_menu()
	local tid = App.current_track
	local items = {}

	local device_item = Registry.menu.make_item('track_' .. tid .. '_device_out', {
		label_fn = function() return 'DEVICE' end,
		helper_labels = {
			enc3 = 'Select device',
		},
	})

	local midi_out_item = Registry.menu.make_item('track_' .. tid .. '_midi_out', {
		label_fn = function() return 'MIDI OUT' end,
		helper_labels = {
			enc3 = 'Select port',
		},
		can_show = function() return App.track[tid].output_type ~= 'crow' end,
	})

	local crow_out_item = Registry.menu.make_item('track_' .. tid .. '_crow_out', {
		label_fn = function() return 'CROW OUT' end,
		helper_labels = {
			enc3 = 'Select output',
		},
		can_show = function() return App.track[tid].output_type == 'crow' end,
	})

	local slew_item = Registry.menu.make_item('track_' .. tid .. '_slew', {
		label_fn = function() return 'SLEW' end,
		helper_labels = {
			enc3 = 'Adjust slew',
		},
		can_show = function() return App.track[tid].output_type == 'crow' end,
	})

	table.insert(items, device_item)
	table.insert(items, midi_out_item)
	table.insert(items, crow_out_item)
	table.insert(items, slew_item)

	return items
end

-- Input settings submenu for device/channel
function Default:input_settings_menu()
	local tid = App.current_track
	local items = {}

	table.insert(
		items,
		Registry.menu.make_item('track_' .. tid .. '_device_in', {
			label_fn = function() return 'DEVICE' end,
			helper_labels = {
				enc3 = 'Select device',
			},
		})
	)

	table.insert(
		items,
		Registry.menu.make_item('track_' .. tid .. '_midi_in', {
			label_fn = function() return 'MIDI IN' end,
			helper_labels = {
				enc3 = 'Select channel',
			},
		})
	)

	table.insert(
		items,
		Registry.menu.make_item('track_' .. tid .. '_voice', {
			label_fn = function() return 'VOICE' end,
			helper_labels = {
				enc3 = 'Select voice',
			},
		})
	)

	return items
end

--[[
  Function: default_context
  Purpose: Returns the default context table, including menu and navigation handlers.
]]
function Default:default_context()
	local ctx = {
		cursor = self.mode.cursor or 1,
		menu = self:default_menu(),
		enc1 = function(d)
			local total_tracks = (#App.track and #App.track > 0) and #App.track or 8
			local next_track = util.clamp(App.current_track + d, 1, total_tracks)
			if next_track ~= App.current_track then
				App.current_track = next_track
				-- rebuild context/menu so closures reference the new track
				local screen = (self.current and self.current.screen) or self:default_screen()
				local options = { timeout = false, menu_override = true, cursor = 1 }
				local next_context = self:default_context()
				self.current = { context = next_context, screen = screen, options = options }
				self.mode:use_context(next_context, screen, options)
				App.screen_dirty = true
			end
		end,
		press_fn_3 = function()
			local config = {
				status = { icon = App.current_track, label = App.track[App.current_track].name },
				options = { timeout = false },
				screen = self:submenu_screen(),
			}
			self:sub_menu(self:track_menu(), config)
		end,
		disable_highlight = true,
	}
	return ctx
end

-- Screen used for sub-menus (small tempo)
function Default:submenu_screen()
	return function()
		screen.clear()
		UI:draw_small_tempo()
		UI:draw_chord(1, 80, 45)
		UI:draw_chord_small(2)
		if self.current and self.current.status then
			UI:draw_status(self.current.status.icon, self.current.status.label)
		else
			UI:draw_status()
		end
		UI:draw_menu(0, 20, self.mode.menu, self.mode.cursor, { disable_highlight = self.mode.disable_highlight })
	end
end

--[[
Default Mode Component

This component implements the default mode for the application, providing the main menu and context handling for the user interface. It defines the default context, screen, and menu for the mode, and manages transitions to sub-menus (such as the track menu). The default context includes navigation and menu item selection logic, while the default menu displays basic track MIDI input/output information.

Key Functions:
- enable_event: 
- default_context: Returns the default context table, including menu and navigation handlers.
- sub_menu: 
- default_menu: Constructs the default menu items for the current track.

This component is intended to be registered as a mode component within the application's mode system.
]]

--[[
  Function: sub_menu
  Purpose: Handles transitions to sub-menus and manages returning to the previous context.
  Parameters:
    menu (table): The menu items for the sub-menu.
    config (table): Optional configuration for the sub-menu (status, options, screen).
]]
function Default:sub_menu(menu, config)
	config = config or {}
	local previous = self.current

	local setPrevious = function()
		self.current = previous
		self.mode:use_context(previous.context, previous.screen, previous.options)
	end

	self.current = {}

	self.current.context = {
		press_fn_2 = setPrevious,
		menu = menu,
	}

	if config.default_helper_labels then self.current.context.default_helper_labels = config.default_helper_labels end

	if config.status then self.current.status = config.status end

	if config.options then
		self.current.options = config.options
	else
		self.current.options = { timeout = false, callback = setPrevious }
	end

	if not self.current.options.callback then self.current.options.callback = setPrevious end

	if config.screen then
		self.current.screen = config.screen
	else
		self.current.screen = previous.screen
	end

	self.mode:use_context(self.current.context, self.current.screen, self.current.options)
end

--[[
  Function: default_menu
  Purpose: Constructs the default menu items for the current track, showing MIDI input/output.
  Returns: (table) List of menu items.
]]
function Default:default_menu()
	local id = App.current_track
	local style = { inactive_color = 15, icon_inactive_color = 5, width = 80 }
	local items = {
		Registry.menu.make_item('track_' .. id .. '_midi_in', { disable = true, icon = '\u{2192}', label_fn = function() return App.track[id].input_device.abbr end, style = style }),
		Registry.menu.make_item('track_' .. id .. '_midi_out', { disable = true, icon = '\u{2190}', label_fn = function() return App.track[id].output_device.abbr end, style = style }),
	}
	return items
end

--[[
  Function: track_menu
  Purpose: Constructs the menu for the current track, including MIDI input/output, type, and scale selection.
  Returns: (table) List of menu items for the track menu.
]]
function Default:track_menu()
	local id = App.current_track

	local in_row = Registry.menu.make_combo('track_' .. id .. '_device_in', 'track_' .. id .. '_midi_in', {
		icon = '\u{2192}',
		left_label_fn = function() return App.track[id].input_device.abbr end,
		on_press = function()
			self:sub_menu(self:input_settings_menu(), {
				status = { icon = id, label = 'INPUT' },
				screen = self:submenu_screen(),
			})
		end,
		helper_labels = {
			press_fn_3 = '>',
			enc2 = 'Dev',
			enc3 = 'Ch',
		},
	})

	local out_row = Registry.menu.make_combo('track_' .. id .. '_device_out', 'track_' .. id .. '_midi_out', {
		icon = '\u{2190}',
		left_label_fn = function()
			if App.track[id].output_type == 'crow' then
				return 'Crow'
			else
				return App.track[id].output_device.abbr
			end
		end,
		right_value_fn = function()
			if App.track[id].output_type == 'crow' then
				return Registry.menu.format_value('track_' .. id .. '_crow_out')
			else
				return Registry.menu.format_value('track_' .. id .. '_midi_out')
			end
		end,
		enc3 = function(d)
			if App.track[id].output_type == 'crow' then
				Registry.menu.bump('track_' .. id .. '_crow_out', d)
			else
				Registry.menu.bump('track_' .. id .. '_midi_out', d)
			end
		end,
		on_press = function()
			self:sub_menu(self:output_menu(), {
				status = { icon = id, label = 'OUTPUT' },
				screen = self:submenu_screen(),
			})
		end,
		helper_labels = {
			press_fn_3 = '>',
			enc2 = 'Dev',
			enc3 = 'Dest',
		},
	})

	local type_row = Registry.menu.make_item('track_' .. id .. '_input_type', {
		label_fn = function() return 'TYPE' end,
		encoder = 3,
		can_press = function() return App.track[id].input_type ~= 'midi' end,
		on_press = function()
			if App.track[id].input_type ~= 'midi' then self:sub_menu(self:input_menu(), {
				status = { icon = id, label = App.track[id].input_type },
				screen = self:submenu_screen(),
			}) end
		end,
		helper_labels = {
			press_fn_3 = '>',
			enc3 = 'Type',
		},
	})

	local scale_row = Registry.menu.make_item('track_' .. id .. '_scale_select', {
		label_fn = function() return 'SCALE' end,
		encoder = 3,
		can_press = function()
			local sid = params:get('track_' .. id .. '_scale_select')
			return sid > 0
		end,
		on_press = function()
			local sid = params:get('track_' .. id .. '_scale_select')

			if sid > 0 then self:sub_menu(self:scale_menu(), {
				status = { icon = '\u{266a}', label = 'Scale ' .. sid },
				screen = self:submenu_screen(),
			}) end
		end,
		helper_labels = {
			press_fn_3 = '>',
			enc3 = 'Scale',
		},
	})

	local items = { in_row, out_row, type_row, scale_row }

	-- Additional track parameters (excluding note_range_upper)
	local function add(id_suffix, opts)
		opts = opts or {}
		table.insert(items, Registry.menu.make_item('track_' .. id .. '_' .. id_suffix, opts))
	end

	-- Track name editing via textentry (no encoder adjustment)
	table.insert(
		items,
		Registry.menu.make_item('track_' .. id .. '_name', {
			label_fn = function() return 'EDIT NAME' end,
			value_fn = function() return '' end,
			disable = true,
			on_press = function()
				local current = App.track[id].name or ''
				textentry.enter(function(txt)
					if txt ~= nil and txt ~= '' then Registry.set('track_' .. id .. '_name', txt, 'textentry') end
					App.screen_dirty = true
				end, current, 'Track name')
			end,
			helper_labels = {
				press_fn_3 = 'sel',
			},
		})
	)
	-- Removed OUTPUT type from Track menu; device selection + dynamic right side covers this
	-- Mixer toggle labeled as USE MIXER with yes/no
	table.insert(
		items,
		Registry.menu.make_item('track_' .. id .. '_mixer', {
			label_fn = function() return 'USE MIXER' end,
			value_fn = function()
				local v = params:get('track_' .. id .. '_mixer')
				return (v > 0) and 'yes' or 'no'
			end,
		})
	)
	-- step/reset_step are shown in Input menus for applicable types, not here
	add('program_change', {
		label_fn = function() return 'PROGRAM' end,
		requires_confirmation = true,
	})
	-- VOICE moved under MIDI input type menu

	return items
end

--[[
  Function: scale_menu
  Purpose: Constructs the scale menu for a given scale id.
  Parameters:
    sid (number): The scale id to construct the menu for.
  Returns: (table) List of menu items for the scale menu.
]]
function Default:scale_menu(sid)
	local tid = App.current_track
	sid = sid or App.track[tid].scale_select or 0
	local root = (App.scale[sid].root + 1) % 12 - 1
	local octave = math.floor(App.scale[sid].root / 12)

	local items = {
		-- Root selection remains available
		Registry.menu.make_item('scale_' .. sid .. '_root', {
			label_fn = function() return 'ROOT' end,
			value_fn = function() return musicutil.note_num_to_name(root) end,
			enc3 = function(d)
				root = util.wrap(d + root, 0, 12)
				Registry.set('scale_' .. sid .. '_root', root + octave * 12, 'scale_root_nav')
			end,
		}),

		-- Scale selection via param (no bit stepping UI)
		Registry.menu.make_item('track_' .. tid .. '_scale_select', {
			icon = '\u{266a}',
			label_fn = function() return 'SCALE' end,
			value_fn = function()
				local cur = params:get('track_' .. tid .. '_scale_select')
				local label = 'OFF'
				if cur > 0 and App.scale[cur] and App.scale[cur].name then
					label = App.scale[cur].name
				elseif cur > 0 then
					label = 'Scale ' .. cur
				end
				return label
			end,
		}),

		Registry.menu.make_item('scale_' .. sid .. '_follow', { label_fn = function() return 'FOLLOW' end }),
		Registry.menu.make_item('scale_' .. sid .. '_follow_method', { label_fn = function() return 'METHOD' end }),
		Registry.menu.make_item('scale_' .. sid .. '_chord_set', { label_fn = function() return 'CHORDS' end }),
	}

	return items
end

--[[
  Function: input_menu
  Purpose: Constructs the input type menu for the current track.
  Returns: (table) List of menu items for the input type menu.
]]
function Default:input_menu()
	local tid = App.current_track
	local t = App.track[tid]
	local itype = t.input_type
	local def = Input.types[itype] or { props = {} }

	local items = {}
	for _, prop in ipairs(def.props) do
		local pid = 'track_' .. tid .. '_' .. prop
		table.insert(items, Registry.menu.make_item(pid, { icon = '' }))
	end

	return items
end

--[[
  Function: default_screen
  Purpose: Returns a function that draws the default screen for the mode.
  Returns: (function) The screen drawing function.
]]
function Default:default_screen()
	return function()
		UI:draw_tempo()
		UI:draw_chord(1, 80, 45)
		UI:draw_chord_small(2)
		if self.current.status then
			UI:draw_status(self.current.status.icon, self.current.status.label)
		else
			UI:draw_status()
		end
		UI:draw_menu(0, 20, self.mode.menu, self.mode.cursor, { disable_highlight = self.mode.disable_highlight })
	end
end

return Default
