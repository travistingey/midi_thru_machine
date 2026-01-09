--==============================================================================
-- Persistence.lua - Table Data Persistence for PSET Save/Load
--
-- Handles saving and loading of tabular data (presets, automation sequences)
-- alongside norns parameter saves using tab.save() and tab.load().
--==============================================================================

local Persistence = {}

-- Current data format version (for future migrations)
Persistence.VERSION = 1

--==============================================================================
-- File Path Helpers
--==============================================================================

--- Generate data file path for a given PSET number
-- @param pset_number number|string The preset slot number (may be zero-padded string like "01")
-- @return string The full file path for the data file
function Persistence.get_data_path(pset_number)
	-- Normalize to zero-padded string format to match norns PSET naming (e.g., "01", "02")
	local num = tonumber(pset_number) or 1
	local formatted = string.format("%02d", num)
	return norns.state.data .. "preset_data_" .. formatted .. ".txt"
end

--==============================================================================
-- State Collection
--==============================================================================

--- Collect all persistable state into a single table
-- @return table The collected state ready for serialization
function Persistence.collect_state()
	local state = {
		version = Persistence.VERSION,
		preset = {},
		automation = {},
	}

	-- Deep copy preset bank to avoid reference issues
	if App.preset then
		for i = 1, 16 do
			if App.preset[i] then
				state.preset[i] = {}
				for k, v in pairs(App.preset[i]) do
					state.preset[i][k] = v
				end
			end
		end
	end

	-- Collect automation data from each track
	for i = 1, 8 do
		if App.track[i] and App.track[i].auto then
			local auto = App.track[i].auto
			state.automation[i] = {
				seq = {},
				seq_start = auto.seq_start,
				seq_length = auto.seq_length,
			}

			-- Deep copy seq table (nested structure: tick -> lane -> value)
			-- Buffer lane is special: it's an array of event tables
			if auto.seq then
				for tick, lanes in pairs(auto.seq) do
					state.automation[i].seq[tick] = {}
					for lane, data in pairs(lanes) do
						if lane == 'buffer' and type(data) == 'table' then
							-- Buffer is an array of event tables
							state.automation[i].seq[tick][lane] = {}
							for idx, event in ipairs(data) do
								state.automation[i].seq[tick][lane][idx] = {}
								for k, v in pairs(event) do
									state.automation[i].seq[tick][lane][idx][k] = v
								end
							end
						elseif type(data) == 'table' then
							state.automation[i].seq[tick][lane] = {}
							for k, v in pairs(data) do
								state.automation[i].seq[tick][lane][k] = v
							end
						else
							state.automation[i].seq[tick][lane] = data
						end
					end
				end
			end
		end
	end

	return state
end

--==============================================================================
-- State Restoration
--==============================================================================

--- Restore state from loaded data
-- @param state table The loaded state data
-- @return boolean True if restoration succeeded
function Persistence.restore_state(state)
	if not state then
		print("Persistence: No state to restore")
		return false
	end

	-- Version check for future migrations
	local version = state.version or 1
	if version > Persistence.VERSION then
		print("Persistence: Warning - data version " .. version .. " is newer than supported version " .. Persistence.VERSION)
	end

	-- Restore preset bank
	if state.preset then
		for i = 1, 16 do
			if state.preset[i] then
				if not App.preset[i] then
					App.preset[i] = {}
				end
				for k, v in pairs(state.preset[i]) do
					App.preset[i][k] = v
				end
			end
		end
		print("Persistence: Restored " .. #state.preset .. " presets")
	end

	-- Restore automation sequences
	if state.automation then
		local restored_count = 0
		for i = 1, 8 do
			if state.automation[i] and App.track[i] and App.track[i].auto then
				local auto = App.track[i].auto

				-- Restore seq table
				-- Buffer lane is special: it's an array of event tables
				if state.automation[i].seq then
					auto.seq = {}
					for tick, lanes in pairs(state.automation[i].seq) do
						auto.seq[tick] = {}
						for lane, data in pairs(lanes) do
							if lane == 'buffer' and type(data) == 'table' then
								-- Buffer is an array of event tables
								auto.seq[tick][lane] = {}
								for idx, event in ipairs(data) do
									auto.seq[tick][lane][idx] = {}
									for k, v in pairs(event) do
										auto.seq[tick][lane][idx][k] = v
									end
								end
							elseif type(data) == 'table' then
								auto.seq[tick][lane] = {}
								for k, v in pairs(data) do
									auto.seq[tick][lane][k] = v
								end
							else
								auto.seq[tick][lane] = data
							end
						end
					end
				else
					auto.seq = {}
				end

				-- Restore loop settings
				auto.seq_start = state.automation[i].seq_start or 0
				auto.seq_length = state.automation[i].seq_length or (App.ppqn * 16)

				restored_count = restored_count + 1
			end
		end
		print("Persistence: Restored automation for " .. restored_count .. " tracks")
	end

	return true
end

--==============================================================================
-- Save/Load Operations
--==============================================================================

--- Save table data to file for a given PSET number
-- @param pset_number number The preset slot number
function Persistence.save(pset_number)
	local filepath = Persistence.get_data_path(pset_number)
	local state = Persistence.collect_state()

	local success, err = pcall(function()
		tab.save(state, filepath)
	end)

	if success then
		print("Persistence: Saved table data to " .. filepath)
	else
		print("Persistence: Error saving to " .. filepath .. " - " .. tostring(err))
	end
end

--- Load table data from file for a given PSET number
-- @param pset_number number The preset slot number
-- @return boolean True if load succeeded
function Persistence.load(pset_number)
	local filepath = Persistence.get_data_path(pset_number)

	if not util.file_exists(filepath) then
		print("Persistence: No data file found at " .. filepath)
		return false
	end

	local success, result = pcall(function()
		return tab.load(filepath)
	end)

	if success and result then
		local restored = Persistence.restore_state(result)
		if restored then
			print("Persistence: Loaded table data from " .. filepath)
		end
		return restored
	else
		print("Persistence: Error loading from " .. filepath .. " - " .. tostring(result))
		return false
	end
end

--- Delete table data file for a given PSET number
-- @param pset_number number The preset slot number
function Persistence.delete(pset_number)
	local filepath = Persistence.get_data_path(pset_number)

	if util.file_exists(filepath) then
		local success, err = pcall(function()
			os.remove(filepath)
		end)

		if success then
			print("Persistence: Deleted table data at " .. filepath)
		else
			print("Persistence: Error deleting " .. filepath .. " - " .. tostring(err))
		end
	end
end

return Persistence
