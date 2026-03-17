local path_name = 'Foobar/lib/'
local Default = require(path_name .. 'components/mode/default')
local UI = require(path_name .. 'ui')

--[[
DrumsDefault Mode Component

In Drums mode, we want the clip menu to be "first level" instead of having to
enter the Track menu and then select CLIP. This component reuses Default's
menus/screens, but routes K3 (press_fn_3) directly into the clip menu.
]]

local DrumsDefault = Default:new({})

function DrumsDefault:enable_event()
	local context = self:default_context()
	local screen = self:default_screen()
	local options = { timeout = false }

	if not self.mode.default_menu then options.set_default = true end

	self.current = { context = context, screen = screen, options = options }
	self.mode:use_context(context, screen, options)
end

function DrumsDefault:default_context()
	local ctx = {
		cursor = self.mode.cursor or 1,
		menu = self:default_menu(),
		enc1 = function(d)
			local total_tracks = (#App.track and #App.track > 0) and #App.track or 8
			local next_track = util.clamp(App.current_track + d, 1, total_tracks)
			if next_track ~= App.current_track then
				App.current_track = next_track
				-- rebuild context/menu so closures reference the new track
				local screen_fn = (self.current and self.current.screen) or self:default_screen()
				local options = { timeout = false, menu_override = true, cursor = 1 }
				local next_context = self:default_context()
				self.current = { context = next_context, screen = screen_fn, options = options }
				self.mode:use_context(next_context, screen_fn, options)
				App.screen_dirty = true
			end
		end,
		press_fn_3 = function()
			-- In Drums mode, jump directly to CLIP menu.
			self:sub_menu(self:clip_menu(), {
				status = { icon = App.current_track, label = 'CLIP' },
				screen = self:submenu_screen(),
			})
		end,
		disable_highlight = true,
	}
	return ctx
end

-- Keep the same screen behavior as Default, but show small tempo like submenus
-- to match "editing" workflows in Drums.
function DrumsDefault:default_screen()
	return function()
		UI:draw_small_tempo()
		if self.current.status then
			UI:draw_status(self.current.status.icon, self.current.status.label)
		else
			UI:draw_status(App.current_track, 'CLIP')
		end
		UI:draw_menu(0, 20, self.mode.menu, self.mode.cursor, { disable_highlight = self.mode.disable_highlight })
	end
end

return DrumsDefault

