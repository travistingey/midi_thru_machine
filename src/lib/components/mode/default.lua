local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'components/mode/modecomponent')
local UI = require(path_name .. 'ui')
local ParamTrace = require(path_name .. 'utilities/paramtrace')

local Default = ModeComponent:new({})

local menu_style = { inactive_color = 15 }

function Default:sub_menu(menu, parent_menu)
  local current_cursor = self.mode.cursor

  local prev = function()
    print("Previous Menu")
    self.mode:use_context({menu=parent_menu}, self:screen(), { timeout = false, cursor = current_cursor })
  end
  
  local context = {
    press_fn_2 = prev,
    menu = menu
  }
  
  self.mode:use_context(context, self:screen(), { timeout = false })
end

function Default:track_menu()
  return {
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
      enc2 = function(d)
        ParamTrace.set('track_' .. App.current_track .. '_device_out', App.track[App.current_track].device_out + d, 'session_device_out_change')
      end,
      enc3 = function(d)
        ParamTrace.set('track_' .. App.current_track .. '_midi_out', App.track[App.current_track].midi_out + d, 'session_midi_out_change')
      end
    },
    {
      icon = "\u{266a}",
      label = "SCALE",
      value = function()
        local scale = App.track[App.current_track].scale_select
        if scale == 0 then
          return 'none'
        else
          return scale
        end
      end,
      enc3 = function(d)
        ParamTrace.set('track_' .. App.current_track .. '_scale_select', App.track[App.current_track].scale_select + d, 'session_scale_select_change')
      end,
      press_fn_3 = function()
        print("Scale Sub Menu")
        self:sub_menu(self:scale_menu(), self:track_menu())
      end
    }    
  }
end

function Default:scale_menu()
  return {
      {
        icon = "\u{2192}",
        label = "SCALE SUB MENU",
        value = function()
          return App.track[App.current_track].scale_select
        end,
      }
    }
end


function Default:screen()
  return function ()
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
end


function Default:enable_event()
  -- Build the baseline menu for the active track
  
  local menu = self:track_menu()

  -- Apply as the mode's default UI and menu
  local context = { menu = menu }

  self.mode:use_context(context, self:screen(), { timeout = false })
end

return Default

