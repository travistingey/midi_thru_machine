local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/lib/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local PresetSeq = ModeComponent:new()

PresetSeq.__base = ModeComponent
PresetSeq.name = 'presetseq'

local max_step_length = App.ppqn * 16 -- 4 bars
local min_step_length = App.ppqn / 8 -- 1/32th note
local max_ticks = max_step_length * 64

function PresetSeq:set(o)
    self.__base.set(self, o)
    self.active = true
    self.select = { type='track', value = 1}
    self.index = nil
    self.component = 'auto'

    self.lanes = { 'track', 'scale', 'cc' }  -- List of lanes
    self.selected_lane_index = 1                -- Index of the selected lane
    self.selected_lane = self.lanes[self.selected_lane_index]
    self.step_length = o.step_length or 24

    self.display_offset = o.display_offset or 0
    
    self.grid = Grid:new({
        name = 'PresetSeq ' .. o.track,
        grid_start = o.grid_start or {x=1,y=4},
        grid_end = o.grid_end or {x=8,y=1},
        display_start = o.display_start or {x=1,y=1},
        display_end = o.display_end or {x=8,y=4},
        offset = o.offset or {x=0,y=4},
        midi = App.midi_grid
    })

    self.row_length = self.grid.bounds.width
    self.row_ticks = self.row_length * self.step_length

    self.display_length = self.grid.bounds.height * self.row_length
    self.display_ticks = self.display_length * self.step_length  
    

    self.step_offset = self.display_offset * self.row_length

    self.grid:refresh()

    self.context = {
        enc1 = function(d)
            local auto = self:get_component()
            self.selected_lane_index = (self.selected_lane_index + d - 1) % #self.lanes + 1
            self.selected_lane = self.lanes[self.selected_lane_index]
            self:set_grid(auto)
            App.screen_dirty = true
        end,
    }

    self.screen =  function()
        screen.level(0)
        screen.rect(0,35,128,29)
        screen.fill()
        screen.level(15)
        screen.rect(0,35,32,32)
        screen.fill()
        screen.level(0)
        
        screen.move(36, 42)
        screen.text(self.selected_lane)

        screen.move(16,62)
        screen.font_face(56)
        screen.font_size(28)
        
        local auto = self:get_component()
        local step_value = ''
        if self.index and auto.seq[self.index] and auto.seq[self.index][self.selected_lane] then
            screen.text_center(auto.seq[self.index][self.selected_lane].value)
        end
        screen.font_face(1)
        screen.font_size(8)
        screen.move(16, 42)
        screen.text_center(self.selected_lane)
        screen.fill()
        screen.level(15)
        screen.move(36, 42)
        screen.text('TYPE')
        screen.move(128, 42)
        screen.text_right('poops')
        screen.fill()
    end
end

function PresetSeq:enable_event()
    local auto = self:get_component()

    local loop_start = auto.seq_start
    local loop_end = auto.seq_start + auto.seq_length - 1

    self:on('preset_select', function(selection)
        self:set_select(selection.value)
        if App.recording then
            local auto = self:get_component()
            local step = math.floor((auto.step + (self.step_length / 2) ) / self.step_length) + 1
            self:set_step(step, selection)
        end
    end)
end

-- If no value is specified, it references the track's current_preset
function PresetSeq:set_select(value)
    local track = self:get_component().track

    if value then
        self.select = { type = self.selected_lane, value = value }
    elseif self.selected_lane == 'track' then
        self.select = { type='track', value = track.current_preset }
    elseif self.selected_lane == 'cc' then
        self.select = { type='cc', value = track.current_preset }
    end
    
end

function PresetSeq:recalculate_display(previous_offset)
    self.row_ticks = self.step_length * self.row_length
    local new_offset = self.step_length * self.display_length
    self.display_ticks = self.step_length * self.display_length + new_offset
    -- recalculate display offset
    if previous_offset then
        self.display_offset = math.floor(previous_offset / self.step_length)
        self.step_offset = self.display_offset * self.row_length
    end
    
end

function PresetSeq:increase_step_length()
    -- max step length is 384 ticks = 16 beats * 24ppqn = 16 bars
    if self.step_length < max_step_length then
        local current_display_offset = self.display_offset * self.step_length
        self.step_length = self.step_length * 2
        self:recalculate_display(current_display_offset)
        
        self:set_grid(self:get_component())
    end
    
end

function PresetSeq:decrease_step_length()
    local current_display_offset = self.display_offset * self.step_length
    -- min step length is 3 ticks = 1/32th note
    -- Note length calculated as PPQN / 2^3 (subdivisions)
    if self.step_length > min_step_length then
        self.step_length = self.step_length / 2
        self:recalculate_display(current_display_offset)
        self:set_grid(self:get_component())
    elseif self.step_length <= min_step_length then
        self.step_length = 1 -- show ticks
        self:recalculate_display(current_display_offset)
        self:set_grid(self:get_component())
    end
    self.row_ticks = self.step_length * self.row_length
    self.display_ticks = self.step_length * self.display_length
end

function PresetSeq:increase_display_offset()
    local new_offset = self.step_offset * self.step_length + self.display_ticks
    print('new_offset', new_offset)
    print('max_ticks', max_ticks)
    if new_offset < max_ticks then
        self.display_offset = self.display_offset + 1
        self.step_offset = self.display_offset * self.row_length
        self:set_grid(self:get_component())
    end
end

function PresetSeq:decrease_display_offset()
    if self.display_offset > 0 then
        self.display_offset = self.display_offset - 1
        self.step_offset = self.display_offset * self.row_length
        self:set_grid(self:get_component())
    end
end

function PresetSeq:grid_event(component, data)
    local grid = self.grid
    local auto = component

    self:set_select()
    

    if data.type == 'pad_long' and data.pad_down and #data.pad_down == 1 then
        local pad_1 = self.grid:grid_to_index(data) + self.step_offset
        local pad_2 = self.grid:grid_to_index(data.pad_down[1]) + self.step_offset
        print(pad_1, pad_2)
        local selection_start = math.min(pad_1,pad_2)
        local selection_end = math.max(pad_1,pad_2)

        if self.mode.alt then
            local loop_start = (selection_start - 1) * self.step_length
            local loop_end = selection_end * self.step_length - 1
            auto:set_loop(loop_start, loop_end)
        else
            self.last_step = {selection_start, selection_end}
            for i = selection_start, selection_end do
                local start_tick = (i - 1) * self.step_length
                local end_tick = i * self.step_length - 1
                for tick = start_tick, end_tick do
                    auto:set_action(tick, self.select)
                end
            end
        end
    elseif data.type == 'pad' and data.state and not self.mode.alt then
        local index = self.grid:grid_to_index(data) + self.step_offset
        local current = self:get_step(index, self.select)

        if current ~= nil and current.value ~= self.select.value then
            self:set_step(index, self.select)
        else
            self:toggle_step(index, self.select)
        end
       
        self.index = (index - 1) * self.step_length
    end
    self:set_grid(auto)
end

-- Clear all actions within a step and set first tick to the action
function PresetSeq:clear_step(step, action)
    local auto = self:get_component()
    local start_tick = (step - 1) * self.step_length
    local end_tick = step * self.step_length - 1
    local has_event = false

    for tick = start_tick, end_tick do
        auto:set_action(tick, action.type, nil)
    end
 
end

-- If event exists within a step, it removes events. Otherwise we add first step
function PresetSeq:toggle_step(step, action)
    local auto = self:get_component()
    local start_tick = (step - 1) * self.step_length
    local end_tick = step * self.step_length - 1
    local has_event = false
    for tick = start_tick, end_tick do
        if auto.seq[tick] and auto.seq[tick][action.type] then
            has_event = true
            break
        end
    end

    if has_event then
       self:clear_step(step, action)
    else
        auto:set_action(start_tick, action)
    end

    self.index = (step - 1) * self.step_length
end

function PresetSeq:get_step(step, action)
    local auto = self:get_component()
    local tick = (step - 1) * self.step_length
    if type(action) == 'string' then
        return auto:get_action(tick, action)
    elseif type(action) == 'table' then
        return auto:get_action(tick, action.type)
    end
end

-- Clear all actions within a step and set first tick to the action
function PresetSeq:set_step(step, action)
    local auto = self:get_component()
    local tick = (step - 1) * self.step_length
    local has_event = false

    self:clear_step(step, action)
 
    auto:set_action(tick, action)

    self.index = (step - 1) * self.step_length
end

function PresetSeq:set_grid(component)
    if self.mode == nil then return end
    local grid = self.grid
    local auto = self:get_component()  -- 'component' is the Auto component
    local BLINK = 1
    local VALUE = (1 << 1)
    local LOOP_END = (1 << 2)
    local STEP = (1 << 3)
  
    grid:for_each(function(s, x, y, i)
        local pad = 0

        if self.blink_state then
            pad = pad | BLINK
        end

        local lane = self.selected_lane
        
        -- Determine the global step index for this LED pad based on the display offset
        local global_step = i + self.step_offset
        local current_step = math.floor(auto.step / self.step_length) + 1
        local seq_value

        -- Iterate over the tick range corresponding to the global step
        for j = (global_step - 1) * self.step_length, global_step * self.step_length - 1 do
            if auto.seq[j] and auto.seq[j][lane] then
                seq_value = auto.seq[j][lane].value
                break
            end
        end
        
        if seq_value then
            pad = pad | VALUE
        end

        local loop_start = auto.seq_start
        local loop_end = auto.seq_start + auto.seq_length - 1
        local loop_start_index = math.floor(loop_start / self.step_length) + 1
        local loop_end_index = math.floor(loop_end / self.step_length) + 1

        if global_step == loop_start_index or global_step == loop_end_index then
            pad = pad | LOOP_END
        end

        if current_step == global_step and App.playing then
            pad = pad | STEP
        end

        local color = 123

        if pad & (BLINK | VALUE | STEP) == 0 or pad == BLINK then
            -- empty
            color = 0
        elseif pad & STEP > 0 and pad & (BLINK | VALUE) == 0 or pad == (BLINK | STEP) then
            -- LOW White
            color = {5,5,5}
        elseif pad & VALUE > 0 and pad & (BLINK | STEP) == 0 or pad == (BLINK | VALUE) then
            -- LOW Color
            color = grid.rainbow_off[(seq_value - 1) % 16 + 1]
        elseif pad & (BLINK | STEP) > 0 and pad & VALUE == 0 then
            -- HIGH White
            color = 1
        elseif pad & (VALUE | STEP) > 0 or pad & (BLINK | VALUE) > 0 and pad & STEP == 0 then
            color = grid.rainbow_on[(seq_value - 1) % 16 + 1]
        end
   
        s.led[x][y] = color
    end)
    grid:refresh('PresetSeq:set_grid')
end

function PresetSeq:transport_event(auto, data)
    if App.recording then
        if auto.step % self.step_length == 0 then
            self:set_select()
            self:set_step(math.floor(auto.step / self.step_length) + 1, self.select)
        end
    end
    self:set_grid(auto)
end

function PresetSeq:alt_event(data)

    if data.state and self.mode.alt then
        self.index = nil
        self.mode:cancel_context()
        self:start_blink()
        local auto = self:get_component()
        self:set_grid(auto)
        local cleanup = self:on('alt_reset', function()
            self:end_blink()
            local auto = self:get_component()
            self:set_grid(auto)
            cleanup()
        end)
    elseif data.state then
        self:end_blink()
        self.index = nil
        local auto = self:get_component()
        self:set_grid(auto)
    end
end

function PresetSeq:row_event(data)
    if data.state then
      self.track = data.row
    end
end
  

return PresetSeq