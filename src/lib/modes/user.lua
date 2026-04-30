local path_name = 'Foobar/lib/'

local BitwiseGrid = require(path_name .. 'components/mode/bitwisegrid')
local Mode = require(path_name .. 'components/app/mode')
local Default = require(path_name .. 'components/mode/default')
local Registry = require(path_name .. 'utilities/registry')

local bitwisegrid = BitwiseGrid:new({
	track = 1,
	grid_start = { x = 1, y = 8 },
	grid_end = { x = 8, y = 1 },
	display_start = { x = 1, y = 1 },
	display_end = { x = 8, y = 8 },
	offset = { x = 0, y = 0 },
})

local default = Default:new({})

local UserMode = Mode:new({
	id = 4,
	track = 1,
	components = {
		default,
		bitwisegrid,
	},
	load_event = function(self, data)
		local function legacy_screen()
			screen.clear()
			bitwisegrid:draw()
		end

		local function open_bitwise_menu()
			default:sub_menu(default:bitwise_menu(), {
				status = { icon = App.current_track, label = 'Bitwise' },
				screen = default:submenu_screen(),
			})
		end

		local legacy_context = {
			press_fn_2 = open_bitwise_menu,
			enc1 = function(d)
				local tid = App.current_track
				local pid = 'track_' .. tid .. '_chance'
				local chance = util.clamp((params:get(pid) or 0.5) + (d * 0.01), 0, 1)
				Registry.set(pid, chance, 'user_mode_bitwise_chance')
				App.screen_dirty = true
			end,
			enc2 = function(d)
				bitwisegrid:move_selection(d)
			end,
			enc3 = function(d)
				bitwisegrid:adjust_selected(-d)
			end,
			enc3_alt = function(d)
				bitwisegrid:set_lane('vel')
				bitwisegrid:adjust_selected(-d)
			end,
			default_helper_labels = {
				enc1 = 'chance',
				enc2 = 'step',
				enc3 = 'note value',
				enc3_alt = 'velocity',
				press_fn_2 = 'menu',
			},
		}

		default.current = {
			context = legacy_context,
			screen = legacy_screen,
			options = { timeout = false, menu_override = true, cursor = 1 },
			status = { icon = App.current_track, label = 'Bitwise' },
		}

		self:use_context(default.current.context, default.current.screen, default.current.options)
		bitwisegrid.track = App.current_track
		local input = bitwisegrid:get_component()
		bitwisegrid:set_grid(input)

		App.screen_dirty = true
	end,
	arrow_event = function(self, data)
		if data.state then
			if data.type == 'left' then
				bitwisegrid:set_lane('note')
			elseif data.type == 'right' then
				bitwisegrid:set_lane('vel')
			elseif data.type == 'up' then
				bitwisegrid:cycle('right')
			elseif data.type == 'down' then
				bitwisegrid:cycle('left')
			end
		end
	end,
	row_event = function(self, data)
		if data.state then
			if data.row ~= App.current_track then
				self.track = data.row
				App.current_track = data.row

				self:load_event()

				bitwisegrid.track = data.row
				bitwisegrid:set_grid(bitwisegrid:get_component())
				App.screen_dirty = true
			end
		end
	end,
})

return UserMode
