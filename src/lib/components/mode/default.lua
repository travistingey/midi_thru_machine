local path_name = 'Foobar/lib/'
local musicutil = require(path_name .. 'musicutil-extended')
local ModeComponent = require(path_name .. 'components/mode/modecomponent')
local UI = require(path_name .. 'ui')
local Registry = require(path_name .. 'utilities/registry')
local textentry = require('textentry')
local Input = require(path_name .. 'components/track/input')
local TimingConstants = require(path_name .. 'utilities/timing_constants')
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
Default.name = 'default'
local menu_style = { inactive_color = 15 }
local max_clip_slot_select = 32
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
			enc3 = 'select device',
		},
	})

	local midi_out_item = Registry.menu.make_item('track_' .. tid .. '_midi_out', {
		label_fn = function() return 'MIDI OUT' end,
		helper_labels = {
			enc3 = 'select channel',
		},
		can_show = function() return App.track[tid].output_type ~= 'crow' end,
	})

	local crow_out_item = Registry.menu.make_item('track_' .. tid .. '_crow_out', {
		label_fn = function() return 'CROW OUT' end,
		helper_labels = {
			enc3 = 'select output',
		},
		can_show = function() return App.track[tid].output_type == 'crow' end,
	})

	local slew_item = Registry.menu.make_item('track_' .. tid .. '_slew', {
		label_fn = function() return 'SLEW' end,
		helper_labels = {
			enc3 = 'adjust slew',
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
				enc3 = 'select device',
			},
		})
	)

	table.insert(
		items,
		Registry.menu.make_item('track_' .. tid .. '_midi_in', {
			label_fn = function() return 'MIDI IN' end,
			helper_labels = {
				enc3 = 'select channel',
			},
		})
	)

	table.insert(
		items,
		Registry.menu.make_item('track_' .. tid .. '_voice', {
			label_fn = function() return 'VOICE' end,
			helper_labels = {
				enc3 = 'select voice',
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
	local prev_cursor = self.mode and self.mode.cursor or 1

	local setPrevious = function()
		-- Restore prior cursor position when backing out of submenu
		previous.options = previous.options or {}
		previous.options.cursor = prev_cursor
		self.current = previous
		self.mode:use_context(previous.context, previous.screen, previous.options)
	end

	self.current = {}

	self.current.context = {
		press_fn_2 = setPrevious,
		menu = menu,
	}

	-- Always provide a default "back" helper label for press_fn_2
	local existing_labels = config.default_helper_labels
	self.current.context.default_helper_labels = function()
		local merged = {}
		if type(existing_labels) == 'function' then
			local ok, res = pcall(existing_labels)
			if ok and type(res) == 'table' then
				for k, v in pairs(res) do
					merged[k] = v
				end
			end
		elseif type(existing_labels) == 'table' then
			for k, v in pairs(existing_labels) do
				merged[k] = v
			end
		end
		if merged.press_fn_2 == nil then merged.press_fn_2 = '\u{21ba}' end
		return merged
	end

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
		requires_confirmation = true,
		has_submenu = true,
		left_label_fn = function() return Registry.menu.format_value('track_' .. id .. '_device_in') end,
		on_press = function()
			self:sub_menu(self:input_settings_menu(), {
				status = { icon = id, label = 'Input' },
				screen = self:submenu_screen(),
			})
		end,
		alt_fn_3 = function() Registry.set('track_' .. id .. '_device_swap_trigger', 1, 'menu_swap') end,
		helper_labels = {
			enc1 = 'device',
			enc3 = 'channel',
			alt_fn_3 = 'swap',
		},
	})

	local out_row = Registry.menu.make_combo('track_' .. id .. '_device_out', 'track_' .. id .. '_midi_out', {
		icon = '\u{2190}',
		requires_confirmation = true,
		has_submenu = true,
		left_label_fn = function() return Registry.menu.format_value('track_' .. id .. '_device_out') end,
		right_value_fn = function()
			if App.track[id].output_type == 'crow' then
				return Registry.menu.format_value('track_' .. id .. '_crow_out')
			else
				return Registry.menu.format_value('track_' .. id .. '_midi_out')
			end
		end,
		on_press = function()
			self:sub_menu(self:output_menu(), {
				status = { icon = id, label = 'OUTPUT' },
				screen = self:submenu_screen(),
			})
		end,
		alt_fn_3 = function() Registry.set('track_' .. id .. '_device_swap_trigger', 1, 'menu_swap') end,
		helper_labels = {
			enc1 = 'device',
			enc3 = 'channel',
			alt_fn_3 = 'swap',
		},
	})

	local type_row = Registry.menu.make_item('track_' .. id .. '_input_type', {
		requires_confirmation = true,
		label_fn = function() return 'TYPE' end,
		can_press = function() return App.track[id].input_type ~= 'midi' end,
		has_submenu = function() return App.track[id].input_type ~= 'midi' end,
		on_press = function()
			if App.track[id].input_type ~= 'midi' then self:sub_menu(self:input_menu(), {
				status = { icon = id, label = App.track[id].input_type },
				screen = self:submenu_screen(),
			}) end
		end,
	})

	local scale_row = Registry.menu.make_item('track_' .. id .. '_scale_select', {
		requires_confirmation = true,

		label_fn = function() return 'SCALE' end,
		can_press = function()
			local sid = params:get('track_' .. id .. '_scale_select')
			return sid > 0
		end,
		has_submenu = function()
			local sid = params:get('track_' .. id .. '_scale_select')
			return sid > 0 and true or false
		end,
		on_press = function()
			local sid = params:get('track_' .. id .. '_scale_select')

			if sid > 0 then self:sub_menu(self:scale_menu(), {
				status = { icon = '\u{266a}', label = 'scale ' .. sid },
				screen = self:submenu_screen(),
			}) end
		end,
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
				press_fn_3 = 'edit',
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

	-- step/reset_step_count are shown in Input menus for applicable types, not here
	add('program_change', {
		label_fn = function() return 'PROGRAM CHANGE' end,
		requires_confirmation = true,
	})
	-- VOICE moved under MIDI input type menu

	-- Clip testing submenu
	table.insert(
		items,
		Registry.menu.make_item('clip_test', {
			label_fn = function() return 'CLIP' end,
			value_fn = function()
				local track = App.track[id]
				if track and track.clip then
					if track.clip.current_slot then
						return 'slot ' .. track.clip.current_slot
					else
						return 'live buffer'
					end
				end
				return 'no clip'
			end,
			has_submenu = true,
			on_press = function()
				self:sub_menu(self:clip_menu(), {
					status = { icon = id, label = 'Clips' },
					screen = self:submenu_screen(),
				})
			end,
		})
	)

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
	local function get_root_param() return util.clamp(params:get('scale_' .. sid .. '_root'), -24, 24) end
	local function format_root(val)
		val = util.clamp(val, -24, 24)
		local base = ((val % 12) + 12) % 12
		local octave = math.floor(val / 12)
		local note = musicutil.note_num_to_name(base)
		-- Only show octave when outside 0–12; include negative octaves.
		if val < 0 or val > 12 then return note .. tostring(octave) end
		return note
	end

	local items = {
		-- Root selection remains available
		Registry.menu.make_item('scale_' .. sid .. '_root', {
			label_fn = function() return 'ROOT' end,
			value_fn = function() return format_root(get_root_param()) end,
			enc3 = function(d)
				local pid = 'scale_' .. sid .. '_root'
				local p = params:lookup_param(pid)
				if p then
					local next_val = util.clamp(p:get() + d, p.min or -24, p.max or 24)
					params:set(pid, next_val)
				end
			end,
		}),

		-- Scale selection via param (no bit stepping UI)
		Registry.menu.make_item('scale_' .. sid .. '_bits', {
			icon = '\u{266a}',
			label_fn = function() return 'SCALE' end,
			value_fn = function()
				local cur = params:get('scale_' .. sid .. '_bits')
				local label = 'OFF'
				if cur == 0 then
					label = 'NONE'
				else
					local chord = musicutil.interval_lookup[cur]

					if chord then
						label = chord.name
					else
						label = 'b' .. cur
					end
				end
				return label
			end,
		}),

		Registry.menu.make_item('scale_' .. sid .. '_follow', {
			label_fn = function() return 'FOLLOW' end,
		}),
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
  Function: clip_menu
  Purpose: Constructs a menu for testing clip save/load operations.
  Returns: (table) List of menu items for clip testing.
]]

local function get_clip_status()
	local tid = App.current_track
	local track = App.track[tid]
	if track and track.clip then
		if track.clip.current_slot then return track.clip.current_slot end
		return 'no clip'
	end
end

function Default:clip_menu()
	local tid = App.current_track
	local track = App.track[tid]
	local items = {}
	local clip_status = get_clip_status()

	print('clip_status: ' .. clip_status)

	-- Playback settings submenu
	table.insert(
		items,
		Registry.menu.make_item('clip_playback_settings', {
			label_fn = function() return 'PLAYBACK' end,
			value_fn = function()
				if track and track.clip then
					local clip = track.clip
					-- Check scrub mode first
					if clip.scrub_mode then return 'Scrub' end
					-- Check frozen buffer
					if clip.buffer_frozen then return 'Frozen' end
					-- Check if clip is loaded
					if clip.current_slot then
						local slot = clip.current_slot
						local clip_entry = clip.clip_bank[slot]
						if clip_entry then return 'Slot ' .. slot end
						return 'Slot ' .. slot .. ' (missing)'
					end
					-- Live input
					return 'Live'
				end
				return 'none'
			end,
			has_submenu = true,
			on_press = function()
				self:sub_menu(self:clip_playback_menu(), {
					status = { icon = tid, label = 'Playback' },
					screen = self:submenu_screen(),
				})
			end,
		})
	)

	-- List all bank slots
	table.insert(
		items,
		Registry.menu.make_item('clip_list_slots', {
			label_fn = function() return 'BANK' end,
			value_fn = function()
				if track and track.clip then
					local count = 0
					for slot = 1, max_clip_slot_select do
						if track.clip.clip_bank[slot] then count = count + 1 end
					end
					return count .. ' / ' .. max_clip_slot_select
				end
				return '0 / ' .. max_clip_slot_select
			end,
			disable = true,
		})
	)

	-- Save clip to bank slot
	table.insert(
		items,
		Registry.menu.make_item('clip_save_slot', {
			label_fn = function() return 'SAVE SLOT' end,
			value_fn = function()
				local slot = App.current_clip or 1
				return tostring(slot)
			end,
			enc3 = function(d)
				App.current_clip = util.clamp((App.current_clip or 1) + d, 1, max_clip_slot_select)
				App.screen_dirty = true
			end,
			on_press = function()
				if track and track.clip and track.buffer then
					local slot = App.current_clip or 1
					local loop_start = track.buffer.buffer_start
					local loop_end = track.buffer.buffer_start + track.buffer.buffer_length - 1
					local name = slot
					local success = track.clip:save_clip_to_bank(slot, loop_start, loop_end, name)
					if success then
						print('Saved clip to slot ' .. slot)
					else
						print('Failed to save clip to slot ' .. slot)
					end
					App.screen_dirty = true
				end
			end,
			helper_labels = {
				enc3 = 'select slot',
				press_fn_3 = 'save',
			},
		})
	)

	-- Load clip from bank slot
	table.insert(
		items,
		Registry.menu.make_item('clip_load_slot', {
			label_fn = function() return 'LOAD SLOT' end,
			value_fn = function()
				local slot = App.current_clip or 1
				local track = App.track[tid]
				if track and track.clip and track.clip.clip_bank[slot] then return tostring(slot) .. ' (' .. (track.clip.clip_bank[slot].name or 'unnamed') .. ')' end
				return '(empty)'
			end,
			enc3 = function(d)
				App.current_clip = util.clamp((App.current_clip or 1) + d, 1, max_clip_slot_select)
				App.screen_dirty = true
			end,
			on_press = function()
				if track and track.clip then
					local slot = App.current_clip or 1
					local success = track.clip:load_clip_from_bank(slot)
					if success then
						print('Loaded clip from slot ' .. slot)
					else
						print('Failed to load clip from slot ' .. slot)
					end
					App.screen_dirty = true
				end
			end,
			helper_labels = {
				enc3 = 'select slot',
				press_fn_3 = 'load',
			},
		})
	)

	-- Clear clip slot
	table.insert(
		items,
		Registry.menu.make_item('clip_clear_slot', {
			label_fn = function() return 'CLEAR SLOT' end,
			value_fn = function()
				local slot = App.current_clip or 1
				return tostring(slot)
			end,
			enc3 = function(d)
				App.current_clip = util.clamp((App.current_clip or 1) + d, 1, max_clip_slot_select)
				App.screen_dirty = true
			end,
			on_press = function()
				if track and track.clip then
					local slot = App.current_clip or 1
					local success = track.clip:clear_clip_slot(slot)
					if success then
						print('Cleared clip slot ' .. slot)
					else
						print('Failed to clear clip slot ' .. slot)
					end
					App.screen_dirty = true
				end
			end,
			helper_labels = {
				enc3 = 'select slot',
				press_fn_3 = 'clear',
			},
		})
	)

	-- Clear clip slot
	table.insert(
		items,
		Registry.menu.make_item('clip_clear_all', {
			label_fn = function() return 'CLEAR ALL' end,
			value_fn = function()
				local slot = App.current_clip or 1
				return tostring(slot)
			end,

			on_press = function()
				if track and track.clip then
					for slot = 1, max_clip_slot_select do
						local success = track.clip:clear_clip_slot(slot)
						if success then
							print('Cleared clip slot ' .. slot)
						else
							print('Failed to clear clip slot ' .. slot)
						end
					end
					App.screen_dirty = true
				end
			end,
			helper_labels = {
				press_fn_3 = 'clear',
			},
		})
	)

	-- Unload clip and return to live buffer (also unfreezes frozen buffer)
	table.insert(
		items,
		Registry.menu.make_item('clip_unload', {
			label_fn = function() return 'UNLOAD CLIP' end,
			value_fn = function()
				if track and track.clip then
					if track.clip.current_slot then
						return 'clip loaded'
					elseif track.clip.buffer_frozen then
						return 'buffer frozen'
					end
				end
				return ''
			end,
			can_press = function() return track and track.clip and (track.clip.current_slot ~= nil or track.clip.buffer_frozen) end,
			on_press = function()
				if track and track.clip then
					local success = track.clip:unload_clip()
					if success then
						if track.clip.current_slot then
							print('Unloaded clip, returning to live buffer')
						elseif track.clip.buffer_frozen then
							print('Unfroze buffer, returning to live playback')
						end
					else
						print('No clip to unload or buffer to unfreeze')
					end
					App.screen_dirty = true
				end
			end,
			helper_labels = {
				press_fn_3 = 'unload/unfreeze',
			},
		})
	)

	return items
end

--[[
  Function: edit_menu
  Purpose: Constructs the edit menu for buffer editing operations.
  Parameters:
    bufferseq: Reference to the BufferSeq component with selection state
  Returns: (table) List of menu items for editing operations.
]]
function Default:edit_menu(bufferseq)
	local tid = App.current_track
	local track = App.track[tid]
	local items = {}

	-- Get selection range from bufferseq
	local start_tick, end_tick = nil, nil
	if bufferseq and bufferseq.get_selection then
		start_tick, end_tick = bufferseq:get_selection()
	end

	-- Selection range display (read-only info)
	table.insert(
		items,
		Registry.menu.make_item('edit_selection_range', {
			label_fn = function() return 'RANGE' end,
			value_fn = function()
				if start_tick and end_tick then return TimingConstants.tick_range_to_time_string(start_tick, end_tick) end
				return 'none'
			end,
			disable = true,
		})
	)

	-- Quantize setting
	local quantize_values = {
		{ ticks = App.ppqn / 8, name = '1/32' },
		{ ticks = App.ppqn / 4, name = '1/16' },
		{ ticks = App.ppqn / 2, name = '1/8' },
		{ ticks = App.ppqn, name = '1/4' },
	}
	local quantize_index = 2 -- Default to 1/16

	table.insert(
		items,
		Registry.menu.make_item('edit_quantize', {
			label_fn = function() return 'QUANTIZE' end,
			value_fn = function() return quantize_values[quantize_index].name end,
			enc3 = function(d)
				quantize_index = util.clamp(quantize_index + d, 1, #quantize_values)
				App.screen_dirty = true
			end,
			on_press = function()
				if track and track.buffer and start_tick and end_tick then
					local grid_size = quantize_values[quantize_index].ticks
					local count = track.buffer:quantize(grid_size, start_tick, end_tick + 1)
					self.mode:toast('Quantized ' .. count .. ' events', { timeout = 2 })
					App.screen_dirty = true
				else
					self.mode:toast('No selection', { timeout = 2 })
				end
			end,
			helper_labels = {
				enc3 = 'grid size',
				press_fn_3 = 'apply',
			},
		})
	)

	-- Transpose setting
	local transpose_semitones = 0

	table.insert(
		items,
		Registry.menu.make_item('edit_transpose', {
			label_fn = function() return 'TRANSPOSE' end,
			value_fn = function()
				if transpose_semitones == 0 then
					return '0'
				elseif transpose_semitones > 0 then
					return '+' .. transpose_semitones
				else
					return tostring(transpose_semitones)
				end
			end,
			enc3 = function(d)
				transpose_semitones = util.clamp(transpose_semitones + d, -48, 48)
				App.screen_dirty = true
			end,
			on_press = function()
				if track and track.buffer and start_tick and end_tick and transpose_semitones ~= 0 then
					local count = track.buffer:transpose(transpose_semitones, start_tick, end_tick + 1)
					self.mode:toast('Transposed ' .. count .. ' notes', { timeout = 2 })
					transpose_semitones = 0 -- Reset after applying
					App.screen_dirty = true
				else
					self.mode:toast('No selection or no transpose', { timeout = 2 })
				end
			end,
			helper_labels = {
				enc3 = 'semitones',
				press_fn_3 = 'apply',
			},
		})
	)

	-- Velocity scale setting
	local velocity_percent = 100

	table.insert(
		items,
		Registry.menu.make_item('edit_velocity', {
			label_fn = function() return 'VELOCITY' end,
			value_fn = function() return velocity_percent .. '%' end,
			enc3 = function(d)
				velocity_percent = util.clamp(velocity_percent + d * 5, 10, 200)
				App.screen_dirty = true
			end,
			on_press = function()
				if track and track.buffer and start_tick and end_tick and velocity_percent ~= 100 then
					local factor = velocity_percent / 100
					local count = track.buffer:scale_velocity(factor, start_tick, end_tick + 1)
					self.mode:toast('Scaled ' .. count .. ' velocities', { timeout = 2 })
					velocity_percent = 100 -- Reset after applying
					App.screen_dirty = true
				else
					self.mode:toast('No selection or 100%', { timeout = 2 })
				end
			end,
			helper_labels = {
				enc3 = 'scale %',
				press_fn_3 = 'apply',
			},
		})
	)

	-- Shift events forward/backward
	local shift_amount = 0 -- in 32nd notes

	table.insert(
		items,
		Registry.menu.make_item('edit_shift', {
			label_fn = function() return 'SHIFT' end,
			value_fn = function()
				if shift_amount == 0 then
					return '0'
				else
					local ticks = shift_amount * (App.ppqn / 8)
					return (shift_amount > 0 and '+' or '') .. shift_amount .. ' (32nds)'
				end
			end,
			enc3 = function(d)
				shift_amount = util.clamp(shift_amount + d, -64, 64)
				App.screen_dirty = true
			end,
			on_press = function()
				if track and track.buffer and start_tick and end_tick and shift_amount ~= 0 then
					local ticks = shift_amount * (App.ppqn / 8)
					local count = track.buffer:shift_events(start_tick, ticks)
					self.mode:toast('Shifted ' .. count .. ' events', { timeout = 2 })
					shift_amount = 0 -- Reset after applying
					App.screen_dirty = true
				else
					self.mode:toast('No selection or no shift', { timeout = 2 })
				end
			end,
			helper_labels = {
				enc3 = '32nd notes',
				press_fn_3 = 'apply',
			},
		})
	)

	-- Delete events in range
	table.insert(
		items,
		Registry.menu.make_item('edit_delete', {
			label_fn = function() return 'DELETE' end,
			value_fn = function()
				if start_tick and end_tick then return 'events in range' end
				return ''
			end,
			can_press = function() return start_tick and end_tick end,
			on_press = function()
				if track and track.buffer and start_tick and end_tick then
					local count = track.buffer:clear_buffer_range(start_tick, end_tick)
					self.mode:toast('Deleted events', { timeout = 2 })
					App.screen_dirty = true
				else
					self.mode:toast('No selection', { timeout = 2 })
				end
			end,
			helper_labels = {
				press_fn_3 = 'delete',
			},
		})
	)

	-- Save selection to clip bank
	table.insert(
		items,
		Registry.menu.make_item('edit_save_to_clip', {
			label_fn = function() return 'SAVE TO CLIP' end,
			value_fn = function()
				local slot = App.current_clip or 1
				return 'slot ' .. slot
			end,
			enc3 = function(d)
				App.current_clip = util.clamp((App.current_clip or 1) + d, 1, max_clip_slot_select)
				App.screen_dirty = true
			end,
			can_press = function() return start_tick and end_tick end,
			on_press = function()
				if track and track.clip and start_tick and end_tick then
					local slot = App.current_clip or 1
					local success = track.clip:save_clip_to_bank(slot, start_tick, end_tick, 'Clip ' .. slot)
					if success then
						self.mode:toast('Saved to slot ' .. slot, { timeout = 2 })
					else
						self.mode:toast('Save failed', { timeout = 2 })
					end
					App.screen_dirty = true
				else
					self.mode:toast('No selection', { timeout = 2 })
				end
			end,
			helper_labels = {
				enc3 = 'select slot',
				press_fn_3 = 'save',
			},
		})
	)

	-- Clear selection
	table.insert(
		items,
		Registry.menu.make_item('edit_clear_selection', {
			label_fn = function() return 'CLEAR SEL' end,
			value_fn = function() return '' end,
			on_press = function()
				if bufferseq and bufferseq.clear_selection then
					bufferseq:clear_selection()
					self.mode:toast('Selection cleared', { timeout = 1.5 })
				end
				-- Return to previous menu
				if self.current and self.current.options and self.current.options.callback then self.current.options.callback() end
			end,
			helper_labels = {
				press_fn_3 = 'clear',
			},
		})
	)

	return items
end

--[[
  Function: clip_playback_menu
  Purpose: Constructs the clip playback settings submenu.
  Returns: (table) List of menu items for playback settings.
]]
function Default:clip_playback_menu()
	local tid = App.current_track
	local track = App.track[tid]
	local items = {}

	if not track or not track.clip then return items end

	local clip = track.clip

	-- Playback mode (where to inject playback events)
	local playback_modes = { 'Input', 'Scale', 'Output', 'Direct' }
	table.insert(
		items,
		Registry.menu.make_item('clip_playback_mode', {
			label_fn = function() return 'MODE' end,
			value_fn = function() return playback_modes[clip.playback_mode] or 'Input' end,
			enc3 = function(d)
				clip.playback_mode = util.clamp(clip.playback_mode + d, 1, #playback_modes)
				App.screen_dirty = true
			end,
			helper_labels = {
				enc3 = 'select mode',
			},
		})
	)

	-- Loop mode (continuous vs one-shot)
	table.insert(
		items,
		Registry.menu.make_item('clip_loop_mode', {
			label_fn = function() return 'LOOP' end,
			value_fn = function() return clip.buffer_loop and 'on' or 'off' end,
			enc3 = function(d)
				if d ~= 0 then clip.buffer_loop = not clip.buffer_loop end
				App.screen_dirty = true
			end,
			helper_labels = {
				enc3 = 'toggle',
			},
		})
	)

	-- Sync length (action sync for clip operations)
	local sync_options = {
		{ value = nil, name = 'off' },
		{ value = App.ppqn / 4, name = '1/16' },
		{ value = App.ppqn / 2, name = '1/8' },
		{ value = App.ppqn, name = '1/4' },
		{ value = App.ppqn * 2, name = '1/2' },
		{ value = App.ppqn * 4, name = '1 bar' },
		{ value = App.ppqn * 8, name = '2 bars' },
		{ value = App.ppqn * 16, name = '4 bars' },
	}

	local function get_sync_index()
		for i, opt in ipairs(sync_options) do
			if opt.value == clip.action_sync_length then return i end
		end
		return 1
	end

	table.insert(
		items,
		Registry.menu.make_item('clip_sync_length', {
			label_fn = function() return 'SYNC' end,
			value_fn = function() return sync_options[get_sync_index()].name end,
			enc3 = function(d)
				local idx = util.clamp(get_sync_index() + d, 1, #sync_options)
				clip.action_sync_length = sync_options[idx].value
				App.screen_dirty = true
			end,
			helper_labels = {
				enc3 = 'sync length',
			},
		})
	)

	-- Playback start (if frozen or clip loaded)
	table.insert(
		items,
		Registry.menu.make_item('clip_playback_start', {
			label_fn = function() return 'START' end,
			value_fn = function()
				local start = clip:get_playback_start()
				return TimingConstants.tick_to_time_string(start)
			end,
			disable = true,
		})
	)

	-- Playback length
	table.insert(
		items,
		Registry.menu.make_item('clip_playback_length', {
			label_fn = function() return 'LENGTH' end,
			value_fn = function()
				local length = clip:get_playback_length()
				local bars = length / (App.ppqn * 4)
				if bars >= 1 then
					return string.format('%.1f bars', bars)
				else
					return length .. ' ticks'
				end
			end,
			disable = true,
		})
	)

	-- Current position
	table.insert(
		items,
		Registry.menu.make_item('clip_position', {
			label_fn = function() return 'POSITION' end,
			value_fn = function()
				if clip.scrub_mode and clip.scrub_tick then
					return TimingConstants.tick_to_time_string(clip.scrub_tick) .. ' (scrub)'
				else
					return TimingConstants.tick_to_time_string(clip.tick)
				end
			end,
			disable = true,
		})
	)

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

		if self.current.status then
			UI:draw_status(self.current.status.icon, self.current.status.label)
		else
			UI:draw_status()
		end
		UI:draw_menu(0, 20, self.mode.menu, self.mode.cursor, { disable_highlight = self.mode.disable_highlight })
	end
end

return Default
