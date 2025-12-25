local Mode = require('Foobar/lib/components/app/mode')
local ScaleGrid = require('Foobar/lib/components/mode/scalegrid')
local PresetGrid = require('Foobar/lib/components/mode/presetgrid')
local Registry = require('Foobar/lib/utilities/registry')
local UI = require('Foobar/lib/ui')
local musicutil = require('Foobar/lib/musicutil-extended')
local Default = require('Foobar/lib/components/mode/default')

local function format_root_note(sid)
	if sid > 0 and App.scale[sid] then
		local val = util.clamp(params:get('scale_' .. sid .. '_root'), -24, 24)
		local octave = math.floor(val / 12)
		local note = ((val % 12) + 12) % 12
		if val < 0 or val > 12 then return musicutil.note_num_to_name(note) .. tostring(octave) end
		return musicutil.note_num_to_name(note)
	end
	return '--'
end

local function keys_default_menu(self)
	local tid = App.current_track
	local items = {}
	local sid_param = 'track_' .. tid .. '_scale_select'
	local style = { inactive_color = 15, icon_inactive_color = 5, width = 80 }

	table.insert(
		items,
		Registry.menu.make_item(sid_param, {
			label_fn = function() return 'SCALE' end,
			value_fn = function()
				local v = params:get(sid_param)
				if v == 0 then return 'off' end
				return v
			end,
			disable = true,
			style = style,
		})
	)

	table.insert(
		items,
		Registry.menu.make_item('track_' .. tid .. '_root_display', {
			label_fn = function() return 'ROOT' end,
			value_fn = function()
				local sid = params:get(sid_param)
				return format_root_note(sid)
			end,
			disable = true,
			style = style,
		})
	)

	return items
end

local function keys_default_context(self)
	local ctx = Default.default_context(self)
	-- Encoder 1 switches scales (skip 0/off)
	ctx.enc1 = function(d)
		if d == 0 then return end
		local tid = App.current_track
		local sid_param = 'track_' .. tid .. '_scale_select'
		local p = params:lookup_param(sid_param)
		if not p then return end
		local max = (p.options and #p.options) or p.max or 1
		if max < 1 then return end
		local cur = params:get(sid_param)
		local next_sid = util.clamp(cur + d, 1, max)
		if next_sid ~= cur then
			Registry.set(sid_param, next_sid, 'keys_enc1')
			App.screen_dirty = true
		end
	end
	-- Jump directly to scale menu when opening menu
	ctx.press_fn_3 = function()
		local sid = params:get('track_' .. App.current_track .. '_scale_select')
		if sid > 0 then
			local config = {
				status = { icon = '\u{266a}', label = 'scale ' .. sid },
				options = { timeout = false },
				screen = self:submenu_screen(),
			}
			self:sub_menu(self:scale_menu(sid), config)
		end
	end
	-- Menu rows are informational only
	ctx.disable_highlight = true
	return ctx
end

local function keys_default_screen(self)
	return function()
		local tid = App.current_track
		local sid = params:get('track_' .. tid .. '_scale_select')
		screen.clear()
		if sid > 0 then UI:draw_chord_large(sid) end

		if self.current and self.current.status then
			UI:draw_status(self.current.status.icon, self.current.status.label)
		else
			UI:draw_status()
		end
		UI:draw_menu(0, 20, self.mode.menu, self.mode.cursor, { disable_highlight = self.mode.disable_highlight })
	end
end

local KeysMode = Mode:new({
	id = 3,
	-- Base layer can show intervals for the active track's scale selection
	screen = function()
		local tid = App.current_track
		local sid = params:get('track_' .. tid .. '_scale_select')
		if sid and sid > 0 then UI:draw_intervals(0, 63, sid) end
	end,
	components = {
		Default:new({
			default_menu = keys_default_menu,
			default_screen = keys_default_screen,
			default_context = keys_default_context,
		}),
		ScaleGrid:new({ id = 1, offset = { x = 0, y = 6 } }),
		ScaleGrid:new({ id = 2, offset = { x = 0, y = 4 } }),
		ScaleGrid:new({ id = 3, offset = { x = 0, y = 2 } }),
		PresetGrid:new({
			id = 2,
			track = 1,
			grid_start = { x = 1, y = 2 },
			grid_end = { x = 8, y = 1 },
			display_start = { x = 1, y = 1 },
			display_end = { x = 8, y = 2 },
			offset = { x = 0, y = 0 },
			param_list = {
				'scale_1_bits',
				'scale_1_root',
				'scale_2_bits',
				'scale_2_root',
				'scale_3_bits',
				'scale_3_root',
			},
		}),
	},
	on_load = function() App.screen_dirty = true end,
	row_event = function(s, data)
		if data.state then
			if data.row < 7 then
				local scalegrid = s.components[math.ceil(data.row / 2)]
				scalegrid:row_event(data)
			end
		end
	end,
})

return KeysMode
