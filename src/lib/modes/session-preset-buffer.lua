local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local path_name = 'Foobar/lib/components/mode/'

local MuteGrid = require('Foobar/lib/components/mode/mutegrid')
local PresetGrid = require('Foobar/lib/components/mode/presetgrid')
local ClipGrid = require('Foobar/lib/components/mode/clipgrid')
local Default = require('Foobar/lib/components/mode/default')

local Mode = require('Foobar/lib/components/app/mode')

-- ClipGrid replaces BufferSeq in Session mode
local clipgrid = ClipGrid:new({
	track = 1,
	grid_start = { x = 1, y = 4 },
	grid_end = { x = 8, y = 1 },
	display_start = { x = 1, y = 1 },
	display_end = { x = 8, y = 4 },
	offset = { x = 0, y = 4 },
})
local mutegrid = MuteGrid:new({ track = 1 })
local presetgrid = PresetGrid:new({
	track = 1,
	param_type = 'track',
	-- Scoped save per track/scale; normal press recall is macro or single-track via PARAMS > Preset grid macro
	use_macro_launch_param = true,
	save_mode = 'scoped_overwrite',
	save_track_fn = function(self) return App.current_track end,
	save_scale_fn = function(self, tid)
		local pid = 'track_' .. tid .. '_scale_select'
		return params:get(pid) or 0
	end,
})
local default = Default:new({})

local SessionMode = Mode:new({
	id = 1,
	track = 1,
	components = {
		default,
		clipgrid,
		mutegrid,
		presetgrid,
	},
	load_event = function(s, data)
		clipgrid.track = App.current_track
		presetgrid.track = App.current_track

		-- Use clipgrid's unified row pad update function
		clipgrid:update_row_pads()
		App.screen_dirty = true
	end,
	row_event = function(self, data)
		if data.type == 'row_long' then
			clipgrid:row_event(data)
			return
		end
		if data.state then
			-- Let clipgrid handle row events
			-- It will update row pads internally
			clipgrid:row_event(data)
			
			-- Only proceed with track switching if not in alt mode
			if not self.alt then
				if data.row ~= App.current_track then
					self.track = data.row
					App.current_track = data.row
					presetgrid:row_event(data)
				else
					App:set_mode(1)
					return
				end

				self:disable()
				self:enable()
			end
		end
	end,
})

return SessionMode
