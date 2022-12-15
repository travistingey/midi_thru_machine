-- HTTPS://NOR.THE-RN.INFO
-- NORNSILERPLATE
-- >> k1: exit
-- >> k2:
-- >> k3:
-- >> e1:
-- >> e2:
-- >> e3:

local path_name = 'Foobar/lib/'
MidiGrid = require (path_name .. 'midigrid')
musicutil = require ('musicutil')
util = require('util')



------------------------------------------------------------------------------------------------------------------------------


function init() 
  
  message = "Foobar"
  screen_dirty = true
  redraw_clock_id = clock.run(redraw_clock)
  
  transport = midi.connect(1)
  
  g = MidiGrid:new({
    event = grid_event
  })
  

  midi_out = midi.connect(3)
  
  
  drum_map = {}
  drum_map[36] = {x = 1, y = 1}
  drum_map[37] = {x = 2, y = 1}
  drum_map[38] = {x = 3, y = 1}
  drum_map[39] = {x = 4, y = 1}
  drum_map[40] = {x = 1, y = 2}
  drum_map[41] = {x = 2, y = 2}
  drum_map[42] = {x = 3, y = 2}
  drum_map[43] = {x = 4, y = 2}
  drum_map[44] = {x = 1, y = 3}
  drum_map[45] = {x = 2, y = 3}
  drum_map[46] = {x = 3, y = 3}
  drum_map[47] = {x = 4, y = 3}
  drum_map[48] = {x = 1, y = 4}
  drum_map[49] = {x = 2, y = 4}
  drum_map[50] = {x = 3, y = 4}
  drum_map[51] = {x = 4, y = 4}
  
  Mutes = {
    grid_start = {x = 1, y = 1},
    grid_end = {x = 4, y = 4},
    toggled = {false,false,false,false,false,false,false,false,false,false,false,false,false,false,false,false},
    transport = handle_mute_transport,
    grid = handle_mute_grid
  }
  
  Presets = {
    grid_start = {x = 5, y = 4},
    grid_end = {x = 8, y = 1},
    active = 1,
    preset = {{},{},{},{},{},{},{},{},{},{},{},{},{},{},{},{}},
    transport = handle_preset_transport,
    grid = handle_preset_grid
  }
  
  Sequence = {
    grid_start = { x = 1, y = 8 },
    grid_end = {x = 8, y = 5},
    div = 12,
    length = grid_to_index({x = 8, y = 5},{x = 1, y = 8},{x = 8, y = 5}),
    sequence = {},
    tick = 1,
    step = 1
  }
  
  -- PRESETS  
  presets = {}
  for i = 1, 16 do
      presets[i] =  {}
      
      for j = 1,16 do
        presets[i][j] = false
      end
  end
  
  preset_select = 1

  for x = 5, 8 do
    for y = 1, 4 do
      g.led[x][y] = {10,4,0}
    end
  end
  




    -- Transport Event Handler for incoming midi notes from the Beatstep Pro.
  transport.event = function(msg)
    local data = midi.to_msg(msg)
   
    
    handle_seq_transport(data)
    handle_mute_transport(data)
      
    g:redraw()
  end
end -- end Init

  
seq_map = {}
seq_length = 32
seq_height = 8
seq_width = 8
seq_div = 12

for i=1,seq_length do
  seq_map[i] = {
    x = util.wrap(i,1,seq_width),
    y = seq_height- math.floor((i-1)/seq_width),
    state = (math.fmod(i,2) == 1)
  }

end


seq_tick = 0
seq_step = 1

function handle_seq_transport(data)
  -- Tick based sequencer running on 16th notes at 24 PPQN
    if data.type == 'clock' then
      seq_tick = util.wrap(seq_tick + 1,1, seq_div * seq_length)
      local next_step = util.wrap(math.floor(seq_tick/seq_div) + 1,1,seq_length)
      
      -- Enter new step. c = current step, l = last step
      if next_step > seq_step or next_step == 1 then
        local l = seq_map[seq_step]
        local c = seq_map[next_step]
        
        if(l.state) then
          g.led[l.x][l.y] = 1
        else
          g.led[l.x][l.y] = 0  
        end
        
        if c.state then
          g.led[c.x][c.y] = 12
        else
          g.led[c.x][c.y] = 16  
        end

      end
      
      seq_step = next_step
    end
    
    -- Note: 'Start' is called at the beginning of the sequence
    if data.type == 'start' then
      seq_tick = 0
      seq_step = 1
    end
  
end

function handle_seq_grid(s, data)
  local x = data.x
  local y = data.y
  
  if x < 8 and y > 4 and y < 9 then
    
  end
end

function handle_mute_transport(data)
  -- react only to drum pads
      if data.ch == 10  and drum_map[data.note] then
        local target = drum_map[data.note]
        
        if(not g.toggled[target.x][target.y]) then
          -- Mute is off
          if data.type == 'note_on' then
            g.led[target.x][target.y] = 3 -- note_on unmuted.
          elseif data.type == 'note_off' then
            g.led[target.x][target.y] = 0 -- note_on unmuted.
          end
          midi_out:send(data)
        else
          -- Mute is on
          midi_out:note_off(data.note,64,10)
          if data.type == 'note_on' then
            g.led[target.x][target.y] = 5 -- note_On muted.
          elseif data.type == 'note_off' then
            g.led[target.x][target.y] = 7 -- note_off muted.
          end
        end
      end
  end



-- MidiGrid Event Handler
-- Event triggered for every pad up and down event — TRUE state is a pad up event, FALSE state is a pad up event.
-- param s = self, MidiGrid instance
-- param data = { x = 1-9, y = 1-9, state = boolean }
function grid_event(s,data)
  handle_alt_grid(s, data) -- Toggles alt button state
  handle_mute_grid(s, data) -- Sets display of mute buttons
  handle_preset_grid(s,data) -- Manages loading and saving of mute states
  g:redraw()

end

-- The Alt button is the grid pad used to access secondary functions. 
-- Based on the toggle state, tapping Alt will toggle on or off
-- Methods using Alt check if the toggle state is true and should reset toggle state to false after event completes
function handle_alt_grid(s,data)
  local x = data.x
  local y = data.y
  
  -- Alt button
  if x == 9 and y == 1 and s.toggled[x][y] then
      s.state[x][y] = true
  elseif x == 9 and y == 1 then 
      s.state[x][y] = false
  end
end


-- Mutes are used to prevent incoming MIDI notes from passing through.
-- Based on toggle state, handler just handles LEDs, transport handles muting and live LED visuals
function handle_mute_grid(s,data)
  local x = data.x
  local y = data.y
  
  -- Set off state for mutes
  if x <= 4 and y <= 4 then
    if s.toggled[x][y] then
      g.led[x][y] = 7
    else
      g.led[x][y] = 0
    end
  end  
end


-- Presets are used to store different combination of mute settings, stored as a 2D table
-- Ony one preset in a bank is active at a time.
-- Pressing pad will load preset. Pressing alt + pad will save current mutes as a preset
function handle_preset_grid(s,data)
  local x = data.x
  local y = data.y
  local alt = s.state[9][1]
  
  -- Preset Select
  if(x >= 5 and x <=8 and y >= 1 and y <= 4 and data.state) then
     preset_select = (4 - y) * 4 + x - 4
    
     if alt then
        
        local save_state = {}
        -- Save Preset
        for px = 1, 4 do
            for py = 1, 4 do
              save_state[#save_state + 1] = (s.toggled[px][py])
            end
        end
        presets[preset_select] = save_state
        print('Saved Preset ' .. preset_select)
        
        s.state[9][1] = false
        s.toggled[9][1] = false
      else
        
      -- Load Preset
        local pset = presets[preset_select]
    
        for i = 1, 16 do
          local px = math.floor((i-1)/4) + 1
          local py = util.wrap(i,1,4)
 
          s.toggled[px][py] = pset[i]
          
          if pset[i] then
            g.led[px][py] = 7
            else
              g.led[px][py] = 0
          end
            
        end
           
     end
     
      -- Preset Leds
      for px = 5, 8 do
          for py = 1, 4 do
            if px == x and py == y then
              g.state[px][py] = true
            else
              g.state[px][py] = false
            end
          end
      end
  end
end


function grid_to_index(pos,grid_start,grid_end)
   
  local width = math.abs(grid_end.x - grid_start.x) + 1
  local max_x = math.max(grid_start.x,grid_end.x)
  local max_y = math.max(grid_start.y,grid_end.y)
  local min_x = math.min(grid_start.x,grid_end.x)
  local min_y = math.min(grid_start.y,grid_end.y)
  
  if pos.x <= max_x and pos.x >= min_x and pos.y <= max_y and pos.y >- min_y then
    return math.abs(pos.y - grid_start.y) * width + math.abs(pos.x - grid_start.x) + 1
  else
    -- out of bounds
    return false
  end
end




function enc(e, d) --------------- enc() is automatically called by norns
  if e == 1 then turn(e, d) end -- turn encoder 1
  if e == 2 then turn(e, d) end -- turn encoder 2
  if e == 3 then turn(e, d) end -- turn encoder 3
  screen_dirty = true ------------ something changed
end

function turn(e, d) ----------------------------- an encoder has turned
  message = "encoder " .. e .. ", delta " .. d -- build a message
end

function key(k, z) ------------------ key() is automatically called by norns
  if z == 0 then return end --------- do nothing when you release a key
  if k == 2 then press_down(2) end -- but press_down(2)
  if k == 3 then press_down(3) end -- and press_down(3)
  screen_dirty = true --------------- something changed
end

function press_down(i) ---------- a key has been pressed
  message = "press down " .. i -- build a message
end

function redraw_clock() ----- a clock that draws space
  while true do ------------- "while true do" means "do this forever"
    clock.sleep(1/15) ------- pause for a fifteenth of a second (aka 15fps)
    if screen_dirty then ---- only if something changed
      redraw() -------------- redraw space
      screen_dirty = false -- and everything is clean again
    end
  end
end

function redraw() -------------- redraw() is automatically called by norns
  screen.clear() --------------- clear space
  screen.aa(1) ----------------- enable anti-aliasing
  screen.font_face(1) ---------- set the font face to "04B_03"
  screen.font_size(8) ---------- set the size to 8
  screen.level(15) ------------- max
  screen.move(64, 32) ---------- move the pointer to x = 64, y = 32
  screen.text_center(message) -- center our message at (64, 32)
  screen.move(64, 24)
  screen.pixel(0, 0) ----------- make a pixel at the north-western most terminus
  screen.pixel(127, 0) --------- and at the north-eastern
  screen.pixel(127, 63) -------- and at the south-eastern
  screen.pixel(0, 63) ---------- and at the south-western
  screen.fill() ---------------- fill the termini and message at once
  screen.update() -------------- update space
end

------------------------------------------------------------------------------------------------------------------------------------
function removeDuplicates(arr)
    local newArray = {}
    local checkerTbl = {}
    for _, element in ipairs(arr) do
        if not checkerTbl[element] then
            checkerTbl[element] = true
            table.insert(newArray, element)
        end
    end
    return newArray
end



function unrequire(name) 
  package.loaded[name] = nil
  _G[name] = nil
end

function r() ----------------------------- execute r() in the repl to quickly rerun this script
  unrequire (path_name .. 'midigrid')
  norns.script.load(norns.state.script) -- https://github.com/monome/norns/blob/main/lua/core/state.lua
end

function cleanup() --------------- cleanup() is automatically called on script close
  clock.cancel(redraw_clock_id) -- melt our clock vie the id we noted
end