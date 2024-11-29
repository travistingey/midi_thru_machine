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
  self.select = 1
  self.index = nil
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
  self.seq_start = o.seq_start or 1
  self.seq_length = o.seq_length or 8 -- or the desired number of steps
  -- Initialize the sequence with `nil` values
  for i = 1, self.seq_length do
    self.seq[i] = nil
  end
  
  self.context = {
  enc1 = function(d)
    self.select = util.clamp(self.select + d,1,64)

    self.seq[self.index] = self.select
    self:set_grid()
    App.screen_dirty = true
  end,
  enc2 = function(d)
    local param = 'track_'  .. App.current_track .. '_program_change'
  
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
      if self.index and self.seq[self.index] then
        screen.text_center(self.seq[self.index])
      else
        print(self.index)
      end
      screen.font_face(1)
      screen.font_size(8)
      screen.move(16, 42)
      screen.text_center('preset')
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

  if data.type == 'pad_long' and data.pad_down and #data.pad_down == 1 then
    local pad_1 = self.grid:grid_to_index(data)
    local pad_2 = self.grid:grid_to_index(data.pad_down[1])

    local selection_start = math.min(pad_1,pad_2)
    local selection_end = math.max(pad_1,pad_2)

    if self.mode.alt then
      self.seq_start = selection_start
      self.seq_length = selection_end - selection_start + 1
    else
      for i = selection_start, selection_end do
        
          self.seq[i] = self.select
      end
    end
  elseif data.type == 'pad' and data.state and not self.mode.alt then
      local index = self.grid:grid_to_index(data)
      self:start_blink()
      self.mode:handle_context(self.context,self.screen, {
        timeout = true,
        callback = function()
          self:end_blink()
          self.index = nil
          self:set_grid()
        end
      })

      if self.seq[index] then
        self.select = self.seq[index]
        self.seq[index] = nil
      else
        self.seq[index] = self.select
      end
      self.index = index
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
      self.step = self.seq_start
      self.prev_value = nil
      self:run(self.seq[self.step])
    elseif data.type == 'clock' then
      -- Define ticks per step (e.g., 96 ticks per measure)
      local ticks_per_step = 96

      -- Calculate the current step based on the tick count
      local current = math.floor((App.tick) / ticks_per_step) % self.seq_length + self.seq_start

      if current ~= self.step then
        self.step = current
        local value = self.seq[self.step]

        -- Only run if the value has changed
        if value and value ~= self.prev_value then
          self:run(value)
          self.prev_value = value
        end
      end
    end

    self:set_grid()
  end
end



function PresetSeq:set_grid()
  if self.mode == nil then return end
  local grid = self.grid

  local BLINK = 1
  local VALUE = (1 << 1)
  local INSIDE_LOOP = (1 << 2)
  local LOOP_END = (1 << 3)
  local STEP = (1 << 4)
  local SELECTED = (1 << 5)
  
  grid:for_each(function(s, x, y, i)

    local pad = 0
    if self.blink_state then
      pad = pad | BLINK

    end
    if self.seq[i] then pad = pad | VALUE end
    if i >= self.seq_start and i <= self.seq_start + self.seq_length - 1 and self.mode.alt then  pad = pad | INSIDE_LOOP end
    if self.mode.alt and (i == self.seq_start or  i == self.seq_start + self.seq_length - 1) then  pad = pad | LOOP_END end
    if self.index == i and not self.mode.alt then  pad = pad | SELECTED  end
    if self.step == i and App.playing then  pad = pad | STEP  end

    if pad  & (BLINK | SELECTED | INSIDE_LOOP | VALUE) >= (BLINK | SELECTED | INSIDE_LOOP | VALUE) then
      color = self.grid.rainbow_on[(self.seq[i] - 1) % 16 + 1]
    elseif pad  & (SELECTED | VALUE | INSIDE_LOOP) >= (SELECTED | VALUE | INSIDE_LOOP) then
      color = self.grid.rainbow_off[(self.seq[i] - 1) % 16 + 1]
    elseif pad  & (BLINK | SELECTED | VALUE ) >= (BLINK | SELECTED | VALUE) then
      color = 1
    elseif pad  & (BLINK | SELECTED) >= (BLINK | SELECTED) then
      color = {5,5,5}
    elseif pad  & (SELECTED) >= (SELECTED) then
      color = 0
    elseif pad  & (STEP | VALUE) >= (STEP | VALUE) then
      color = self.grid.rainbow_on[(self.seq[i] - 1) % 16 + 1]
    elseif pad  & (STEP) >= STEP then
      color = 1
    elseif pad  & (BLINK | LOOP_END | VALUE) >= (BLINK | LOOP_END | VALUE) then
      color = self.grid.rainbow_on[(self.seq[i] - 1) % 16 + 1]
    elseif pad  & (BLINK | LOOP_END ) >= (BLINK | LOOP_END ) then
      color = {5,5,5}
    elseif pad  & (INSIDE_LOOP | VALUE) >= (INSIDE_LOOP | VALUE) then
      color = self.grid.rainbow_off[(self.seq[i] - 1) % 16 + 1]
    elseif pad  & (VALUE) >= (VALUE) then
      color = self.grid.rainbow_off[(self.seq[i] - 1) % 16 + 1]
    else
      color = 0
    end

    s.led[x][y] = color
  end)
  grid:refresh('PresetSeq:set_grid')
end

function PresetSeq:on_alt()
  self.index = nil
  self.mode:cancel_context()
  self:start_blink()
  self:set_grid()
end

function PresetSeq:on_alt_reset()
  self:end_blink()
  self:set_grid()
end

return PresetSeq