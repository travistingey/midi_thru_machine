-- Note: This is highly customized to interface with the 1010music BitBox Mk II

local path_name = 'Foobar/lib/'
local ModeComponent = require('Foobar/components/mode/modecomponent')
local Grid = require(path_name .. 'grid')
local PresetSeq = ModeComponent:new()

PresetSeq.__base = ModeComponent
PresetSeq.name = 'presetseq'

function PresetSeq:set(o)
    self.__base.set(self, o)
    self.active = true
    self.select = { type='preset', id = 1, component = 'track' }
    self.index = nil
    self.component = 'auto'  -- Reference to the Auto component

    self.lanes = { 'preset', 'cc' }  -- List of lanes
    self.selected_lane_index = 1                -- Index of the selected lane
    self.selected_lane = self.lanes[self.selected_lane_index]
    
    self.preset_components = {'track', 'scale'}
    self.selected_component_index = 1
    self.selected_component = self.preset_components[self.selected_component_index]

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

function PresetSeq:on_enable()
    self:on('preset_select', function(selection)
        self.mode:reset_timeout()
        if self.blink_mode then
            local auto = self:get_component()

            self:set_select(selection)

            if type(self.last_step) == 'number' then
                auto:set_action(self.last_step, self.select)
            elseif type(self.last_step) == 'table' then 
                for i= self.last_step[1], self.last_step[2] do
                    auto:set_action(i, self.select)
                end
            end
        end
    end)
end

-- If no value is specified, it references the track's current_preset

function PresetSeq:set_select(value)
    local track = self:get_component().track

    if value then
        self.select = { type = self.selected_lane, value = value }
    elseif self.selected_lane == 'preset' then
        self.select = { type='preset', value = track.current_preset }
    elseif self.selected_lane == 'scale' then
        self.select = { type='scale', value = track.current_preset }
    end
    
end

function PresetSeq:grid_event(component, data)
    local grid = self.grid
    local auto = component

    self:set_select()

    if data.type == 'pad_long' and data.pad_down and #data.pad_down == 1 then
        local pad_1 = self.grid:grid_to_index(data)
        local pad_2 = self.grid:grid_to_index(data.pad_down[1])
        local selection_start = math.min(pad_1,pad_2)
        local selection_end = math.max(pad_1,pad_2)
        
        if self.mode.alt then
            auto:set_loop(selection_start, selection_end)
        else
            
            self:start_blink()
            self.mode:reset_timeout()

            self.last_step = {selection_start, selection_end}
            for i = selection_start, selection_end do
                auto:set_action(i, self.select)
            end

        end
    elseif data.type == 'pad' and data.state and not self.mode.alt then
        local index = self.grid:grid_to_index(data)
        local lane = self.selected_lane

        self:start_blink()
        self.mode:reset_timeout()
        self.last_step = index
        
        -- Toggle action
        auto:toggle_action(index,self.select)

        self.index = index

        self.mode:handle_context(self.context, self.screen, {
            timeout = true,
            callback = function()
                self:end_blink()
                self.index = nil
                self:set_grid(auto)
            end
        })
    end
    self:set_grid(auto)
end

function PresetSeq:set_grid(component)
    if self.mode == nil then return end
    local grid = self.grid
    local auto = component  -- 'component' is the Auto component

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
        
        local lane = self.selected_lane

        local seq_entry = auto.seq[i]
        local seq_value = seq_entry and seq_entry[lane] and seq_entry[lane].value
        if seq_value then pad = pad | VALUE end

        if i >= auto.seq_start and i <= auto.seq_start + auto.seq_length - 1 and self.mode.alt then
            pad = pad | INSIDE_LOOP
        end
        if self.mode.alt and (i == auto.seq_start or i == auto.seq_start + auto.seq_length - 1) then
            pad = pad | LOOP_END
        end
        if self.index == i and not self.mode.alt then
            pad = pad | SELECTED
        end
        if auto.step == i and App.playing then
            pad = pad | STEP
        end

        local color
        if pad & (BLINK | SELECTED | INSIDE_LOOP | VALUE) == (BLINK | SELECTED | INSIDE_LOOP | VALUE) then
            if seq_value and type(seq_value) == "number" then
                color = self.grid.rainbow_on[(seq_value - 1) % 16 + 1]
            else
                color = {5,5,5}
            end
        elseif pad & (SELECTED | VALUE | INSIDE_LOOP) == (SELECTED | VALUE | INSIDE_LOOP) then
            if seq_value and type(seq_value) == "number" then
                color = self.grid.rainbow_off[(seq_value - 1) % 16 + 1]
            else
                color = {5,5,5}
            end
        elseif pad & (BLINK | SELECTED | VALUE) == (BLINK | SELECTED | VALUE) then
            if seq_value and type(seq_value) == "number" then
                color = self.grid.rainbow_on[(seq_value - 1) % 16 + 1]
            else
                color = {5,5,5}
            end
        elseif pad & (BLINK | SELECTED) == (BLINK | SELECTED) then
            color = {5,5,5}
        elseif pad & (SELECTED | VALUE) == (SELECTED | VALUE) then
            if seq_value and type(seq_value) == "number" then
                color = self.grid.rainbow_off[(seq_value - 1) % 16 + 1]
            else
                color = {5,5,5}
            end
        elseif pad & (SELECTED) == (SELECTED) then
            color = 0
        elseif pad & (STEP | VALUE) == (STEP | VALUE) then
            if seq_value and type(seq_value) == "number" then
                color = self.grid.rainbow_on[(seq_value - 1) % 16 + 1]
            else
                color = 1
            end
        elseif pad & (STEP) == STEP then
            color = 1
        elseif pad & (BLINK | LOOP_END | VALUE) == (BLINK | LOOP_END | VALUE) then
            if seq_value and type(seq_value) == "number" then
                color = self.grid.rainbow_on[(seq_value - 1) % 16 + 1]
            else
                color = {5,5,5}
            end
        elseif pad & (BLINK | LOOP_END) == (BLINK | LOOP_END) then
            color = {5,5,5}
        elseif pad & (INSIDE_LOOP | VALUE) == (INSIDE_LOOP | VALUE) then
            if seq_value and type(seq_value) == "number" then
                color = self.grid.rainbow_off[(seq_value - 1) % 16 + 1]
            else
                color = 1
            end
        elseif pad & (VALUE) == (VALUE) then
            if seq_value and type(seq_value) == "number" then
                color = self.grid.rainbow_off[(seq_value - 1) % 16 + 1]
            else
                color = 1
            end
        else
            color = 0
        end

        s.led[x][y] = color
    end)
    grid:refresh('PresetSeq:set_grid')
end

function PresetSeq:transport_event(component, data)
    -- Update grid if necessary based on transport events
    self:set_grid(component)
end

function PresetSeq:on_alt()
    self.index = nil
    self.mode:cancel_context()
    self:start_blink()
    local auto = self:get_component()
    self:set_grid(auto)
end

function PresetSeq:on_alt_reset()
    self:end_blink()
    local auto = self:get_component()
    self:set_grid(auto)
end

function PresetSeq:on_row(data, skip_grid)
    if data.state and App.track[data.row].enabled then
      
      App.current_track = data.row
      self:set_track(App.current_track)
      
      self:end_blink()
      self.skip_set_grid = true
      self.mode:cancel_context()

      App.screen_dirty = true
    end
end
  

return PresetSeq