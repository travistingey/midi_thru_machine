-- lib/utilities/Registry.lua
--
-- Clean parameter tracing utilities that don't interfere with the environment.
-- This module provides manual tracing functions that can be called explicitly
-- where needed, without any global monkey-patching.
--
-- Usage:
--   local Registry = require('Foobar/lib/utilities/registry')
--   Registry.log_registration('my_param', 'add_number')
--   Registry.log_set_action('my_param')
--   Registry.log_value_change('my_param', 42, 'user_input')
-----------------------------------------------------------------------------

local Tracer = require('Foobar/lib/utilities/tracer')
local flags = require('Foobar/lib/utilities/flags')

local Registry = {}

-- Helper function to detect calling component from stack trace
local function detect_calling_component()
	-- Look through multiple stack levels to find the actual calling component
	for level = 3, 10 do -- Check levels 3-10
		local info = debug.getinfo(level, 'S')

		if not info then break end

		local source = info.source
		if not source then break end

		-- Skip Registry.lua itself
		if string.find(source, 'Registry.lua') then goto continue end

		-- Extract component name from file path
		local component_match = string.match(source, '/([^/]+)%.lua$')
		if component_match and component_match ~= 'registry' then return component_match end

		-- Try to match specific patterns
		if string.find(source, 'track/') then
			local track_component = string.match(source, 'track/([^/]+)%.lua$')
			if track_component then return track_component end
		end

		if string.find(source, 'components/') then
			local component = string.match(source, 'components/([^/]+)%.lua$')
			if component then return component end
		end

		::continue::
	end

	return nil
end

-- Helper function to check component filtering with hierarchy
local function check_component_filtering(component_name)
	if not component_name or #flags.trace_config.components == 0 then
		return true -- No filtering if no component or no component filter
	end

	-- Check exact component match
	for _, allowed_component in ipairs(flags.trace_config.components) do
		if allowed_component == component_name then return true end
	end

	-- Check hierarchical matches
	if component_name == 'track' then
		-- Track components are always allowed if 'track' is in the filter
		for _, allowed_component in ipairs(flags.trace_config.components) do
			if allowed_component == 'track' then return true end
		end
	elseif component_name == 'trackcomponent' then
		-- TrackComponent is allowed if 'trackcomponent' is in the filter
		for _, allowed_component in ipairs(flags.trace_config.components) do
			if allowed_component == 'trackcomponent' then return true end
		end
	end

	return false
end

-------------------------------------------------------------------------------
-- Core logging functions
-------------------------------------------------------------------------------

function Registry.log_registration(param_id, registration_type)
	if not flags.trace_config.load_trace then return end

	-- Extract component ID from param_id for filtering
	local component_id = nil
	local component_type = nil

	-- Try different component ID patterns
	local track_match = string.match(param_id, 'track_(%d+)_') or (registration_type == 'add_group' and string.match(param_id, 'Track (%d+)'))
	if track_match then
		component_id = tonumber(track_match)
		component_type = 'track'
	else
		local scale_match = string.match(param_id, 'scale_(%d+)_')
		if scale_match then
			component_id = tonumber(scale_match)
			component_type = 'scale'
		else
			local device_match = string.match(param_id, 'device_(%d+)_')
			if device_match then
				component_id = tonumber(device_match)
				component_type = 'device'
			end
		end
	end

	-- Check ID filtering for load-time registration
	if component_id and #flags.trace_config.tracks > 0 then
		local id_allowed = false
		for _, allowed_id in ipairs(flags.trace_config.tracks) do
			if allowed_id == component_id then
				id_allowed = true
				break
			end
		end
		if not id_allowed then return end
	end

	-- Detect calling component for filtering
	local calling_component = detect_calling_component()

	-- Check component filtering for registration
	if not check_component_filtering(calling_component) then return end

	Tracer.load():log('param:register', '%s %s', tostring(registration_type), tostring(param_id))
end

function Registry.log_set_action(param_id)
	if not flags.trace_config.load_trace then return end

	-- Extract component ID from param_id for filtering
	local component_id = nil
	local component_type = nil

	-- Try different component ID patterns
	local track_match = string.match(param_id, 'track_(%d+)_')
	if track_match then
		component_id = tonumber(track_match)
		component_type = 'track'
	else
		local scale_match = string.match(param_id, 'scale_(%d+)_')
		if scale_match then
			component_id = tonumber(scale_match)
			component_type = 'scale'
		else
			local device_match = string.match(param_id, 'device_(%d+)_')
			if device_match then
				component_id = tonumber(device_match)
				component_type = 'device'
			end
		end
	end

	-- Check ID filtering for set_action registration
	if component_id and #flags.trace_config.tracks > 0 then
		local id_allowed = false
		for _, allowed_id in ipairs(flags.trace_config.tracks) do
			if allowed_id == component_id then
				id_allowed = true
				break
			end
		end
		if not id_allowed then return end
	end

	-- Detect calling component for filtering
	local calling_component = detect_calling_component()

	-- Check component filtering for set_action
	if not check_component_filtering(calling_component) then return end

	Tracer.load():log('param:set_action', '%s', tostring(param_id))
end

function Registry.log_value_change(param_id, value, source)
	if not flags.trace_config.params then return end

	-- Extract component ID from param_id for filtering
	local component_id = nil
	local component_type = nil

	-- Try different component ID patterns
	local track_match = string.match(param_id, 'track_(%d+)_')
	if track_match then
		component_id = tonumber(track_match)
		component_type = 'track'
	else
		local scale_match = string.match(param_id, 'scale_(%d+)_')
		if scale_match then
			component_id = tonumber(scale_match)
			component_type = 'scale'
		else
			local device_match = string.match(param_id, 'device_(%d+)_')
			if device_match then
				component_id = tonumber(device_match)
				component_type = 'device'
			end
		end
	end

	-- Check ID filtering (generalized from track filtering)
	if component_id and #flags.trace_config.tracks > 0 then
		local id_allowed = false
		for _, allowed_id in ipairs(flags.trace_config.tracks) do
			if allowed_id == component_id then
				id_allowed = true
				break
			end
		end
		if not id_allowed then return end
	end

	-- Detect calling component for filtering
	local calling_component = detect_calling_component()

	-- Check component filtering
	if not check_component_filtering(calling_component) then return end

	-- Determine log tag based on source
	local log_tag = 'param:change'
	local log_template = '%s'
	local log_data = { tostring(source), tostring(value) }
	local previous_value = params:get(param_id)
	if source == 'set_action' then
		log_tag = 'param:set'
		log_template = '%s: %s → %s'
		log_data = { tostring(param_id), tostring(previous_value), tostring(value) }
	elseif source and source ~= 'set_action' then
		log_tag = 'param:caller'
		log_data = { tostring(source) }
	end

	Tracer.event({
		context_type = 'param',
		param_id = param_id,
		source = source,
		track_id = component_id, -- Use component_id for backward compatibility
		component_name = calling_component,
		component_type = component_type,
	}):log(log_tag, log_template, table.unpack(log_data))
end

-------------------------------------------------------------------------------
-- Convenience wrapper for set_action that includes tracing
-------------------------------------------------------------------------------
function Registry.set_action(param_id, callback)
	Registry.log_set_action(param_id)

	if not callback then return params:set_action(param_id, nil) end

	local wrapped = function(value, ...)
		Registry.log_value_change(param_id, value, 'set_action')
		return callback(value, ...)
	end

	return params:set_action(param_id, wrapped)
end

-------------------------------------------------------------------------------
-- Helper for tracking parameter registration with automatic ID extraction
-------------------------------------------------------------------------------
function Registry.add(registration_type, ...)
	local param_id = select(1, ...)
	Registry.log_registration(param_id, registration_type)
	return params[registration_type](params, ...)
end

-------------------------------------------------------------------------------
-- Traced wrapper for params:set() that logs the change and then sets the value
-------------------------------------------------------------------------------

function Registry.set(param_id, value, source, callback, silent)
	Registry.log_value_change(param_id, value, source or 'traced_set')

	-- Support calling forms where callback is omitted and silent is passed as 4th arg
	if silent == nil and type(callback) == 'boolean' then
		silent, callback = callback, nil
	end

	local result
	if silent ~= nil then
		result = params:set(param_id, value, silent)
	else
		result = params:set(param_id, value)
	end

	if type(callback) == 'function' then callback(result) end
	return result
end

-------------------------------------------------------------------------------
-- Menu helpers: centralize menu item composition and param bumping
-------------------------------------------------------------------------------

-- local clamp that does not depend on util
local function _clamp(v, lo, hi)
	if lo ~= nil and v < lo then v = lo end
	if hi ~= nil and v > hi then v = hi end
	return v
end

Registry.menu = {}

-- Format a param value using native formatter/string()
function Registry.menu.format_value(id)
	local s = params:string(id)
	if s ~= nil then return s end
	local v = params:get(id)
	return tostring(v)
end

-- Get a human label for a param id
function Registry.menu.label(id)
	local p = params:lookup_param(id)
	if p and p.name then return p.name end
	return id
end

-- Increment/decrement a param value based on its type
function Registry.menu.bump(id, delta, step, callback, item_context, side)
	local p = params:lookup_param(id)
	if not p then return end

	local t = p.t or p.type or ''

	local cur = params:get(id)
	local new = cur

	if t == 'number' then
		local s = step or 1
		local lo = p.min
		local hi = p.max
		new = _clamp(cur + (delta * s), lo, hi)
	elseif t == 'option' then
		local count = (p.options and #p.options) or 0
		if count > 0 then new = _clamp(cur + delta, 1, count) end
	elseif t == 'binary' then
		if delta ~= 0 then new = (cur > 0) and 0 or 1 end
	elseif t == 'control' then
		local cs = p.controlspec
		local s = step or (cs and cs.step) or 0.01
		local lo = cs and cs.min or nil
		local hi = cs and cs.max or nil
		new = _clamp(cur + (delta * s), lo, hi)
	else
		-- Fallback: treat as numeric
		new = cur + delta
	end

	if new == cur then return end

	local requires_confirmation = false
	if item_context then
		if side == 'left' and item_context.requires_confirmation_left ~= nil then
			requires_confirmation = item_context.requires_confirmation_left
		elseif side == 'right' and item_context.requires_confirmation_right ~= nil then
			requires_confirmation = item_context.requires_confirmation_right
		else
			requires_confirmation = item_context.requires_confirmation
		end

		if type(requires_confirmation) == 'function' then requires_confirmation = requires_confirmation(item_context, side) end
	end

	local mode = App.mode and App.mode[App.current_mode]
	if requires_confirmation and mode and mode.prepare_pending_confirmation then
		mode:prepare_pending_confirmation({
			item = item_context,
			param_id = id,
			original_value = cur,
			new_value = new,
			callback = callback,
			side = side,
		})
		Registry.set(id, new, 'menu_bump_pending', callback, true)
	else
		Registry.set(id, new, 'menu_bump', callback)
	end
end

-- One-param menu row helper
function Registry.menu.make_item(id, opts)
	opts = opts or {}

	local item = {
		icon = opts.icon,
		label = opts.label_fn or opts.label or function() return Registry.menu.label(id) end,
		value = opts.value_fn or opts.value or function() return Registry.menu.format_value(id) end,
		style = opts.style,
		draw = opts.draw,
		draw_buttons = opts.draw_buttons,
		can_press = opts.can_press,
		on_set = opts.on_set,
	}

	item.requires_confirmation = opts.requires_confirmation
	item.helper_labels = opts.helper_labels
 	item.helper_labels_default = opts.helper_labels_default
	item.can_show = opts.can_show
	item.disable_highlight = opts.disable_highlight

	if opts.enc3 then
		-- Wrap custom handler to also invoke on_set after it runs
		item.enc3 = function(d)
			opts.enc3(d)
			if type(item.on_set) == 'function' then pcall(item.on_set) end
		end
	elseif not opts.disable then
		item.enc3 = function(d) Registry.menu.bump(id, d, opts.step, item.on_set, item) end
	end

	if opts.on_press then
		item.press_fn_3 = opts.on_press
		item.has_press = true
	end

	item.is_editable = (not opts.disable) and (item.enc2 ~= nil or item.enc3 ~= nil)

	return item
end

-- Two-param combo row helper (enc2=left, enc3=right)
function Registry.menu.make_combo(left_id, right_id, opts)
	opts = opts or {}
	local row = {
		icon = opts.icon,
		label = opts.left_label_fn or function() return Registry.menu.format_value(left_id) end,
		value = opts.right_value_fn or function() return Registry.menu.format_value(right_id) end,
		on_set = opts.on_set,
		style = opts.style,
		draw = opts.draw,
		draw_buttons = opts.draw_buttons,
		can_press = opts.can_press,
	}

	row.requires_confirmation = opts.requires_confirmation
	row.requires_confirmation_left = opts.left_requires_confirmation
	row.requires_confirmation_right = opts.right_requires_confirmation
	row.helper_labels = opts.helper_labels
	row.can_show = opts.can_show
	row.disable_highlight = opts.disable_highlight
	row.helper_labels_default = opts.helper_labels_default

	if row.requires_confirmation_left == nil then row.requires_confirmation_left = row.requires_confirmation end
	if row.requires_confirmation_right == nil then row.requires_confirmation_right = row.requires_confirmation end

	local function default_left_bump(d) Registry.menu.bump(left_id, d, opts.left_step, row.on_set, row, 'left') end

	local function default_right_bump(d) Registry.menu.bump(right_id, d, opts.right_step, row.on_set, row, 'right') end

	if opts.left_value_fn then
		row.enc2 = function(d)
			opts.left_value_fn(d)
			if type(row.on_set) == 'function' then pcall(row.on_set) end
		end
	elseif opts.enc2 then
		row.enc2 = function(d)
			opts.enc2(d)
			if type(row.on_set) == 'function' then pcall(row.on_set) end
		end
	else
		row.enc2 = default_left_bump
	end

	if opts.enc3 then
		row.enc3 = function(d)
			opts.enc3(d)
			if type(row.on_set) == 'function' then pcall(row.on_set) end
		end
	else
		row.enc3 = default_right_bump
	end

	if opts.on_press then
		row.press_fn_3 = opts.on_press
		row.has_press = true
	end

	row.is_editable = (row.enc2 ~= nil or row.enc3 ~= nil)

	return row
end

-- Convenience: build multiple simple items from a list of ids
function Registry.menu.make_items(ids, opts)
	local items = {}
	for _, id in ipairs(ids or {}) do
		table.insert(items, Registry.menu.make_item(id, opts))
	end
	return items
end

-------------------------------------------------------------------------------
-- Return the module
-------------------------------------------------------------------------------
return Registry
