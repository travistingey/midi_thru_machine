-- Note: This is highly customized to interface with the 1010music BitBox Mk II

local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/lib/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local NoteGrid = ModeComponent:new()

local TRIGGER = 1
local LAUNCH = 2
local EMPTY = 3

local SEND_IN = 1
local SEND_OUT = 1 << 1
local SEND_OTHER = 1 << 2

local TYPES = {'trigger','launch','empty'}

NoteGrid.__base = ModeComponent
NoteGrid.name = 'Note Grid'

function NoteGrid:set(o)
  self.__base.set(self, o) -- call the base set method first   

  self.component = 'auto'
  self.select = o.select or 1

  self.grid = Grid:new({
    name = 'NoteGrid ' .. o.track,
    grid_start = {x=1,y=1},
    grid_end = {x=4,y=32},
    display_start = o.display_start or {x=1,y=10},
    display_end = o.display_end or {x=4,y=13},
    offset = o.offset or {x=4,y=0},
    midi = App.midi_grid
  })

  self.alt_context = {
    press_fn_2 = function(d)
      local track = App.track[self.track]

      local on = {
        type = 'note_on',
        note = self.selection + 48,
        vel = 100,
        ch = App.track[self.track].midi_out
      }

      self:handle_send(on)
  
      clock.run(function()
        clock.sleep(.005)
        local off = on
        off.type = 'note_off'
        self:handle_send(off)
        self.state[self.track][self.selection] = false
      end)
  
      self.type[self.track][self.selection] = EMPTY
      self:emit('alt_reset')
      App.screen_dirty = true
      self:set_grid()
      
    end,
    enc2 = function(d)
      self.selection = util.clamp(self.selection + d,36,51)
      self:set_grid()
      App.screen_dirty = true
    end,
    enc3 = function(d)
      self.type[self.track][self.selection] = util.clamp(self.type[self.track][self.selection] + d, 1, #TYPES - 1)
      
      if self.type[self.track][self.selection] == LAUNCH then
        self.state[self.track][self.selection] = false
      end
  
      self:set_grid()
      App.screen_dirty = true
    end
  }

  self.alt_screen = function()
    if self.selection then
      screen.level(0)
      screen.rect(0,35,128,29)
      screen.fill() -- level 15

      screen.level(15)
      screen.rect(0,35,32,32)
      screen.fill() -- level 15
      
      screen.level(0)
      screen.move(16,62)
      screen.font_face(56)
      screen.font_size(28)
      screen.text_center(self.selection)
    
      screen.font_face(1)
      screen.font_size(8)
      screen.move(16, 42)
      screen.text_center('note')
      screen.fill() -- level 0
    
      screen.level(15)
      screen.move(36, 42)
      screen.text('TYPE')
      screen.move(128, 42)
      screen.text_right(TYPES[self.type[self.track][self.selection]])
      screen.fill()
      
      if self.type[self.track][self.selection] ~= EMPTY then
        screen.move(36, 64)
        screen.text('PRESS A TO CLEAR')
        screen.fill()
      end
    end
  end


  self.grid:refresh()
  
  self.type = o.type or {}
  self.state = {}

  for i = 1, 16 do
      self.type[i] = {}
      self.state[i] = {}

    for n = 36, 51 do
      self.type[i][n] = 1
      self.state[i][n] = false
    end

  end

end

function NoteGrid:reset_state()
  for i,v in pairs(self.state[self.track]) do
    if v == true then
      local on = {
        type = 'note_on',
        note = i,
        vel = 100,
        ch = App.track[self.track].midi_out
      }
      
      self:handle_send(on, SEND_OUT)
      
      clock.run(function()
        clock.sleep(.005)
        local off = on
        off.type = 'note_off'
        self:handle_send(off, SEND_OUT)
        
      end)
    end
    self.state[self.track][i] = false
    self:set_grid()
  end
end

function NoteGrid:transport_event (component,data)
  local track = App.track[self.track]
  if data.type == 'stop' then
    self:reset_state()   
  end
end

function NoteGrid:grid_event (component, data)
  local track = App.track[self.track]
  local grid = self.grid
  
  if(data.type == 'pad') then
    local pad = self.grid:grid_to_index(data) - 1
    self.selection = pad

    if self.mode.alt and data.state then
        self.mode:handle_context(self.alt_context, self.alt_screen, {
          timeout = true,
          callback = function()
            self.selection = nil 
            self:set_grid()
          end
        })
    elseif self.type[self.track][pad] == TRIGGER then
      self.state[self.track][pad] = data.state
      if data.state then
        local on = {
          type = 'note_on',
          note = self.grid:grid_to_index(data) - 1,
          vel = 100,
          ch = track.midi_out
        }
        self:handle_send(on, SEND_IN)
      else
        local off = {
          type = 'note_off',
          note = self.grid:grid_to_index(data) - 1,
          vel = 100,
          ch =  track.midi_out
        }
        self:handle_send(off, SEND_IN)
      end
    elseif self.type[self.track][pad] == LAUNCH then
      -- uses trigger on/off but state is toggled
      if data.state then
        self.state[self.track][pad] = not (self.state[self.track][pad])  
      end
 
      if data.state then
      
          local on = {
            type = 'note_on',
            note = self.grid:grid_to_index(data) - 1,
            vel = 100,
            ch =  track.midi_out
          }
          self:handle_send(on, SEND_OUT)
      else
        local off = {
          type = 'note_off',
          note = self.grid:grid_to_index(data) - 1,
          vel = 100,
          ch = track.midi_out
        }
        self:handle_send(off, SEND_OUT)
      end
  
    elseif self.type[self.track][pad] == EMPTY then
      
      if data.state then
        local on = {
          type = 'note_on',
          note = self.grid:grid_to_index(data) - 1 + 32,
          vel = 100,
          ch = track.midi_out
        }
        self:handle_send(on, SEND_OUT)

        if self.state[self.track][pad] == 'recording' then
          
          clock.run(function()
            clock.sleep(.005)
            local off = on
            off.type = 'note_off'
            self:handle_send(off, SEND_OUT)
            self.type[self.track][pad] = LAUNCH
            self.state[self.track][pad] = true
          end)
          
          
        else
          self.state[self.track][pad] = 'recording'
        end

      elseif self.state[self.track][pad] ~= 'recording' then
        local off = {
          type = 'note_off',
          note = self.grid:grid_to_index(data) - 1 + 32,
          vel = 100,
          ch = track.midi_out
        }
        self:handle_send(off, SEND_OUT)
      end

    end
    self:set_grid()
  end

end

function NoteGrid:set_grid (component) 
    local grid = self.grid

      for i,state in pairs(self.state[self.track]) do
        local c = grid:index_to_grid(i+1)
        if i == self.selection and self.mode.alt then
          grid.led[c.x][c.y] = 3
        elseif self.type[self.track][i] == EMPTY  then
          if self.state[self.track][i] == 'recording' then
            grid.led[c.x][c.y] = {1,true}
          else  
            grid.led[c.x][c.y] = 0
          end
        elseif state then
          grid.led[c.x][c.y] = Grid.rainbow_on[i % 16 + 1 ]
        else
          grid.led[c.x][c.y] = Grid.rainbow_off[i % 16 + 1 ]
        end
      end
      grid:refresh('NoteGrid:set_grid')
end

function NoteGrid:handle_send(event, send_type)
  
  if send_type == SEND_IN then
    local track = App.track[self.track]
    track.input_device:process_midi(event)
  elseif send_type == SEND_OUT then
    App.midi_out:send(event)
  end
  
end

function NoteGrid:row_event(data)
  if data.state then
    self.track= data.row
  end
end

return NoteGrid