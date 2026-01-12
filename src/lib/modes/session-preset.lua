local Grid = require('Foobar/lib/grid')
local utilities = require('Foobar/lib/utilities')
local Registry = require('Foobar/lib/utilities/registry')
local path_name = 'Foobar/lib/components/mode/'

local MuteGrid = require('Foobar/lib/components/mode/mutegrid')
local PresetGrid = require('Foobar/lib/components/mode/presetgrid')
local PresetSeq = require('Foobar/lib/components/mode/presetseq')
local Default = require('Foobar/lib/components/mode/default')

local Mode = require('Foobar/lib/components/app/mode')

local presetseq = PresetSeq:new({ track = 1 })
local mutegrid = MuteGrid:new({ track = 1 })
local presetgrid = PresetGrid:new({ track = 1, param_type = 'track' })
local default = Default:new({})

local SessionMode = Mode:new({
	id = 1,
	track = 1,
	cursor = 1,
	components = {
		default,
		presetseq,
		mutegrid,
		presetgrid,
	},
	load_event = function(self, data)
		presetseq.track = App.current_track
		presetgrid.track = App.current_track

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
				presetseq:increase_step_length()
			elseif data.type == 'right' then
				presetseq:decrease_step_length()
			elseif data.type == 'up' then
				presetseq:decrease_display_offset()
				if presetseq.display_offset == 0 then print('At buffer start') end
			elseif data.type == 'down' then
				presetseq:increase_display_offset()
				print('Buffer offset: ' .. presetseq.display_offset)
			end
		end
	end,
	row_event = function(self, data)
		if data.state then
			self.row_pads:reset()

			if data.row ~= App.current_track then
				self.track = data.row
				App.current_track = data.row

				presetseq:row_event(data)
				presetgrid:row_event(data)
			else
				App:set_mode(5)
				return
			end

			if self.alt then
				App:set_mode(5)
			else
				self:disable()
				self:enable()
			end
		end
	end,
})

return SessionMode
