local path_name = 'Foobar/lib/'
local Grid = require(path_name .. 'grid')
local utilities = require(path_name .. 'utilities')

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
		self:update_helper_toast()
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

	self:update_helper_toast()
	App.screen_dirty = true
end

function Mode:use_menu(ctx, d)
	local item = self.menu and self.menu[self.cursor]
	if item and type(item[ctx]) == 'function' then item[ctx](d) end
	-- Reset helper toast to reflect any state changes (e.g., pending confirmation)
	local helper_duration = App.alt_down or 5
	self:update_helper_toast()
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

	self.base_layers = o.layer or {}
	self.base_layers[1] = App.default.screen
	self.context_layers = {}
	self.interrupt_layers = {}
	self.context_layer = nil
	self.context_layer_is_interrupt = false
	self.toast_layer = nil
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
	self.context_stack = {}

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

	-- Support multi-entry pending bundles (e.g., combo left/right)
	if pending.entries and type(pending.entries) == 'table' then
		if revert then
			for _, entry in pairs(pending.entries) do
				if entry.param_id and entry.original ~= nil and entry.pending ~= nil and entry.pending ~= entry.original then
					Registry.set(entry.param_id, entry.original, 'menu_bump_revert', entry.callback, true)
				end
			end
		end
	else
		-- Backward compatibility: single pending value
		if revert and pending.param_id and pending.original ~= nil and pending.pending ~= nil and pending.pending ~= pending.original then
			Registry.set(pending.param_id, pending.original, 'menu_bump_revert', pending.callback, true)
		end
	end

	self.pending_confirmation = nil
end

function Mode:confirm_pending_confirmation()
	local pending = self.pending_confirmation
	if not pending then return false end

	-- Multi-entry confirm (combo rows)
	if pending.entries and type(pending.entries) == 'table' then
		for _, entry in pairs(pending.entries) do
			local param_id = entry.param_id
			local value = entry.pending
			local callback = entry.callback
			if value ~= nil then
				if entry.original ~= nil and entry.original ~= value then params:set(param_id, entry.original, true) end
				Registry.set(param_id, value, 'menu_bump_confirm', callback)
			end
		end
		if pending.item then pending.item.pending_confirmation = nil end
		self.pending_confirmation = nil
		return true
	end

	-- Single-entry fallback
	if not pending.param_id then return false end
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

	-- If there is an existing pending for a different item, revert it
	if pending and pending.item and entry.item and pending.item ~= entry.item then
		self:clear_pending_confirmation({ revert = true })
		pending = nil
	end

	-- Initialize pending bundle if needed
	if not pending then
		pending = { entries = {} }
		self.pending_confirmation = pending
	end

	-- Attach item reference and index for UI state once
	if entry.item then
		pending.item = entry.item
		entry.item.pending_confirmation = true
		if pending.item_index == nil then
			for idx, menu_item in ipairs(self.menu or {}) do
				if menu_item == pending.item then
					pending.item_index = idx
					break
				end
			end
		end
	end

	-- Upsert this param into the bundle
	local key = param_id
	local existing = pending.entries[key]
	if not existing then
		existing = {
			param_id = param_id,
			original = entry.original_value,
		}
		pending.entries[key] = existing
	elseif existing.original == nil then
		existing.original = entry.original_value
	end
	-- Update staged value and metadata
	existing.pending = entry.new_value
	existing.callback = entry.callback
	existing.side = entry.side

	-- If the staged value equals the original, drop this entry
	if existing.original ~= nil and existing.pending ~= nil and existing.original == existing.pending then pending.entries[key] = nil end

	-- If bundle is empty, clear the pending flag
	local has_any = false
	for _, _ in pairs(pending.entries) do
		has_any = true
		break
	end
	if not has_any then self:clear_pending_confirmation({ revert = false }) end
end

function Mode:cancel_helper_toast()
	if self.helper_toast_clock then
		clock.cancel(self.helper_toast_clock)
		self.helper_toast_clock = nil
	end

	if self.helper_layer then self.helper_layer = nil end
	App.screen_dirty = true
end

function Mode:show_helper_toast(helper_labels, duration)
	if not helper_labels then
		self:cancel_helper_toast()
		return
	end

	-- Validate at least once to avoid showing empty helper toasts
	local resolved = helper_labels
	if type(resolved) == 'function' then resolved = resolved() end
	if type(resolved) ~= 'table' then return end
	if next(resolved) == nil then return end

	local function resolve_labels()
		local payload = helper_labels
		if type(payload) == 'function' then payload = payload() end
		if type(payload) ~= 'table' or next(payload) == nil then payload = resolved end
		return payload
	end

	if self.helper_toast_clock then
		clock.cancel(self.helper_toast_clock)
		self.helper_toast_clock = nil
	end

	local effective_duration = duration
	if effective_duration == nil then effective_duration = self.timeout end
	if effective_duration == true then effective_duration = self.timeout end

	if effective_duration ~= false and effective_duration ~= nil then
		local total = effective_duration
		self.helper_toast_clock = clock.run(function()
			local elapsed = 0
			while elapsed < total do
				clock.sleep(1 / 15)
				elapsed = elapsed + (1 / 15)
			end
			self:cancel_helper_toast()
		end)
	end

	self.helper_layer = function() UI:draw_helper_toast(resolve_labels()) end

	App.screen_dirty = true
end

function Mode:update_helper_toast()
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

	-- Auto-provide default press_fn_3 when submenu is available and active, unless overridden
	if item and merged.press_fn_3 == nil then
		-- If pending confirmation, prefer 'confirm' unless explicitly overridden above
		if item.pending_confirmation then
			merged.press_fn_3 = 'confirm'
		else
			-- Resolve has_submenu (boolean or function)
			local has_sub = false
			if type(item.has_submenu) == 'function' then
				local ok, res = pcall(item.has_submenu, item)
				has_sub = ok and (res ~= false)
			else
				has_sub = (item.has_submenu == true)
			end

			-- Respect gating via can_press when provided
			if has_sub then
				local can_press = true
				if item.can_press ~= nil then
					if type(item.can_press) == 'function' then
						local ok, res = pcall(item.can_press, item)
						can_press = ok and (res ~= false)
					else
						can_press = (item.on_press ~= nil)
					end
				end
				if can_press then merged.press_fn_3 = '\u{25ba}' end
			end
		end
	end

	local duration = true

	if self:has_pending_confirmation() or self.toast_clock then duration = false end

	if next(merged) then
		self:show_helper_toast(merged, duration)
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
	for _, layer in ipairs(self.base_layers) do
		layer(self)
	end

	for _, layer in ipairs(self.context_layers) do
		layer(self)
	end

	for _, layer in ipairs(self.interrupt_layers) do
		layer(self)
	end

	if self.helper_layer then self.helper_layer(self) end

	if self.toast_layer then self.toast_layer(self) end
end

function Mode:_remove_layer(layers, target)
	if not layers or not target then return end
	for i = #layers, 1, -1 do
		if layers[i] == target then
			table.remove(layers, i)
			break
		end
	end
end

-- Added cancel_context method to handle context cleanup
function Mode:cancel_context(opts)
	opts = opts or {}
	local should_pop = (opts.pop ~= false)
	if self.context_clock then
		clock.cancel(self.context_clock)
		self.context_clock = nil
	end

	-- Remove the context screen from the appropriate layer collection
	if self.context_layer then
		if self.context_layer_is_interrupt then
			self:_remove_layer(self.interrupt_layers, self.context_layer)
		else
			self:_remove_layer(self.context_layers, self.context_layer)
		end
	end
	self.context_layer = nil
	self.context_layer_is_interrupt = false

	-- If invoked for timeout/pop semantics, try restoring prior context from stack
	if should_pop and self.context_stack and #self.context_stack > 0 then
		local previous = table.remove(self.context_stack)
		local prev_options = previous.options or {}
		-- Ensure we restore prior cursor position
		if previous.cursor ~= nil then prev_options.cursor = previous.cursor end
		-- Defer to use_context to reapply prior context cleanly
		-- Prevent recursive pop during this restoration
		self:use_context(previous.context, previous.screen, prev_options)
		return
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
		self:_remove_layer(self.context_layers, self.default_screen)
		self.context_layer = self.default_screen
		self.context_layer_is_interrupt = false
		table.insert(self.context_layers, self.context_layer)
	end

	self.context_helper_labels = self.default_helper_labels
	self:cancel_helper_toast()
	if self.default_disable_highlight ~= nil then
		self.disable_highlight = self.default_disable_highlight
	else
		self.disable_highlight = false
	end

	-- Reset the context functions to default App handlers
	local restored = {}
	for binding, func in pairs(self.default) do
		restored[binding] = func
	end

	-- Reapply Default-mode baseline bindings (captured when set_default was used)
	if self.default_bindings then
		for binding, func in pairs(self.default_bindings) do
			restored[binding] = func
		end
	end

	self.context = restored

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

	if self.toast_layer then self.toast_layer = nil end
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
	local menu_context = context.menu
	local cursor = 1
	local interrupt = false
	if type(option) == 'table' then
		timeout = option.timeout
		callback = option.callback
		menu_override = option.menu_override
		set_default = option.set_default or false
		append = option.append or false
		cursor = option.cursor or 1
		interrupt = option.interrupt == true
		if timeout == true then timeout = self.timeout end
	elseif type(option) == 'number' then
		timeout = option
	elseif type(option) == 'function' then
		callback = option
	elseif type(option) == 'boolean' then
		if option then timeout = self.timeout end
	end

	-- Snapshot current active context (and its cursor) BEFORE we mutate any state,
	-- so overlays can restore precisely.
	local prior_snapshot = nil
	if self.active_context_info then
		prior_snapshot = {
			context = self.active_context_info.context,
			screen = self.active_context_info.screen,
			options = self.active_context_info.options or {},
			cursor = self.cursor,
		}
	end

	-- If this is the same temporary overlay context already active, just
	-- reset its timeout instead of recreating the context (which would
	-- continually re-arm and prevent timeout from ever completing)
	if timeout and self.active_context_info then
		local is_same_context = (self.active_context_info.context == context) and (self.context_layer == screen)
		if is_same_context then
			self:reset_timeout()
			-- ensure redraw and helper labels refresh when reusing same overlay
			local duration = false
			self:update_helper_toast({ duration = duration })
			App.screen_dirty = true
			return
		end
	end

	-- For interrupt overlays, keep existing context/layers and leave active toast running
	if not interrupt then
		-- Cancel any existing context, but do not pop the previous one here
		-- (we want to preserve it on the stack for overlays)
		self:cancel_context({ pop = false })
	end

	-- Compose input routing table for this context:
	-- - For interrupt overlays: start from current context so underlying controls still work
	-- - For normal contexts: reset to App defaults; specific bindings will override
	if interrupt then
		local composed = {}
		for k, v in pairs(self.context or {}) do
			composed[k] = v
		end
		self.context = composed
	else
		self.context = {}
		for binding, func in pairs(self.default) do
			self.context[binding] = func
		end
	end

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
		-- For interrupt overlays, do not change the cursor selection
		if not interrupt then self.cursor = cursor end
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

		-- Capture baseline function bindings from this context so we can fully
		-- restore Default-mode behavior (enc1, press_fn_3, etc.) after overlays
		self.default_bindings = {}
		for key, value in pairs(context) do
			if type(value) == 'function' then self.default_bindings[key] = value end
		end
	end

	if context.disable_highlight ~= nil then
		self.disable_highlight = context.disable_highlight
	else
		self.disable_highlight = false
	end

	-- Insert the context screen and keep a reference to it
	self.context_layer = screen
	self.context_layer_is_interrupt = interrupt
	if interrupt then
		self.interrupt_layers = self.interrupt_layers or {}
		self:_remove_layer(self.interrupt_layers, screen)
		table.insert(self.interrupt_layers, screen)
	else
		self.context_layers = {}
		table.insert(self.context_layers, screen)
	end

	self.context_helper_labels = context.default_helper_labels or self.default_helper_labels

	local helper_duration = false
	self:update_helper_toast({ duration = helper_duration })

	App.screen_dirty = true

	if timeout then self:context_timeout(timeout, callback) end

	-- Only provide a default back (K2) handler for temporary overlays.
	if timeout and not context['press_fn_2'] then context['press_fn_2'] = function()
		self:cancel_context()
		if callback then callback() end
	end end

	for binding, func in pairs(context) do
		if func and type(func) == 'function' then -- Ensure function exists and is callable
			self.context[binding] = function(a, b)
				func(a, b)
				if timeout then self:reset_timeout() end
			end
		end
	end

	-- Track the active context so we can push/pop around temporary overlays
	local applied_options = {}
	if type(option) == 'table' then
		applied_options = option
	else
		applied_options = {
			timeout = timeout,
			callback = callback,
			menu_override = menu_override,
			set_default = set_default,
			append = append,
		}
	end
	-- Always store the current cursor with the context snapshot
	applied_options.cursor = self.cursor

	-- If this context is a temporary overlay (timeout set), push the previous active
	-- context onto a stack so we can restore it on timeout, using the cursor at time of overlay
	if timeout and prior_snapshot then table.insert(self.context_stack, prior_snapshot) end
	self.active_context_info = { context = context, screen = screen, options = applied_options, cursor = self.cursor }
end

function Mode:toast(toast_text, draw_or_opts, opts)
	local draw_fn = function(t, d) UI:draw_toast(t, d) end
	local duration = self.timeout

	if type(draw_or_opts) == 'function' then
		draw_fn = draw_or_opts
		if opts and opts.timeout ~= nil then duration = opts.timeout end
	elseif type(draw_or_opts) == 'table' then
		if type(draw_or_opts.draw_fn) == 'function' then draw_fn = draw_or_opts.draw_fn end
		if draw_or_opts.timeout ~= nil then duration = draw_or_opts.timeout end
	end

	self.completion = 0
	local function toast_screen()
		local completion = self.completion
		draw_fn(toast_text, completion)
	end

	-- Cancel any existing toast
	self:cancel_toast()

	-- Insert the new toast screen and keep a reference to it
	self.toast_layer = toast_screen
	if duration ~= false then
		if duration == true then duration = self.timeout end
		local count = 0
		self.toast_clock = clock.run(function()
			while count < duration do
				clock.sleep(1 / 15)
				count = count + (1 / 15)
				self.completion = count / duration
				App.screen_dirty = true
			end
			-- Remove the toast layer
			self:cancel_toast()
		end)
	else
		self.toast_clock = nil
	end

	App.screen_dirty = true
end

function Mode:register_params(o)
	--local mode = 'mode_' .. o.id .. '_'
end

-- Methods
function Mode:register_screens()
	self.base_layers = { App.default.screen }

	-- Register screen functions
	if self.screen and type(self.screen) == 'function' then table.insert(self.base_layers, self.screen) end
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
	self:cancel_context({ pop = false })
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

function Mode:has_active_menu()
	local indices = self:get_visible_indices()
	if #indices == 0 then return false end
	for _, idx in ipairs(indices) do
		local it = self.menu[idx]
		if it and (it.enc2 or it.enc3 or it.is_editable or it.has_press) then return true end
	end
	return false
end

return Mode
