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
						return 'none'
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

	-- Show current playback status
	table.insert(
		items,
		Registry.menu.make_item('clip_status', {
			label_fn = function() return 'PLAYBACK' end,
			value_fn = function()
				if track and track.clip then
					local clip = track.clip
					-- Check scrub mode first
					if clip.active_source == clip.sources.scrub then return 'Scrub' end
					-- Check frozen buffer
					if clip.buffer_frozen then return 'Frozen' end
					-- Check if clip is loaded
					if clip.current_slot then
						local slot = clip.current_slot
						local clip_entry = clip.clip_bank[slot]
						if clip_entry then return 'Slot ' .. slot .. ' (' .. (clip_entry.name or 'unnamed') .. ')' end
						return 'Slot ' .. slot .. ' (missing)'
					end
					-- Live input
					return 'Live'
				end
				return 'none'
			end,
			disable = true,
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

	-- Edit submenu (shown when frozen or clip loaded)
	if track and track.clip and (track.clip.buffer_frozen or track.clip.current_slot) then
		table.insert(
			items,
			Registry.menu.make_item('clip_edit', {
				label_fn = function() return 'EDIT' end,
				value_fn = function()
					if track and track.clip then
						if track.clip.buffer_frozen and track.clip.current_slot then
							return 'editing'
						elseif track.clip.buffer_frozen then
							return 'frozen'
						elseif track.clip.current_slot then
							return 'clip'
						end
					end
					return ''
				end,
				has_submenu = true,
				on_press = function()
					if track and track.clip then
						self:sub_menu(self:clip_edit_menu(), {
							status = { icon = '\u{270e}', label = 'EDIT' },
							screen = self:submenu_screen(),
						})
					end
				end,
			})
		)
	end

	-- Revert edits (only when dirty: frozen from clip)
	if track and track.clip and track.clip.buffer_frozen and track.clip.current_slot then
		table.insert(
			items,
			Registry.menu.make_item('clip_revert', {
				label_fn = function() return 'REVERT' end,
				value_fn = function()
					if track and track.clip and track.clip.current_slot then
						return 'to slot ' .. track.clip.current_slot
					end
					return ''
				end,
				can_press = function() return track and track.clip and track.clip.buffer_frozen and track.clip.current_slot ~= nil end,
				on_press = function()
					if track and track.clip then
						local success = track.clip:revert_edits()
						if success then
							print('Reverted edits, resuming from clip')
						else
							print('Failed to revert edits')
						end
						App.screen_dirty = true
					end
				end,
				helper_labels = {
					press_fn_3 = 'revert',
				},
			})
		)
	end

	-- Save edits to current slot (only when dirty)
	if track and track.clip and track.clip.buffer_frozen and track.clip.current_slot then
		table.insert(
			items,
			Registry.menu.make_item('clip_save_edits', {
				label_fn = function() return 'SAVE' end,
				value_fn = function()
					if track and track.clip and track.clip.current_slot then
						return 'slot ' .. track.clip.current_slot
					end
					return ''
				end,
				can_press = function() return track and track.clip and track.clip.buffer_frozen and track.clip.current_slot ~= nil end,
				on_press = function()
					if track and track.clip then
						local success = track.clip:save_edits_to_current_slot()
						if success then
							print('Saved edits to slot ' .. track.clip.current_slot)
						else
							print('Failed to save edits')
						end
						App.screen_dirty = true
					end
				end,
				helper_labels = {
					press_fn_3 = 'save',
				},
			})
		)
	end

	-- Save edits as new slot (only when dirty)
	if track and track.clip and track.clip.buffer_frozen and track.clip.current_slot then
		table.insert(
			items,
			Registry.menu.make_item('clip_save_as', {
				label_fn = function() return 'SAVE AS' end,
				value_fn = function()
					local slot = App.current_clip or 1
					return tostring(slot)
				end,
				enc3 = function(d)
					App.current_clip = util.clamp((App.current_clip or 1) + d, 1, max_clip_slot_select)
					App.screen_dirty = true
				end,
				can_press = function() return track and track.clip and track.clip.buffer_frozen and track.clip.current_slot ~= nil end,
				on_press = function()
					if track and track.clip then
						local slot = App.current_clip or 1
						local success = track.clip:save_edits_as(slot)
						if success then
							print('Saved edits as slot ' .. slot)
						else
							print('Failed to save edits as slot ' .. slot)
						end
						App.screen_dirty = true
					end
				end,
				helper_labels = {
					enc3 = 'select slot',
					press_fn_3 = 'save as',
				},
			})
		)
	end

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

-- Edit submenu for clip editing operations
function Default:clip_edit_menu()
	local tid = App.current_track
	local track = App.track[tid]
	local items = {}
	
	if not track or not track.clip then return items end
	
	local clip = track.clip
	
	-- Quantize
	table.insert(
		items,
		Registry.menu.make_item('clip_edit_quantize', {
			label_fn = function() return 'QUANTIZE' end,
			value_fn = function()
				local grid = App.clip_edit_grid or (App.ppqn / 4) -- default 1/16 note
				local note_name = ''
				if grid == App.ppqn * 4 then note_name = ' (1/1)'
				elseif grid == App.ppqn * 2 then note_name = ' (1/2)'
				elseif grid == App.ppqn then note_name = ' (1/4)'
				elseif grid == App.ppqn / 2 then note_name = ' (1/8)'
				elseif grid == App.ppqn / 4 then note_name = ' (1/16)'
				elseif grid == App.ppqn / 8 then note_name = ' (1/32)'
				end
				return tostring(grid) .. ' ticks' .. note_name
			end,
			enc3 = function(d)
				-- Grid sizes: 1/32, 1/16, 1/8, 1/4, 1/2, 1/1
				local grids = { App.ppqn / 8, App.ppqn / 4, App.ppqn / 2, App.ppqn, App.ppqn * 2, App.ppqn * 4 }
				local current = App.clip_edit_grid or (App.ppqn / 4)
				local idx = 1
				for i, g in ipairs(grids) do
					if math.abs(g - current) < 1 then idx = i break end
				end
				idx = util.clamp(idx + d, 1, #grids)
				App.clip_edit_grid = grids[idx]
				App.screen_dirty = true
			end,
			on_press = function()
				if clip then
					local grid = App.clip_edit_grid or (App.ppqn / 4)
					local count = clip:quantize_frozen(grid)
					print('Quantized ' .. count .. ' events')
					App.screen_dirty = true
				end
			end,
			helper_labels = {
				enc3 = 'grid size',
				press_fn_3 = 'quantize',
			},
		})
	)
	
	-- Transpose
	table.insert(
		items,
		Registry.menu.make_item('clip_edit_transpose', {
			label_fn = function() return 'TRANSPOSE' end,
			value_fn = function()
				local semitones = App.clip_edit_transpose or 0
				if semitones == 0 then return '0'
				elseif semitones > 0 then return '+' .. semitones
				else return tostring(semitones)
				end
			end,
			enc3 = function(d)
				App.clip_edit_transpose = util.clamp((App.clip_edit_transpose or 0) + d, -12, 12)
				App.screen_dirty = true
			end,
			on_press = function()
				if clip then
					local semitones = App.clip_edit_transpose or 0
					local count = clip:transpose_frozen(semitones)
					print('Transposed ' .. count .. ' events by ' .. semitones .. ' semitones')
					App.screen_dirty = true
				end
			end,
			helper_labels = {
				enc3 = 'semitones',
				press_fn_3 = 'transpose',
			},
		})
	)
	
	-- Velocity scale
	table.insert(
		items,
		Registry.menu.make_item('clip_edit_velocity', {
			label_fn = function() return 'VELOCITY' end,
			value_fn = function()
				local factor = App.clip_edit_velocity_factor or 1.0
				return string.format('%.2fx', factor)
			end,
			enc3 = function(d)
				local factor = App.clip_edit_velocity_factor or 1.0
				factor = util.clamp(factor + (d * 0.1), 0.1, 2.0)
				App.clip_edit_velocity_factor = factor
				App.screen_dirty = true
			end,
			on_press = function()
				if clip then
					local factor = App.clip_edit_velocity_factor or 1.0
					local count = clip:scale_velocity_frozen(factor)
					print('Scaled velocity for ' .. count .. ' events by ' .. string.format('%.2fx', factor))
					App.screen_dirty = true
				end
			end,
			helper_labels = {
				enc3 = 'factor',
				press_fn_3 = 'scale',
			},
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
