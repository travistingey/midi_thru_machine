-- Minimal stub of LuaFileSystem for Norns test harness
local lfs = {}

function lfs.attributes(path, attr)
  return nil -- indicate non-existent attributes
end

function lfs.currentdir()
  return '/'
end

function lfs.chdir(path)
  return true
end

function lfs.dir(path)
  -- Simple directory iterator that returns actual files
  local files = {}
  local i = 0
  
  -- For the spec directory, return the actual test files
  if path:match('/spec/?$') then
    files = {'devicemanager_note_handling_spec.lua', 'example_spec.lua'}
  end
  
  return function()
    i = i + 1
    if i <= #files then
      return files[i]
    else
      return nil
    end
  end
end

function lfs.mkdir(path)
  return true
end

function lfs.rmdir(path)
  return true
end

function lfs.symlinkattributes(path, attr)
  return nil
end

return lfs