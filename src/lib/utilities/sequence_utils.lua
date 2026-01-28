-- Sequence Utilities
-- Shared library for tick/step conversions, sync boundaries, and sync actions
-- Used by Auto, Buffer, and Clip components for consistent sequence handling

local SequenceUtils = {}

--==============================================================================
-- Sync Length Access
--==============================================================================

-- Get sync length from various sources (standardized access pattern)
-- @param buffer_component (table|nil) Buffer component with action_sync_length
-- @param component_sync_length (number|nil) Component's own sync_length
-- @param default (number) Default sync length if none found
-- @return (number) Sync length in ticks
function SequenceUtils.get_sync_length(buffer_component, component_sync_length, default)
	default = default or (App.ppqn * 4) -- Default 1 bar
	
	if buffer_component and buffer_component.action_sync_length then
		return buffer_component.action_sync_length
	elseif component_sync_length then
		return component_sync_length
	else
		return default
	end
end

--==============================================================================
-- Sync Boundary Functions
--==============================================================================

-- Calculate the next sync boundary tick based on current_tick
-- Returns the next tick that aligns with the sync boundary
-- All ticks are 1-based: first clock event happens at tick 1, data stored at tick 1+
-- @param sync_length (number) Sync length in ticks
-- @param current_tick (number) Current transport tick (defaults to App.tick, 1-based)
-- @return (number) Next sync boundary tick (1-based)
function SequenceUtils.get_next_sync_tick(sync_length, current_tick)
	current_tick = current_tick or (App.tick or 1)
	
	-- Convert to 0-based for modulo calculation (Lua modulo works on 0-based)
	local relative_tick = current_tick - 1
	
	-- If we're already on a boundary, return current tick (execute immediately)
	if relative_tick % sync_length == 0 then return current_tick end
	
	-- Calculate next boundary (0-based), then convert back to 1-based
	local next_boundary_0based = math.ceil(relative_tick / sync_length) * sync_length
	return next_boundary_0based + 1
end

-- Check if we should wait for sync or execute immediately
-- All ticks are 1-based: first clock event happens at tick 1
-- @param sync_length (number) Sync length in ticks (0 = disabled)
-- @param current_tick (number) Current transport tick (defaults to App.tick, 1-based)
-- @return (boolean) True if we should wait for sync
function SequenceUtils.should_wait_for_sync(sync_length, current_tick)
	if sync_length == 0 then return false end
	
	current_tick = current_tick or (App.tick or 1)
	
	-- Convert to 0-based for modulo calculation
	local relative_tick = current_tick - 1
	return (relative_tick % sync_length) ~= 0
end

--==============================================================================
-- Tick/Step Conversion Functions (1-based)
--==============================================================================

-- Convert tick to step index (1-based)
-- Step 1 = ticks 1 to step_length, Step 2 = ticks step_length+1 to 2*step_length, etc.
-- @param tick (number) Tick position (1-based)
-- @param step_length (number) Step length in ticks
-- @return (number) Step index (1-based)
function SequenceUtils.tick_to_step_index(tick, step_length)
	return math.floor((tick - 1) / step_length) + 1
end

-- Get current step index from current tick (1-based)
-- @param current_tick (number) Current tick position (1-based)
-- @param step_length (number) Step length in ticks
-- @return (number) Current step index (1-based)
function SequenceUtils.get_current_step_index(current_tick, step_length)
	return SequenceUtils.tick_to_step_index(current_tick, step_length)
end

-- Convert step index to tick range (returns start_tick, end_tick inclusive)
-- @param step_index (number) Step index (1-based)
-- @param step_length (number) Step length in ticks
-- @return (number, number) start_tick, end_tick (both 1-based, inclusive)
function SequenceUtils.step_index_to_tick_range(step_index, step_length)
	local start_tick = (step_index - 1) * step_length + 1
	local end_tick = step_index * step_length
	return start_tick, end_tick
end

-- Convert step index to start tick (1-based)
-- @param step_index (number) Step index (1-based)
-- @param step_length (number) Step length in ticks
-- @return (number) Start tick of the step (1-based)
function SequenceUtils.step_index_to_start_tick(step_index, step_length)
	return (step_index - 1) * step_length + 1
end

--==============================================================================
-- Loop Wrapping Logic
--==============================================================================

-- Wrap tick to be within loop bounds
-- @param tick (number) Tick position
-- @param loop_start (number) Loop start tick (1-based)
-- @param loop_length (number) Loop length in ticks
-- @return (number) Wrapped tick position
function SequenceUtils.wrap_tick_to_loop(tick, loop_start, loop_length)
	local loop_end = loop_start + loop_length - 1
	
	-- If tick is within bounds, return as-is
	if tick >= loop_start and tick <= loop_end then
		return tick
	end
	
	-- Calculate relative position within loop
	local relative_tick = (tick - loop_start) % loop_length
	if relative_tick < 0 then relative_tick = relative_tick + loop_length end
	
	return loop_start + relative_tick
end

-- Check if tick is within loop bounds
-- @param tick (number) Tick position
-- @param loop_start (number) Loop start tick (1-based)
-- @param loop_length (number) Loop length in ticks
-- @return (boolean) True if tick is within loop
function SequenceUtils.is_tick_in_loop(tick, loop_start, loop_length)
	local loop_end = loop_start + loop_length - 1
	return tick >= loop_start and tick <= loop_end
end

--==============================================================================
-- Sync Action Queue
--==============================================================================

-- Create a sync action queue manager
-- Handles queuing and executing actions at sync boundaries
-- @param component (table) Component instance (for accessing sync_length)
-- @param get_sync_length_fn (function) Function to get sync_length: (component) -> number
-- @return (table) Sync action queue instance
function SequenceUtils.create_sync_action_queue(component, get_sync_length_fn)
	local queue = {
		component = component,
		get_sync_length = get_sync_length_fn,
		pending_action = nil,
	}
	
	-- Queue a sync action (replaces any existing pending action)
	-- All ticks are 1-based: first clock event happens at tick 1
	-- @param action_fn (function) Function to execute at sync boundary: (component) -> void
	-- @param action_data (table|nil) Optional data to pass to action_fn
	function queue:queue_action(action_fn, action_data)
		local sync_length = self.get_sync_length(self.component)
		local current_tick = App.tick or 1 -- 1-based: first clock = tick 1
		local next_sync_tick = SequenceUtils.get_next_sync_tick(sync_length, current_tick)
		
		print('SequenceUtils: Queue action')
		print('  Current App.tick: ' .. current_tick)
		print('  Sync length: ' .. sync_length .. ', boundary: ' .. sync_length)
		print('  Next sync tick: ' .. next_sync_tick .. ' (in ' .. (next_sync_tick - current_tick) .. ' ticks)')
		
		self.pending_action = {
			action_fn = action_fn,
			action_data = action_data,
			sync_tick = next_sync_tick,
		}
		
		-- If we're already at the sync boundary, execute immediately
		if not SequenceUtils.should_wait_for_sync(sync_length, current_tick) then
			print('SequenceUtils: Already on sync boundary, executing immediately')
			self:execute_actions()
		end
	end
	
	-- Clear pending action
	function queue:clear_action()
		self.pending_action = nil
	end
	
	-- Execute pending actions if sync boundary has been reached
	-- Should be called on each clock tick
	-- All ticks are 1-based: first clock event happens at tick 1
	-- @return (boolean) True if an action was executed
	function queue:execute_actions()
		if not self.pending_action then return false end
		
		local current_tick = App.tick or 1 -- 1-based: first clock = tick 1
		if current_tick >= self.pending_action.sync_tick then
			print('SequenceUtils: Execute action at App.tick: ' .. current_tick .. ' (target was: ' .. self.pending_action.sync_tick .. ')')
			-- Execute the action
			self.pending_action.action_fn(self.component, self.pending_action.action_data)
			
			-- Clear the action
			self.pending_action = nil
			return true
		end
		
		return false
	end
	
	-- Check if there's a pending action
	function queue:has_pending_action()
		return self.pending_action ~= nil
	end
	
	return queue
end

return SequenceUtils
