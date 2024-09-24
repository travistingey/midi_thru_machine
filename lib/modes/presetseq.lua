-- Note: This is highly customized to interface with the 1010music BitBox Mk II

local path_name = 'Foobar/lib/'
local ModeComponent = require(path_name .. 'modecomponent')
local Grid = require(path_name .. 'grid')
local PresetSeq = ModeComponent:new()

local DRUM_CHANNEL = 10
local SEQ_1_CHANNEL = 1
local SEQ_2_CHANNEL = 2

PresetSeq.__base = ModeComponent
PresetSeq.name = 'Preset Sequencer'

function PresetSeq:set(o)
  self.__base.set(self, o) -- call the base set method first   
  self.active = true
  self.select = o.select or 1
  self.index = o.index or 1
  self.step = 1
  self.component = 'input'

  self.grid = Grid:new({
    name = 'PresetSeq ' .. o.track,
    grid_start = {x=1,y=4},
    grid_end = {x=8,y=1},
    display_start = o.display_start or {x=1,y=1},
    display_end = o.display_end or {x=8,y=4},
    offset = o.offset or {x=0,y=4},
    midi = App.midi_grid
  })

  self.grid:refresh()

  self.seq = {}

  self.context = {
  enc1 = function(d)
    self.select = util.clamp(self.select + d,1,64)

    self.seq[self.index] = self.select
    self:set_grid()
  end,
  enc2 = function(d)
    local param = 'track_'  .. App.current_track .. '_program_change'
    print(App.current_track)
    local value = params:get(param)
    
    params:set(param, value + d)
  end

}

  self.screen =  function()
    
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
      screen.text_center(self.index)
    
      screen.font_face(1)
      screen.font_size(8)
      screen.move(16, 42)
      screen.text_center('pattern')
      screen.fill() -- level 0
    
      screen.level(15)
      screen.move(36, 42)
      screen.text('TYPE')
      screen.move(128, 42)
      screen.text_right('poops')
      screen.fill()

  end

end


function PresetSeq:grid_event (component, data)
  -- TODO: Alt pad will select step
  -- Up/Down navigate grid
  -- Left/Right select preset
  
  local grid = self.grid
  if data.state and data.type == 'pad' then
    local index = self.grid:grid_to_index(data)

    if self.seq[index] and self.index == index then
      self.seq[index] = nil
    elseif self.seq[index] and self.index ~= index then
      self.select = self.seq[index]
      self.mode:handle_context(self.context,self.screen,2)
    else
      self.seq[index] = self.select
      self.mode:handle_context(self.context,self.screen,2)
    end
    
    self.index = index
    if not App.playing then
      self.step = index
    end
  end
  self:set_grid()
end

function PresetSeq:run(value)
  if value then
    App.midi_in:program_change (value - 1, DRUM_CHANNEL)
    App.midi_in:program_change (value - 1, SEQ_1_CHANNEL)
    App.midi_in:program_change (value - 1, SEQ_2_CHANNEL)
  end
end

function PresetSeq:transport_event(component, data)
  if self.active then
    if data.type == 'start' then
      self:run(self.seq[1])
      self.step = 1
    elseif data.type == 'clock' then
      local current = math.ceil((App.tick + 1) / 96)

      if current ~= self.step then
        self.step = current

        local value = self.seq[current]
        if #self.seq > 0 and self.seq[(current - 2) % #self.seq + 1 ] ~= value then
          self:run(value)
        end
      end
    end

    self:set_grid()
  end
end

function PresetSeq:set_grid (component) 
  local current = self.step

    local grid = self.grid
      grid:for_each(function(s,x,y,i)
        if self.seq[i] then
          if i == current then
            s.led[x][y] = self.grid.rainbow_on[(self.seq[i] - 1) % 16 + 1]
          else
            s.led[x][y] = self.grid.rainbow_off[(self.seq[i] - 1) % 16 + 1]
          end
        elseif i == current then
          s.led[x][y] = 1
        else
          s.led[x][y] = 0
        end
      end)
      grid:refresh('PresetSeq:set_grid')
end

return PresetSeq