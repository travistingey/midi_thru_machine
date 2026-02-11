-- ============================================================================
-- SYNC MANAGER
-- Consolidates multiple sync action queues into a single manager with named slots
--
-- Replaces the multiple separate sync queues (sync_action_queue, scrub_sync_queue,
-- _clipgrid_sync_queue) with a unified interface.
--
-- All ticks are 1-based (Lua convention):
--   - First clock event = tick 1
--   - Sync boundaries align with tick multiples
-- ============================================================================

local flags = require('Foobar/lib/utilities/flags')
local SequenceUtils = require('Foobar/lib/utilities/sequence_utils')

local SyncManager = {}
SyncManager.__index = SyncManager

-- Create a new SyncManager
-- @param component table The component this manager belongs to
-- @param default_sync_length_fn function Optional function to get default sync length: (component) -> number
-- @return SyncManager
function SyncManager.new(component, default_sync_length_fn)
	local self = setmetatable({}, SyncManager)
	self.component = component
	self.default_sync_length_fn = default_sync_length_fn
		or function(c)
			-- Default: try to get from buffer, fall back to 1 bar
			if c.buffer and c.buffer.action_sync_length then
				return c.buffer.action_sync_length
			elseif c.action_sync_length then
				return c.action_sync_length
			else
				return (App and App.ppqn or 96) * 4 -- 1 bar default
			end
		end
	self.slots = {} -- Named action slots
	return self
end

-- ============================================================================
-- SYNC BOUNDARY CALCULATIONS
-- ============================================================================

-- Get the next sync boundary tick
-- @param sync_length number Sync length in ticks
-- @param current_tick number Current tick (defaults to App.tick)
-- @return number Next sync boundary tick
function SyncManager:get_next_sync_tick(sync_length, current_tick)
	current_tick = current_tick or (App and App.tick) or 1
	return SequenceUtils.get_next_sync_tick(sync_length, current_tick)
end

-- Check if we should wait for sync
-- @param sync_length number Sync length in ticks (0 = disabled)
-- @param current_tick number Current tick (defaults to App.tick)
-- @return boolean True if we should wait
function SyncManager:should_wait_for_sync(sync_length, current_tick) return SequenceUtils.should_wait_for_sync(sync_length, current_tick) end

-- ============================================================================
-- ACTION QUEUE MANAGEMENT
-- ============================================================================

-- Queue an action in a named slot
-- Replaces any existing action in that slot
-- @param slot_name string Name of the slot (e.g., 'scrub', 'clip_load', 'recording')
-- @param action_fn function Function to execute: (component, action_data) -> void
-- @param action_data table|nil Optional data to pass to action_fn
-- @param sync_length number|nil Sync length in ticks (uses default if nil)
function SyncManager:queue(slot_name, action_fn, action_data, sync_length)
	sync_length = sync_length or self.default_sync_length_fn(self.component)
	local current_tick = (App and App.tick) or 1
	local next_sync_tick = self:get_next_sync_tick(sync_length, current_tick)

	if flags.debug_sync then
		print('SyncManager: Queue action in slot "' .. slot_name .. '"')
		print('  Current App.tick: ' .. current_tick)
		print('  Sync length: ' .. sync_length)
		print('  Next sync tick: ' .. next_sync_tick .. ' (in ' .. (next_sync_tick - current_tick) .. ' ticks)')
	end

	self.slots[slot_name] = {
		action_fn = action_fn,
		action_data = action_data,
		sync_tick = next_sync_tick,
		sync_length = sync_length,
	}

	-- If already at sync boundary, execute immediately
	if not self:should_wait_for_sync(sync_length, current_tick) then
		if flags.debug_sync then print('SyncManager: Already on sync boundary, executing "' .. slot_name .. '" immediately') end
		self:execute_slot(slot_name)
	end
end

-- Queue an action that executes immediately (no sync)
-- @param slot_name string Name of the slot
-- @param action_fn function Function to execute
-- @param action_data table|nil Optional data
function SyncManager:queue_immediate(slot_name, action_fn, action_data)
	self.slots[slot_name] = {
		action_fn = action_fn,
		action_data = action_data,
		sync_tick = (App and App.tick) or 1,
		sync_length = 0,
	}
	self:execute_slot(slot_name)
end

-- Clear a specific slot
-- @param slot_name string Name of the slot to clear
function SyncManager:clear(slot_name) self.slots[slot_name] = nil end

-- Clear all slots
function SyncManager:clear_all() self.slots = {} end

-- Check if a slot has a pending action
-- @param slot_name string Name of the slot
-- @return boolean True if action is pending
function SyncManager:has_pending(slot_name) return self.slots[slot_name] ~= nil end

-- Get pending action info for a slot
-- @param slot_name string Name of the slot
-- @return table|nil Action info or nil
function SyncManager:get_pending(slot_name) return self.slots[slot_name] end

-- ============================================================================
-- EXECUTION
-- ============================================================================

-- Execute a specific slot if its sync tick has been reached
-- @param slot_name string Name of the slot
-- @return boolean True if action was executed
function SyncManager:execute_slot(slot_name)
	local slot = self.slots[slot_name]
	if not slot then return false end

	local current_tick = (App and App.tick) or 1
	if current_tick >= slot.sync_tick then
		if flags.debug_sync then print('SyncManager: Execute "' .. slot_name .. '" at App.tick: ' .. current_tick .. ' (target was: ' .. slot.sync_tick .. ')') end

		-- Execute the action
		slot.action_fn(self.component, slot.action_data)

		-- Clear the slot
		self.slots[slot_name] = nil
		return true
	end

	return false
end

-- Execute all slots that have reached their sync tick
-- Should be called on each clock tick
-- @return number Count of actions executed
function SyncManager:execute_all()
	local current_tick = (App and App.tick) or 1
	local executed_count = 0

	-- Collect slots to execute (to avoid modifying while iterating)
	local to_execute = {}
	for slot_name, slot in pairs(self.slots) do
		if current_tick >= slot.sync_tick then table.insert(to_execute, slot_name) end
	end

	-- Execute collected slots
	for _, slot_name in ipairs(to_execute) do
		local slot = self.slots[slot_name]
		if slot then
			if flags.debug_sync then print('SyncManager: Execute "' .. slot_name .. '" at App.tick: ' .. current_tick .. ' (target was: ' .. slot.sync_tick .. ')') end

			slot.action_fn(self.component, slot.action_data)
			self.slots[slot_name] = nil
			executed_count = executed_count + 1
		end
	end

	return executed_count
end

-- ============================================================================
-- UTILITY METHODS
-- ============================================================================

-- Get list of all pending slot names
-- @return table Array of slot names
function SyncManager:get_pending_slots()
	local names = {}
	for name, _ in pairs(self.slots) do
		table.insert(names, name)
	end
	return names
end

-- Get count of pending actions
-- @return number Count
function SyncManager:pending_count()
	local count = 0
	for _, _ in pairs(self.slots) do
		count = count + 1
	end
	return count
end

-- Check if any actions are pending
-- @return boolean True if any actions pending
function SyncManager:has_any_pending() return next(self.slots) ~= nil end

return SyncManager
