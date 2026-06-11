local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'components/mode/modecomponent')
local UI = require(path_name .. 'ui')
local Registry = require(path_name .. 'utilities/registry')

--[[
BufferDefault Mode Component

This component provides a buffer-specific menu for the User mode, making it easy
to enable and disable buffer settings like playback, overdub, loop recording,
mute on arm, and scrub loop mode.
]]

local BufferDefault = ModeComponent:new({})

function BufferDefault:enable_event()
	local context = self:default_context()
	local screen = self:default_screen()
	local options = { timeout = false }

	if not self.mode.default_menu then options.set_default = true end

	self.current = { context = context, screen = screen, options = options }
	self.mode:use_context(context, screen, options)
end

function BufferDefault:default_context()
	local ctx = {
		cursor = self.mode.cursor or 1,
		menu = self:default_menu(),
		enc1 = function(d)
			-- Cycle through tracks
			local total_tracks = (#App.track and #App.track > 0) and #App.track or 8
			local next_track = util.clamp(App.current_track + d, 1, total_tracks)
			if next_track ~= App.current_track then
				App.current_track = next_track

				-- Update grid row pads to show new track selection
				if self.mode and self.mode.row_pads then
					self.mode.row_pads:reset()
					self.mode.row_pads.led[9][9 - App.current_track] = 1
					self.mode.row_pads:refresh()
				end

				-- Update bufferseq component to reflect new track
				if self.mode and self.mode.components then
					for _, comp in ipairs(self.mode.components) do
						if comp.row_event then comp:row_event({ state = true, row = App.current_track }) end
						-- Refresh grid display for the new track
						if comp.set_grid and comp.get_component then comp:set_grid(comp:get_component()) end
					end
				end

				-- Rebuild context/menu for new track
				local screen_fn = (self.current and self.current.screen) or self:default_screen()
				local options = { timeout = false, menu_override = true, cursor = 1 }
				local next_context = self:default_context()
				self.current = { context = next_context, screen = screen_fn, options = options }
				self.mode:use_context(next_context, screen_fn, options)
				App.screen_dirty = true
			end
		end,
		press_fn_3 = function()
			-- Check if current menu item has its own press_fn_3 handler
			local current_item = self.mode.menu and self.mode.menu[self.mode.cursor]
			if current_item and current_item.press_fn_3 then
				-- Let the menu item handle it (e.g., clear buffer)
				current_item.press_fn_3()
			end
		end,
		disable_highlight = true,
	}
	return ctx
end

-- Handle transitions to sub-menus
function BufferDefault:sub_menu(menu, config)
	config = config or {}
	local previous = self.current
	local prev_cursor = self.mode and self.mode.cursor or 1

	local setPrevious = function()
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

	-- Back button helper
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

-- Default menu shows all buffer settings in one menu
function BufferDefault:default_menu()
	local id = App.current_track

	local items = {
		Registry.menu.make_item('track_' .. id .. '_buffer_arm', {
			icon = '\u{25cf}',
			label_fn = function() return 'RECORD ARM' end,
			value_fn = function()
				local track = App.track[id]
				return (track and track.buffer_armed) and 'armed' or 'off'
			end,
			helper_labels = {
				enc3 = 'toggle',
			},
		}),
		-- Playback mode (Default/Input/Direct/Scale Only)
		Registry.menu.make_item('track_' .. id .. '_buffer_playback_mode', {
			icon = '\u{25cf}',
			label_fn = function() return 'PLAYBACK MODE' end,
			value_fn = function()
				local track = App.track[App.current_track]
				local mode = track and track.buffer and track.buffer.playback_mode or 1
				local modes = { 'Default', 'Input', 'Direct', 'Scale Only' }
				return modes[mode] or 'Default'
			end,
			helper_labels = {
				enc3 = 'change mode',
			},
		}),
		-- Monitor (replaces overdub/overwrite: IN = always on, AUTO = on when not playing, OFF = never)
		Registry.menu.make_item('track_' .. id .. '_monitor', {
			icon = '\u{25cf}',
			label_fn = function() return 'MONITOR' end,
			value_fn = function()
				local track = App.track[id]
				if not track then return 'AUTO' end
				local monitor = track.monitor or 2
				local modes = { 'IN', 'AUTO', 'OFF' }
				return modes[monitor] or 'AUTO'
			end,
			helper_labels = {
				enc3 = 'change mode',
			},
		}),
		-- Loop Recording/Playback vs One-shot (per-track)
		Registry.menu.make_item('track_' .. id .. '_buffer_loop', {
			icon = '\u{25cf}',
			label_fn = function() return 'LOOP' end,
			value_fn = function()
				local track = App.track[App.current_track]
				local buffer_loop = track and track.buffer and track.buffer.buffer_loop
				return buffer_loop and 'loop' or 'one-shot'
			end,
			helper_labels = {
				enc3 = 'toggle',
			},
		}),
		-- Scrub Mode (loop vs play-through)
		Registry.menu.make_item('buffer_scrub_mode', {
			icon = '\u{25cf}',
			label_fn = function() return 'SCRUB MODE' end,
			value_fn = function() return App.buffer_scrub_mode == 'loop' and 'loop' or 'play-thru' end,
			helper_labels = {
				enc3 = 'toggle',
			},
		}),
		-- Clear buffer for current track
		{
			icon = '\u{2715}',
			label = function() return 'CLEAR BUFFER' end,
			value = function() return '' end,
			disable = true,
			on_press = function()
				local track = App.track[App.current_track]
				if track and track.buffer then
					track.buffer:clear_buffer()
					print('Buffer cleared for track ' .. App.current_track)
				end
			end,
			press_fn_3 = function()
				local track = App.track[App.current_track]
				if track and track.buffer then
					track.buffer:clear_buffer()
					print('Buffer cleared for track ' .. App.current_track)
				end
			end,
			has_press = true,
			helper_labels = {
				press_fn_3 = 'clear',
			},
		},
	}
	return items
end

function BufferDefault:default_screen()
	return function()
		UI:draw_small_tempo()

		if self.current and self.current.status then
			UI:draw_status(self.current.status.icon, self.current.status.label)
		else
			-- Show current track number and name in status
			local track_name = App.track[App.current_track] and App.track[App.current_track].name or ('Track ' .. App.current_track)
			UI:draw_status(App.current_track, track_name)
		end
		UI:draw_menu(0, 20, self.mode.menu, self.mode.cursor, { disable_highlight = self.mode.disable_highlight })
	end
end

return BufferDefault
