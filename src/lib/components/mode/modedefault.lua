local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'components/mode/modecomponent')
local UI = require(path_name .. 'ui')
local ParamTrace = require(path_name .. 'utilities/paramtrace')

local ModeDefault = ModeComponent:new({})

function ModeDefault:enable_event()
  -- Build the baseline menu for the active track
  local menu_style = { inactive_color = 15 }

  local menu = {
    {
      icon = "\u{2192}",
      label = function()
        return App.track[App.current_track].input_device.abbr
      end,
      value = function()
        local in_ch = 'off'
        if App.track[App.current_track].midi_in == 17 then
          in_ch = 'all'
        elseif App.track[App.current_track].midi_in ~= 0 then
          in_ch = App.track[App.current_track].midi_in
        end
        return in_ch
      end,
      style = menu_style,
      enc2 = function(d)
        ParamTrace.set('track_' .. App.current_track .. '_device_in', App.track[App.current_track].device_in + d, 'session_device_in_change')
      end,
      enc3 = function(d)
        ParamTrace.set('track_' .. App.current_track .. '_midi_in', App.track[App.current_track].midi_in + d, 'session_midi_in_change')
      end
    },
    {
      icon = "\u{2190}",
      label = function()
        return App.track[App.current_track].output_device.abbr
      end,
      value = function()
        local out_ch = 'off'
        if App.track[App.current_track].midi_out == 17 then
          out_ch = 'all'
        elseif App.track[App.current_track].midi_out ~= 0 then
          out_ch = App.track[App.current_track].midi_out
        end
        return out_ch
      end,
      style = menu_style,
      enc2 = function(d)
        ParamTrace.set('track_' .. App.current_track .. '_device_out', App.track[App.current_track].device_out + d, 'session_device_out_change')
      end,
      enc3 = function(d)
        ParamTrace.set('track_' .. App.current_track .. '_midi_out', App.track[App.current_track].midi_out + d, 'session_midi_out_change')
      end
    }
  }

  -- Baseline screen draws tempo, chords, header, and menu
  local function baseline_screen()
    UI:draw_tempo()

    if App.track[App.current_track].enabled then
      screen.level(10)
    else
      screen.level(2)
    end

    UI:draw_chord(1, 80, 45)
    UI:draw_chord_small(2)
    UI:draw_status()
    UI:draw_menu(0, 20, self.mode.menu, self.mode.cursor)
  end

  -- Apply as the mode's default UI and menu
  local context = { menu = menu }
  self.mode:use_context(context, baseline_screen, { menu_override = true, set_default = true, timeout = false })
end

return ModeDefault

