local path_name = 'Foobar/lib/'
local Grid = require(path_name .. 'grid')
local utilities = require(path_name .. 'utilities')

local Input = require(path_name .. 'components/track/input')
local Seq = require(path_name .. 'components/track/seq')
local Output = require(path_name .. 'components/track/output')
local UI = require(path_name .. 'ui')
local Registry = require(path_name .. 'utilities/registry')

-- Define a new class for Mode
local Mode = {}

-- Constructor

function Mode:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	self.set(o, o)
	self.register_params(o, o)
	return o
end

-- Menu interaction logic (moved from UI)
function Mode:set_cursor(d)
	local visible_indices = self:get_visible_indices()
	if #visible_indices == 0 then
		self.cursor = 1
		self:update_helper_toast({ duration = App.alt_down and false or 2.5 })
		App.screen_dirty = true
		return
	end

	local current = self.cursor or 1
	local current_pos
	for i, idx in ipairs(visible_indices) do
		if idx == current then
			current_pos = i
			break
		end
	end

	local steps = math.abs(d or 0)
	local direction = 0
	if d and d > 0 then
		direction = 1
	elseif d and d < 0 then
		direction = -1
	end

	if direction == 0 then
		if not current_pos then current_pos = 1 end
	else
		if not current_pos then current_pos = (direction > 0) and 1 or #visible_indices end
		for _ = 1, steps do
			current_pos = util.clamp(current_pos + direction, 1, #visible_indices)
		end
	end

	local next_cursor = visible_indices[current_pos or 1] or visible_indices[1]

	if next_cursor ~= current and self:has_pending_confirmation() then self:clear_pending_confirmation({ revert = true }) end

	self.cursor = next_cursor

	local helper_duration = App.alt_down and false or 2.5
	self:update_helper_toast({ duration = helper_duration })
	App.screen_dirty = true
end

function Mode:use_menu(ctx, d)
	local item = self.menu and self.menu[self.cursor]
	if item and type(item[ctx]) == 'function' then item[ctx](d) end
	App.screen_dirty = true
end

function Mode:get_visible_menu_range()
	local total_items = #(self.menu or {})
	local max_visible = UI.max_visible_items

	if total_items <= max_visible then return 1, total_items end

	local start_index = 1
	local end_index = max_visible

	if (self.cursor or 1) > max_visible - 2 then
		if (self.cursor or 1) <= total_items - 2 then
			start_index = self.cursor - 2
			end_index = self.cursor + 2
		else
			start_index = total_items - max_visible + 1
			end_index = total_items
		end
	end

	return start_index, end_index
end

function Mode:set(o)
	self.id = o.id
	self.components = o.components or {}

	self.set_action = o.set_action

	self.enabled = false
	self.timeout = 5
	self.reset_timeout_count = false
	self.interupt = false
	self.context = o.context or {}
	self.default = {}

	self.event_listeners = {}
	self.cleanup_functions = {}

	self.track = o.track

	for binding, func in pairs(App.default) do
		if self.context[binding] then
			self.default[binding] = self.context[binding]
		else
			self.default[binding] = func
			self.context[binding] = func
		end
	end

	self.layer = o.layer or {}
	self.layer[1] = App.default.screen
	self.screen = o.screen or function() end

	-- Stateless UI now; track menu state per mode
	self.menu = {}
	self.cursor = 1
	self.cursor_positions = 0
	self.max_visible_items = 5
	self.default_menu = nil
	self.default_screen = nil
	self.pending_confirmation = nil
	self.default_helper_labels = nil
	self.context_helper_labels = nil
	self.helper_toast_clock = nil
	self.helper_layer = nil
	self.disable_highlight = false
	self.default_disable_highlight = nil

	-- Create the modes
	self.grid = Grid:new({
		grid_start = { x = 1, y = 1 },
		grid_end = { x = 9, y = 9 },
		display_start = { x = 1, y = 1 },
		display_end = { x = 9, y = 9 },
		midi = App.midi_grid,
		active = false,
		process = function(s, msg)
			for i, g in ipairs(self.grid.subgrids) do
				g.active = true
				g:process(msg)
			end

			for i, c in ipairs(self.components) do
				if c.grid and c.grid.process then c.grid:process(msg) end
			end
		end,
	})

	self.mode_pads = self.grid:subgrid({
		name = 'mode pads',
		grid_start = { x = 5, y = 9 },
		grid_end = { x = 8, y = 9 },
	})

	self.arrow_pads = self.grid:subgrid({
		name = 'arrows pads',
		grid_start = { x = 1, y = 9 },
		grid_end = { x = 4, y = 9 },
		event = function(s, data) self:emit('arrow', self, data) end,
	})

	self.row_pads = self.grid:subgrid({
		name = 'row pads',
		grid_start = { x = 9, y = 2 },
		grid_end = { x = 9, y = 8 },
		event = function(s, data) self:emit('row', self, data) end,
	})

	-- Alt pad
	self.alt_pad = self.grid:subgrid({
		name = 'alt pad',
		grid_start = { x = 9, y = 1 },
		grid_end = { x = 9, y = 1 },
		event = function(s, data)
			if data.toggled then
				s.led[data.x][data.y] = 1
			else
				s.led[data.x][data.y] = 0
				if data.state then s:reset() end
			end
			self.alt = data.toggled
			s:refresh('alt event')
			self:emit('alt', data)
		end,
	})
end

function Mode:get_pending_confirmation() return self.pending_confirmation end

function Mode:has_pending_confirmation() return self.pending_confirmation ~= nil end

function Mode:is_menu_item_visible(index)
	local menu = self.menu or {}
	local item = menu[index]
	if not item then return false end
	if item.can_show == nil then return true end
	local show = item.can_show
	if type(show) == 'function' then
		local ok, result = pcall(show, item)
		if ok then
			show = result
		else
			show = true
		end
	end
	return show ~= false
end

function Mode:get_visible_indices()
	local indices = {}
	for i, _ in ipairs(self.menu or {}) do
		if self:is_menu_item_visible(i) then table.insert(indices, i) end
	end
	return indices
end

function Mode:clear_pending_confirmation(opts)
	if not self.pending_confirmation then return end

	local pending = self.pending_confirmation
	local revert = false

	if type(opts) == 'table' then
		revert = opts.revert or false
	elseif type(opts) == 'boolean' then
		revert = opts
	end

	if pending.item then pending.item.pending_confirmation = nil end

	if revert and pending.param_id and pending.original ~= nil and pending.pending ~= nil and pending.pending ~= pending.original then
		Registry.set(pending.param_id, pending.original, 'menu_bump_revert', pending.callback, true)
	end

	self.pending_confirmation = nil
end

function Mode:confirm_pending_confirmation()
	local pending = self.pending_confirmation
	if not pending or not pending.param_id then return false end

	local param_id = pending.param_id
	local value = pending.pending
	local callback = pending.callback

	if pending.item then pending.item.pending_confirmation = nil end
	self.pending_confirmation = nil

	if value ~= nil then
		if pending.original ~= nil and pending.original ~= value then params:set(param_id, pending.original, true) end
		Registry.set(param_id, value, 'menu_bump_confirm', callback)
	end

	return true
end

function Mode:prepare_pending_confirmation(entry)
	if not entry or not entry.param_id then return end

	local pending = self.pending_confirmation
	local param_id = entry.param_id

	if pending and pending.param_id ~= param_id then
		self:clear_pending_confirmation({ revert = true })
		pending = nil
	end

	if not pending then
		pending = {
			param_id = param_id,
			original = entry.original_value,
		}
		self.pending_confirmation = pending
	elseif pending.original == nil then
		pending.original = entry.original_value
	end

	if entry.item then
		pending.item = entry.item
		entry.item.pending_confirmation = true
	end

	if pending.item and pending.item_index == nil then
		for idx, menu_item in ipairs(self.menu or {}) do
			if menu_item == pending.item then
				pending.item_index = idx
				break
			end
		end
	end

	pending.pending = entry.new_value
	pending.callback = entry.callback
	pending.side = entry.side

	if pending.original ~= nil and pending.pending ~= nil and pending.original == pending.pending then self:clear_pending_confirmation({ revert = false }) end
end

function Mode:cancel_helper_toast()
	if self.helper_toast_clock then
		clock.cancel(self.helper_toast_clock)
		self.helper_toast_clock = nil
	end

	if self.helper_layer then
		for i, layer in ipairs(self.layer) do
			if layer == self.helper_layer then
				table.remove(self.layer, i)
				break
			end
		end
		self.helper_layer = nil
		App.screen_dirty = true
	end
end

function Mode:show_helper_toast(helper_labels, duration)
	if not helper_labels then
		self:cancel_helper_toast()
		return
	end

	self:cancel_helper_toast()

	local resolved = helper_labels
	if type(resolved) == 'function' then resolved = resolved() end
	if type(resolved) ~= 'table' then return end

	local has_entries = false
	for _ in pairs(resolved) do
		has_entries = true
		break
	end
	if not has_entries then return end

	local function helper_screen()
		local draw_labels = helper_labels
		if type(draw_labels) == 'function' then draw_labels = draw_labels() end
		UI:draw_helper_toast(draw_labels or resolved)
	end

	self.helper_layer = helper_screen
	table.insert(self.layer, helper_screen)

	if duration ~= false then
		local seconds = duration or 2.5
		self.helper_toast_clock = clock.run(function()
			clock.sleep(seconds)
			self.helper_toast_clock = nil
			self:cancel_helper_toast()
		end)
	else
		self.helper_toast_clock = nil
	end

	App.screen_dirty = true
end

function Mode:update_helper_toast(opts)
	opts = opts or {}
	local item = self.menu and self.menu[self.cursor]
	local merged = {}

	local function add_labels(source)
		if not source then return end
		local resolved = source
		if type(resolved) == 'function' then resolved = resolved() end
		if type(resolved) ~= 'table' then return end
		for key, value in pairs(resolved) do
			if value ~= nil then merged[key] = value end
		end
	end

	add_labels(self.default_helper_labels)
	add_labels(self.context_helper_labels)
	if item then
		add_labels(item.helper_labels_default)
		add_labels(item.helper_labels)
	end

	if next(merged) then
		self:show_helper_toast(merged, opts.duration)
	else
		self:cancel_helper_toast()
	end
end

function Mode:update_grid(device)
	-- Update the main mode grid
	self.grid:update_midi(device)
	-- Also update each component’s grid to the new device
	for _, component in ipairs(self.components) do
		if component.grid and component.grid.update_midi then component.grid:update_midi(device) end
	end
end

-- Mode event listeners
function Mode:on(event_name, listener)
	if not self.event_listeners[event_name] then self.event_listeners[event_name] = {} end

	table.insert(self.event_listeners[event_name], listener)

	local cleanup = function() self:off(event_name, listener) end
	table.insert(self.cleanup_functions, cleanup)

	return cleanup
end

function Mode:off(event_name, listener)
	if self.event_listeners and self.event_listeners[event_name] then
		for i, l in ipairs(self.event_listeners[event_name]) do
			if l == listener then
				table.remove(self.event_listeners[event_name], i)
				break
			end
		end
	end
end

function Mode:emit(event_name, ...)
	local listeners = self.event_listeners[event_name]
	if listeners then
		for _, listener in ipairs(listeners) do
			listener(...)
		end
	end
end

function Mode:refresh()
	self:draw()

	for i, c in ipairs(self.components) do
		if c.set_grid ~= nil then c:set_grid() end
	end
	screen_dirty = true
end

function Mode:draw()
	for i, v in pairs(self.layer) do
		self.layer[i](self)
	end
end

-- Added cancel_context method to handle context cleanup
function Mode:cancel_context()
	if self.context_clock then
		clock.cancel(self.context_clock)
		self.context_clock = nil
	end

	-- Remove the context screen from the layer
	if self.context_layer then
		for i, layer in ipairs(self.layer) do
			if layer == self.context_layer then
				table.remove(self.layer, i)
				break
			end
		end
		self.context_layer = nil
	end

	-- restore default menu and screen if defined
	if self.default_menu then
		-- copy default_menu into a fresh table to avoid mutations/duplication
		self.menu = {}
		for _, item in ipairs(self.default_menu) do
			table.insert(self.menu, item)
		end
		self.cursor_positions = #self.menu
		self.cursor = util.clamp(self.cursor or 1, 1, math.max(1, self.cursor_positions))
	else
		self.menu = {}
		self.cursor = 1
		self.cursor_positions = 0
	end

	if self.default_screen then
		-- reapply default screen as context layer
		self.context_layer = self.default_screen
		table.insert(self.layer, self.context_layer)
	end

	self.context_helper_labels = self.default_helper_labels
	self:cancel_helper_toast()
	if self.default_disable_highlight ~= nil then
		self.disable_highlight = self.default_disable_highlight
	else
		self.disable_highlight = false
	end

	-- Reset the context functions to default
	for binding, func in pairs(self.default) do
		self.context[binding] = func
	end

	for i, c in pairs(self.components) do
		local component = c:get_component()
		if c.set_grid then c:set_grid(component) end
	end

	App.screen_dirty = true
end

-- cancel_toast
function Mode:cancel_toast()
	if self.toast_clock then
		clock.cancel(self.toast_clock)
		self.toast_clock = nil
	end

	if self.toast_layer then
		for i, layer in ipairs(self.layer) do
			if layer == self.toast_layer then
				table.remove(self.layer, i)
				break
			end
		end
		self.toast_layer = nil
	end
	App.screen_dirty = true
end

function Mode:reset_timeout()
	if self.context_clock then self.reset_timeout_count = true end
end

function Mode:context_timeout(timeout, callback)
	if self.context_clock then
		clock.cancel(self.context_clock)
		self.context_clock = nil
	end

	local count = 0

	self.context_clock = clock.run(function()
		while count < timeout do
			if self.reset_timeout_count then
				count = 0
				self.reset_timeout_count = false
			end

			clock.sleep(1 / 24)
			count = count + (1 / 24)
		end

		self:cancel_context()

		if callback then callback() end

		self.context_clock = nil
	end)
end

-- Options is going to represent an optional third property
-- If an option is type of function, we will assume its a callback
-- If an option is a type of number, we will assume its a timeout
-- if an option is type of boolean, we will assume whether or not to use a timeout
-- if the timeout is true then we use the default timeout
function Mode:use_context(context, screen, option)
	local callback
	local timeout
	local menu_override = false
	local set_default = false
	local append = false
	local menu_context = context.menu or nil
	local cursor = 1
	if type(option) == 'table' then
		timeout = option.timeout
		callback = option.callback
		menu_override = option.menu_override
		set_default = option.set_default or false
		append = option.append or false
		cursor = option.cursor or 1
		if timeout == true then timeout = self.timeout end
	elseif type(option) == 'number' then
		timeout = option
	elseif type(option) == 'function' then
		callback = option
	elseif type(option) == 'boolean' then
		if option then timeout = self.timeout end
	end

	-- Cancel any existing context
	self:cancel_context()

	-- Cancel any existing toast when a new context is started
	self:cancel_toast()

	-- Apply menu context to this mode
	if menu_context then
		-- Replace menu by default; only append when explicitly requested
		local should_reset = true
		if append == true then should_reset = false end
		-- Backward compatibility: reset when menu_override or set_default are used
		if menu_override or set_default then should_reset = true end
		if should_reset then self.menu = {} end
		for _, menu_item in ipairs(menu_context) do
			table.insert(self.menu, menu_item)
		end
		self.cursor = cursor
		self.cursor_positions = #self.menu
	end

	if set_default and menu_context then
		-- store default baseline
		self.default_menu = {}
		for _, item in ipairs(menu_context) do
			table.insert(self.default_menu, item)
		end
		self.default_screen = screen
		self.default_disable_highlight = context.disable_highlight
		self.default_helper_labels = context.default_helper_labels
	end

	if context.disable_highlight ~= nil then
		self.disable_highlight = context.disable_highlight
	else
		self.disable_highlight = false
	end

	-- Insert the context screen and keep a reference to it
	self.context_layer = screen
	table.insert(self.layer, screen)

	self.context_helper_labels = context.default_helper_labels or self.default_helper_labels
	local helper_duration = App.alt_down and false or 2.5
	self:update_helper_toast({ duration = helper_duration })

	App.screen_dirty = true

	if timeout then self:context_timeout(timeout, callback) end

	for binding, func in pairs(context) do
		if func and type(func) == 'function' then -- Ensure function exists and is callable
			self.context[binding] = function(a, b)
				func(a, b)
				if timeout then self:context_timeout(timeout, callback) end
			end
		end
	end
end

function Mode:toast(toast_text, draw_fn)
	draw_fn = draw_fn or function(t) UI:draw_toast(t) end

	local function toast_screen() draw_fn(toast_text) end

	-- Cancel any existing toast
	self:cancel_toast()

	-- Insert the new toast screen and keep a reference to it
	self.toast_layer = toast_screen
	table.insert(self.layer, toast_screen)

	local count = 0
	self.toast_clock = clock.run(function()
		while count < self.timeout do
			clock.sleep(1 / 15)
			count = count + (1 / 15)
		end
		-- Remove the toast layer
		self:cancel_toast()
	end)

	App.screen_dirty = true
end

function Mode:register_params(o)
	--local mode = 'mode_' .. o.id .. '_'
end

-- Methods
function Mode:register_screens()
	self.layer = { App.default.screen }

	-- Register screen functions
	if self.screen and type(self.screen) == 'function' then table.insert(self.layer, self.screen) end
end

function Mode:enable()
	if self.enabled then
		return -- Prevent re-enabling
	end

	self.track = App.current_track

	for _, component in ipairs(self.components) do
		component.mode = self
		component:enable()
	end

	-- Register component screen functions into the layer system
	self:register_screens()

	self.grid:enable()
	self.enabled = true

	if self.id then
		self.mode_pads.led[4 + self.id][9] = 3
		self.mode_pads:refresh()
	end

	if self.load_event ~= nil then self:load_event() end

	if self.row_event ~= nil then self:on('row', self.row_event) end

	if self.arrow_event ~= nil then self:on('arrow', self.arrow_event) end

	self:emit('enable')
	screen_dirty = true
end

function Mode:disable()
	-- Cancel any active context or toast
	self:cancel_context()
	self:cancel_toast()
	self.enabled = false
	-- reset alt
	self:emit('alt_reset')

	self.grid:disable()

	-- First, execute all cleanup functions
	for i, cleanup in ipairs(self.cleanup_functions) do
		cleanup()
	end
	self.cleanup_functions = {}

	-- Then disable each component and clear its mode reference
	for i, component in ipairs(self.components) do
		component:disable()
		component.mode = nil
	end

	self.event_listeners = {}
	App.screen_dirty = true
end

return Mode
