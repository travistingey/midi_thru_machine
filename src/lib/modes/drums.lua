local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local path_name = 'Foobar/lib/components/mode/'

local BufferSeq = require('Foobar/lib/components/mode/bufferseq')
local DrumsDefault = require('Foobar/lib/components/mode/drumsdefault')

local Mode = require('Foobar/lib/components/app/mode')

-- BufferSeq with full 8x8 grid for Drums mode
local bufferseq = BufferSeq:new({
	track = 1,
	grid_start = { x = 1, y = 8 },
	grid_end = { x = 8, y = 1 },
	display_start = { x = 1, y = 1 },
	display_end = { x = 8, y = 8 },
	offset = { x = 0, y = 0 },
})

local default = DrumsDefault:new({})

local DrumsMode = Mode:new({
	id = 2,
	track = 1,
	components = {
		default,
		bufferseq,
	},
	load_event = function(s, data)
		bufferseq.track = App.current_track
		
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
			-- Let bufferseq handle row events (including alt mode unfreezing)
			-- It will update row pads internally
			bufferseq:row_event(data)
			
			-- Only proceed with track switching if bufferseq didn't handle it (not alt mode)
			if not self.alt then
				if data.row ~= App.current_track then
					self.track = data.row
					App.current_track = data.row
				else
					App:set_mode(2)
					return
				end
				
				self:disable()
				self:enable()
			end
		end
	end,
})

return DrumsMode 
