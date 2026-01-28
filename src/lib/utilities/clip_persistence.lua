--==============================================================================
-- Clip Persistence - Compatibility Shim
--
-- This file is a compatibility shim that forwards all calls to Persistence.
-- All clip persistence functionality has been merged into persistence.lua.
-- This shim exists to maintain backward compatibility with any code that
-- still references ClipPersistence.
--==============================================================================

local Persistence = require('Foobar/lib/utilities/persistence')

-- Forward all clip persistence functions to Persistence
local ClipPersistence = {
	set_pset_number = function(pset_number) Persistence.set_pset_number(pset_number) end,
	get_pset_folder_path = function() return Persistence.get_current_pset_folder_path() end,
	get_clip_dir = Persistence.get_clip_dir,
	get_clip_filepath = Persistence.get_clip_filepath,
	get_clip_filepath_by_filename = Persistence.get_clip_filepath_by_filename,
	get_bank_filepath = Persistence.get_bank_filepath,
	save_clip_file = Persistence.save_clip_file,
	load_clip_file = Persistence.load_clip_file,
	load_clip_bank = Persistence.load_clip_bank,
	save_clip_bank = Persistence.save_clip_bank,
	delete_clip_file = Persistence.delete_clip_file,
}

return ClipPersistence
