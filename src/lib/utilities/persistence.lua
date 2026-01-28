--==============================================================================
-- Persistence.lua - Table Data Persistence for PSET Save/Load
--
-- Handles saving and loading of tabular data (presets, automation sequences)
-- alongside norns parameter saves using tab.save() and tab.load().
--==============================================================================

local Persistence = {}

-- Current data format version (for future migrations)
Persistence.VERSION = 1

-- Current PSET number (for clip persistence path resolution, defaults to 1)
Persistence.current_pset_number = 1

--==============================================================================
-- File Path Helpers
--==============================================================================

--- Get PSET folder name from PSET number
-- @param pset_number number|string The preset slot number
-- @return string The PSET folder name (e.g., "Foobar-01")
function Persistence.get_pset_folder_name(pset_number)
	-- Normalize to zero-padded string format to match norns PSET naming (e.g., "01", "02")
	local num = tonumber(pset_number) or 1
	local formatted = string.format('%02d', num)
	-- Get script name from norns.state.name (e.g., "Foobar")
	local script_name = norns.state.name or 'Foobar'
	return script_name .. '-' .. formatted
end

--- Get PSET folder path
-- @param pset_number number|string The preset slot number
-- @return string The full path to the PSET folder
function Persistence.get_pset_folder_path(pset_number)
	local folder_name = Persistence.get_pset_folder_name(pset_number)
	return norns.state.data .. folder_name .. '/'
end

--- Generate data file path for a given PSET number
-- @param pset_number number|string The preset slot number (may be zero-padded string like "01")
-- @return string The full file path for the data file
function Persistence.get_data_path(pset_number)
	local pset_folder = Persistence.get_pset_folder_path(pset_number)
	return pset_folder .. 'preset_data.txt'
end

--- Set the current PSET number for path resolution (used by clip persistence)
-- @param pset_number number The preset slot number
function Persistence.set_pset_number(pset_number) Persistence.current_pset_number = pset_number end

--- Get the current PSET folder path (uses current_pset_number or defaults to 1)
-- @return string The PSET folder path
function Persistence.get_current_pset_folder_path()
	local pset_number = Persistence.current_pset_number or 1
	return Persistence.get_pset_folder_path(pset_number)
end

--==============================================================================
-- Clip Persistence Functions
--==============================================================================

--- Get the clips directory for a track (within current PSET folder)
-- @param track_id number The track ID
-- @return string The directory path
function Persistence.get_clip_dir(track_id) return Persistence.get_current_pset_folder_path() .. 'clips/' end

--- Get the filepath for a clip file
-- @param track_id number The track ID
-- @param bank_slot number The bank slot (1-16)
-- @return string The full file path
function Persistence.get_clip_filepath(track_id, bank_slot)
	local filename = string.format('track_%d_clip_%03d.lua', track_id, bank_slot)
	return Persistence.get_clip_dir(track_id) .. filename
end

--- Get the filepath for a clip file by filename
-- @param track_id number The track ID
-- @param filename string The filename
-- @return string The full file path
function Persistence.get_clip_filepath_by_filename(track_id, filename) return Persistence.get_clip_dir(track_id) .. filename end

--- Get the filepath for a bank metadata file (within current PSET folder)
-- @param track_id number The track ID
-- @return string The full file path
function Persistence.get_bank_filepath(track_id) return Persistence.get_current_pset_folder_path() .. string.format('track_%d_bank.txt', track_id) end

--- Save a clip to file
-- @param track_id number The track ID
-- @param bank_slot number The bank slot (1-16)
-- @param clip_data table The clip data {name, length, buffer}
-- @return boolean True if save succeeded
function Persistence.save_clip_file(track_id, bank_slot, clip_data)
	local filepath = Persistence.get_clip_filepath(track_id, bank_slot)

	-- Ensure directory exists
	local clip_dir = Persistence.get_clip_dir(track_id)
	if not util.file_exists(clip_dir) then os.execute('mkdir -p ' .. clip_dir) end

	local success, err = pcall(function() tab.save(clip_data, filepath) end)

	if success then
		print('Persistence: Saved clip to ' .. filepath)
		return true
	else
		print('Persistence: Error saving clip to ' .. filepath .. ' - ' .. tostring(err))
		return false
	end
end

--- Load a clip file by filename
-- @param track_id number The track ID
-- @param filename string The filename
-- @return table|nil The clip data or nil if load failed
function Persistence.load_clip_file(track_id, filename)
	local filepath = Persistence.get_clip_filepath_by_filename(track_id, filename)

	if not util.file_exists(filepath) then
		print('Persistence: No clip file found at ' .. filepath)
		return nil
	end

	local success, result = pcall(function() return tab.load(filepath) end)

	if success and result then
		print('Persistence: Loaded clip from ' .. filepath)
		return result
	else
		print('Persistence: Error loading clip from ' .. filepath .. ' - ' .. tostring(result))
		return nil
	end
end

--- Load bank metadata
-- @param track_id number The track ID
-- @return table|nil The bank data or nil if load failed
function Persistence.load_clip_bank(track_id)
	local filepath = Persistence.get_bank_filepath(track_id)

	if not util.file_exists(filepath) then
		print('Persistence: No bank file found at ' .. filepath)
		return nil
	end

	local success, result = pcall(function() return tab.load(filepath) end)

	if success and result then
		print('Persistence: Loaded bank from ' .. filepath)
		return result
	else
		print('Persistence: Error loading bank from ' .. filepath .. ' - ' .. tostring(result))
		return nil
	end
end

--- Save bank metadata
-- @param track_id number The track ID
-- @param bank_data table The bank data {slots = {[1-16] = {filename, playback_settings}}}
-- @return boolean True if save succeeded
function Persistence.save_clip_bank(track_id, bank_data)
	-- Ensure PSET folder exists
	local pset_folder = Persistence.get_current_pset_folder_path()
	if not util.file_exists(pset_folder) then os.execute('mkdir -p ' .. pset_folder) end

	local filepath = Persistence.get_bank_filepath(track_id)

	local success, err = pcall(function() tab.save(bank_data, filepath) end)

	if success then
		print('Persistence: Saved bank to ' .. filepath)
		return true
	else
		print('Persistence: Error saving bank to ' .. filepath .. ' - ' .. tostring(err))
		return false
	end
end

--- Delete a clip file
-- @param track_id number The track ID
-- @param filename string The filename of the clip to delete
-- @return boolean True if delete succeeded
function Persistence.delete_clip_file(track_id, filename)
	local filepath = Persistence.get_clip_filepath_by_filename(track_id, filename)

	if not util.file_exists(filepath) then
		print('Persistence: No clip file found at ' .. filepath)
		return false
	end

	local success, err = pcall(function() os.remove(filepath) end)

	if success then
		print('Persistence: Deleted clip file ' .. filepath)
		return true
	else
		print('Persistence: Error deleting clip file ' .. filepath .. ' - ' .. tostring(err))
		return false
	end
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

	-- Collect clip bank metadata from each track
	state.clips = {}
	for i = 1, 8 do
		if App.track[i] and App.track[i].clip then
			local clip = App.track[i].clip
			state.clips[i] = {
				current_slot = clip.current_slot,
				bank = {},
			}

			-- Collect bank slot metadata (filenames and settings, not full buffer data)
			for slot = 1, 16 do
				if clip.clip_bank[slot] then
					state.clips[i].bank[slot] = {
						filename = clip.clip_bank[slot].filename,
						name = clip.clip_bank[slot].name,
						loop_start = clip.clip_bank[slot].loop_start, -- Save loop_start
						playback_settings = clip.clip_bank[slot].playback_settings or {},
					}
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
		print('Persistence: No state to restore')
		return false
	end

	-- Version check for future migrations
	local version = state.version or 1
	if version > Persistence.VERSION then print('Persistence: Warning - data version ' .. version .. ' is newer than supported version ' .. Persistence.VERSION) end

	-- Restore preset bank
	if state.preset then
		for i = 1, 16 do
			if state.preset[i] then
				if not App.preset[i] then App.preset[i] = {} end
				for k, v in pairs(state.preset[i]) do
					App.preset[i][k] = v
				end
			end
		end
		print('Persistence: Restored ' .. #state.preset .. ' presets')
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
		print('Persistence: Restored automation for ' .. restored_count .. ' tracks')
	end

	-- Restore clip banks
	if state.clips then
		local restored_count = 0
		for i = 1, 8 do
			if state.clips[i] and App.track[i] and App.track[i].clip then
				local clip = App.track[i].clip

				-- Restore bank slot metadata
				if state.clips[i].bank then
					for slot = 1, 16 do
						if state.clips[i].bank[slot] then
							local slot_data = state.clips[i].bank[slot]
							-- Load the actual clip file
							local clip_data = Persistence.load_clip_file(i, slot_data.filename)
							if clip_data then
								clip.clip_bank[slot] = {
									filename = slot_data.filename,
									name = slot_data.name or clip_data.name,
									length = clip_data.length or 0,
									loop_start = slot_data.loop_start or clip_data.loop_start or 0, -- Restore loop_start
									buffer = clip_data.buffer,
									playback_settings = slot_data.playback_settings or {},
								}
							end
						end
					end
				end

				-- Restore current clip slot (if it exists)
				if state.clips[i].current_slot and clip.clip_bank[state.clips[i].current_slot] then clip.current_slot = state.clips[i].current_slot end

				restored_count = restored_count + 1
			end
		end
		print('Persistence: Restored clip banks for ' .. restored_count .. ' tracks')
	end

	return true
end

--==============================================================================
-- Save/Load Operations
--==============================================================================

--- Save table data to file for a given PSET number
-- @param pset_number number The preset slot number
function Persistence.save(pset_number)
	-- Ensure PSET folder exists
	local pset_folder = Persistence.get_pset_folder_path(pset_number)
	if not util.file_exists(pset_folder) then os.execute('mkdir -p ' .. pset_folder) end

	-- Update current PSET number for clip persistence
	Persistence.set_pset_number(pset_number)

	local filepath = Persistence.get_data_path(pset_number)
	local state = Persistence.collect_state()

	local success, err = pcall(function() tab.save(state, filepath) end)

	if success then
		print('Persistence: Saved table data to ' .. filepath)
	else
		print('Persistence: Error saving to ' .. filepath .. ' - ' .. tostring(err))
	end
end

--- Load table data from file for a given PSET number
-- @param pset_number number The preset slot number
-- @return boolean True if load succeeded
function Persistence.load(pset_number)
	-- Update current PSET number for clip persistence
	Persistence.set_pset_number(pset_number)

	local filepath = Persistence.get_data_path(pset_number)

	if not util.file_exists(filepath) then
		print('Persistence: No data file found at ' .. filepath)
		return false
	end

	local success, result = pcall(function() return tab.load(filepath) end)

	if success and result then
		local restored = Persistence.restore_state(result)
		if restored then print('Persistence: Loaded table data from ' .. filepath) end
		return restored
	else
		print('Persistence: Error loading from ' .. filepath .. ' - ' .. tostring(result))
		return false
	end
end

--- Delete table data file for a given PSET number
-- @param pset_number number The preset slot number
function Persistence.delete(pset_number)
	local filepath = Persistence.get_data_path(pset_number)
	local pset_folder = Persistence.get_pset_folder_path(pset_number)

	-- Delete the data file if it exists
	if util.file_exists(filepath) then
		local success, err = pcall(function() os.remove(filepath) end)

		if success then
			print('Persistence: Deleted table data at ' .. filepath)
		else
			print('Persistence: Error deleting ' .. filepath .. ' - ' .. tostring(err))
		end
	end

	-- Note: We don't delete the entire PSET folder here because:
	-- 1. The PSET file itself is managed by norns
	-- 2. Users might want to keep clips even if they delete the PSET
	-- 3. The folder can be manually cleaned up if needed
end

return Persistence
