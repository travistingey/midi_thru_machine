local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local path_name = 'Foobar/lib/components/mode/'

local MuteGrid = require('Foobar/lib/components/mode/mutegrid')
local PresetGrid = require('Foobar/lib/components/mode/presetgrid')
local BufferSeq = require('Foobar/lib/components/mode/bufferseq')
local Default = require('Foobar/lib/components/mode/default')

local Mode = require('Foobar/lib/components/app/mode')

local bufferseq = BufferSeq:new({
	track = 1,
	grid_start = { x = 1, y = 4 },
	grid_end = { x = 8, y = 1 },
	display_start = { x = 1, y = 1 },
	display_end = { x = 8, y = 4 },
	offset = { x = 0, y = 4 },
})
local mutegrid = MuteGrid:new({ track = 1 })
local presetgrid = PresetGrid:new({ track = 1, param_type = 'track' })
local default = Default:new({})

local SessionMode = Mode:new({
	id = 1,
	track = 1,
	components = {
		default,
		bufferseq,
		mutegrid,
		presetgrid,
	},
	load_event = function(s, data)
		bufferseq.track = App.current_track
		presetgrid.track = App.current_track

		-- Use bufferseq's unified row pad update function
		bufferseq:update_row_pads()
		App.screen_dirty = true
	end,
	arrow_event = function(self, data)
		if data.state then
			-- Check for alt mode first - bufferseq handles alt mode arrow events
			if bufferseq.arrow_event then
				bufferseq:arrow_event(data)
				return
			end
		end
	end,
	row_event = function(self, data)
		if data.state then
			-- Let bufferseq handle row events (including alt mode arming)
			-- It will update row pads internally
			bufferseq:row_event(data)
			
			-- Only proceed with track switching if bufferseq didn't handle it (not alt mode)
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
