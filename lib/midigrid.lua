MidiGrid = {}

function MidiGrid:new (o)
  o = o or {}
  
  setmetatable(o, self)
  self.__index = self
  
  o.event = o.event or function(s, data)
      if data.state then 
       s:led( data.x, data.y, s.default_on[data.x][data.y])
      else
        s:led( data.x, data.y, s.default_off[data.x][data.y])
      end
    end
  
  o.channel = o.channel or 2
  o.led = {{},{},{},{},{},{},{},{},{}}
  o.toggled = {{},{},{},{},{},{},{},{},{}}
  o.down = {{},{},{},{},{},{},{},{},{}}
  
  o.midi = midi.connect(o.channel)
  o.midi:send({240,0,32,41,2,13,0,127,247})  -- Set to Programmer Mode
  
  
  o.midi.event = function(d)
    local msg = midi.to_msg(d)
    local data = {}
    local x,y
    if(msg.type == 'note_on' or msg.type == 'note_off' or msg.type == 'cc') then 
      if(msg.type == 'note_on' or msg.type == 'note_off') then
        x = math.fmod(msg.note,10)
        y =  math.floor(msg.note/10)
          
        data.state = (msg.type == 'note_on')
  
      elseif (msg.type == 'cc') then
        x = math.fmod(msg.cc,10)
        y =  math.floor(msg.cc/10)
        data.state = (msg.val == 127)
      end
      
      data.x = x
      data.y = y
      
      if (not y) then tab.print(msg) end
      
      if(x == 9) then data.type = 'row'
        elseif (x == 1 and y == 9) then data.type = 'up'
        elseif (x == 2 and y == 9) then data.type = 'down'
        elseif (x == 3 and y == 9) then data.type = 'left'
        elseif (x == 4 and y == 9) then data.type = 'right'
        elseif (x >= 5 and x <= 8 and y == 9) then data.type = 'mode'
        else
          data.type = 'pad'
      end
      --Set states
      
      o.down[x][y] = data.state
      
      if data.state then
          o.toggled[x][y] = (not o.toggled[x][y])
      end
      
      --Event Handler
      o:event(data)
    end
  end

  return o
end

function MidiGrid.set_led(x,y,z)
  
    local target = math.fmod(x,10) + 10 * y
    local message = {}
  
    if(type(z) == 'table')then
        if #z == 3 then
            -- length of 3, RGB
            message = table.concat(message,{3,target})
            message = table.concat(message,z)    
       
        elseif #z == 2 and z[2] == true then
            -- length of 2, second value is true
            message = table.concat(message,{2,target})
            message = table.concat(message,z)
        
        elseif #z == 2 then
            -- length of 2
            message = table.concat(message,{1,target})
            message = table.concat(message,z)
            
        else
            -- length of 1 
            message = table.concat(message,{0,target})
            message = table.concat(message,z)
            
        end
      else
        -- send single value to led
        message = table.concat(message,{0,target})
        message = table.concat(message,{z})
        
    end

   
    return message

end

function MidiGrid:redraw()
    local message = {240,0,32,41,2,13,3}
    for x = 1, 9 do
      for y = 1, 9 do
        
          if (self.led[x][y] == nil) then
            local m = self.set_led(x,y,0)
            message = table.concat(message,m)
          else
              local m = self.set_led(x,y,self.led[x][y])
              message = table.concat(message, m )
          end
      end
    end
    
    message = table.concat(message,{247})
     self.midi:send(message)
end

--

function MidiGrid.grid_to_index(pos,grid_start,grid_end)
  grid_start = grid_start or {x=1,y=1}
  grid_end = grid_end or {x=9,y=9}
   
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

--

function table.concat(t1,t2)
   for i=1,#t2 do
      t1[#t1+1] = t2[i]
   end
   return t1
end

return MidiGrid