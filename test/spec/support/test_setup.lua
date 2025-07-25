-- Shared test setup for MIDI Thru Machine tests
-- This file sets up the global environment needed for all tests

-- Create global App stub
App = {
  device_manager = {
    get = function(id) 
      return {name = "stub_device", send = function() end}
    end,
    midi_device_names = {"stub_device"}
  },
  ppqn = 24, -- Pulses per quarter note
  settings = {}, -- Settings storage
  scale = {
    -- Create a default scale for testing
    [1] = {
      id = 1,
      root = 0,
      mode = 1,
      quantize_note = function(_, data)
        return {
          note = data.note,
          vel = data.vel,
          ch = data.ch,
          new_note = data.note -- Default: no change
        }
      end
    }
  }
}

-- Create global controlspec stub
local function create_controlspec(min, max, warp, step, default, units, quantum)
  return {
    min = min or 0,
    max = max or 1,
    warp = warp or "lin",
    step = step or 0.01,
    default = default or 0,
    units = units or "",
    quantum = quantum or 0.01,
    copy = function() return create_controlspec(min, max, warp, step, default, units, quantum) end
  }
end

controlspec = setmetatable({
  UNIPOLAR = create_controlspec(0, 1, "lin", 0.01, 0.5, "", 0.01),
  BIPOLAR = create_controlspec(-1, 1, "lin", 0.01, 0, "", 0.01),
  FREQ = create_controlspec(0.1, 20000, "exp", 0.1, 440, "Hz", 0.1),
  MIDI = create_controlspec(0, 127, "lin", 1, 64, "", 1)
}, {
  __call = function(_, min, max, warp, step, default, units, quantum)
    return create_controlspec(min, max, warp, step, default, units, quantum)
  end
})

-- Helper function to create a properly initialized track for testing
function create_test_track(id)
  return {
    id = id or 1,
    scale_select = 1, -- Ensure scale component is loaded
    input_device = App.device_manager:get(1),
    output_device = App.device_manager:get(2)
  }
end

-- Map Foobar paths used inside the codebase
package.preload['Foobar/lib/utilities'] = function()
  return require('lib/utilities')
end
package.preload['Foobar/lib/launchcontrol'] = function()
  return require('lib/launchcontrol')
end
package.preload['Foobar/lib/grid'] = function()
  return require('lib/grid')
end
package.preload['Foobar/lib/app'] = function()
  return require('lib/app')
end
package.preload['Foobar/lib/musicutil-extended'] = function()
  return require('lib/musicutil-extended')
end
package.preload['Foobar/lib/components/app/track'] = function()
  return require('lib/components/app/track')
end
package.preload['Foobar/lib/components/app/mode'] = function()
  return require('lib/components/app/mode')
end
package.preload['Foobar/lib/components/track/scale'] = function()
  return require('lib/components/track/scale')
end
package.preload['Foobar/lib/components/track/output'] = function()
  return require('lib/components/track/output')
end
package.preload['Foobar/lib/components/track/trackcomponent'] = function()
  return require('lib/components/track/trackcomponent')
end
package.preload['Foobar/lib/components/track/auto'] = function()
  return require('lib/components/track/auto')
end
package.preload['Foobar/lib/components/track/input'] = function()
  return require('lib/components/track/input')
end
package.preload['Foobar/lib/components/track/seq'] = function()
  return require('lib/components/track/seq')
end
package.preload['Foobar/lib/components/track/mute'] = function()
  return require('lib/components/track/mute')
end
package.preload['Foobar/lib/bitwise'] = function()
  return require('lib/bitwise')
end
package.preload['musicutil'] = function()
  -- Create a stub musicutil module
  return {
    scale_names = {"major", "minor", "dorian", "mixolydian"},
    scale_notes = function(scale_name, root)
      return {root, root+2, root+4, root+5, root+7, root+9, root+11}
    end,
    note_num_to_name = function(note_num)
      local names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
      return names[(note_num % 12) + 1]
    end,
    note_name_to_num = function(note_name)
      local names = {C=0, ["C#"]=1, D=2, ["D#"]=3, E=4, F=5, ["F#"]=6, G=7, ["G#"]=8, A=9, ["A#"]=10, B=11}
      return names[note_name] or 0
    end,
    CHORDS = {}, -- Initialize empty CHORDS table
    SCALES = {}  -- Initialize empty SCALES table
  }
end 