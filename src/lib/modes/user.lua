local path_name = 'Foobar/lib/'

local Grid = require(path_name .. 'grid')
local utilities = require(path_name .. 'utilities')
local Registry = require(path_name .. 'utilities/registry')
local BufferSeq = require(path_name .. 'components/mode/bufferseq')
local Mode = require(path_name .. 'components/app/mode')
local UI = require(path_name .. 'ui')
local BufferDefault = require(path_name .. 'components/mode/bufferdefault')

-- Buffer-specific component with full 8x8 grid and scrub playback
local bufferseq = BufferSeq:new({
	track = 1,
	grid_start = { x = 1, y = 8 },
	grid_end = { x = 8, y = 1 },
	display_start = { x = 1, y = 1 },
	display_end = { x = 8, y = 8 },
	offset = { x = 0, y = 0 },
})

local default = BufferDefault:new({})

local UserMode = Mode:new({
	id = 4,
	track = 1,
	components = {
		default,
		bufferseq,
	},
	load_event = function(self, data)
		bufferseq.track = App.current_track

		-- Recalculate display for current track's buffer_step_length
		bufferseq:recalculate_display()
		local auto = bufferseq:get_component()
		if auto then bufferseq:set_grid(auto) end

		self.row_pads.led[9][9 - App.current_track] = 1
		self.row_pads:refresh()

		App.screen_dirty = true
	end,
	arrow_event = function(self, data)
		if data.state then
			if App.recording then
				print('Cannot change zoom during recording')
				return
			end

			-- Left/Right: zoom in/out (step length)
			-- Up/Down: scroll through buffer
			if data.type == 'left' then
				bufferseq:increase_step_length()
				-- step_length is now stored in track's auto component
			elseif data.type == 'right' then
				bufferseq:decrease_step_length()
				-- step_length is now stored in track's auto component
			elseif data.type == 'up' then
				bufferseq:decrease_display_offset()
				if bufferseq.display_offset == 0 then print('At buffer start') end
			elseif data.type == 'down' then
				bufferseq:increase_display_offset()
				print('Buffer offset: ' .. bufferseq.display_offset)
			end
		end
	end,
	row_event = function(self, data)
		if data.state then
			self.row_pads:reset()

			if data.row ~= App.current_track then
				self.track = data.row
				App.current_track = data.row
				bufferseq:row_event(data)

				-- Rebuild context/menu for new track (same logic as encoder 1 handler)
				-- This ensures encoder bindings are updated to the new track
				if default and default.default_context and default.mode then
					local screen_fn = (default.current and default.current.screen) or default:default_screen()
					local options = { timeout = false, menu_override = true, cursor = 1 }
					local next_context = default:default_context()
					default.current = { context = next_context, screen = screen_fn, options = options }
					self:use_context(next_context, screen_fn, options)
					App.screen_dirty = true
				end
			end

			self.row_pads.led[9][9 - App.current_track] = 1
			self.row_pads:refresh()
		end
	end,
})

return UserMode
