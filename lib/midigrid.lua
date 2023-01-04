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
  
  o.state = {{},{},{},{},{},{},{},{},{}} -- KILL THIS ONE
  
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
            message = concat_table(message,{3,target})
            message = concat_table(message,z)    
       
        elseif z[2] == true and #z == 2  then
            -- length of 2, second value is true
            message = concat_table(message,{2,target})
            message = concat_table(message,z)
        
        elseif #z == 2 then
            -- length of 2
            message = concat_table(message,{1,target})
            message = concat_table(message,z)
            
        else
            -- length of 1 
            message = concat_table(message,{0,target})
            message = concat_table(message,z)
            
        end
      else
        -- send single value to led
        message = concat_table(message,{0,target})
        message = concat_table(message,{z})
        
    end

   
    return message

end

function MidiGrid:redraw()
    local message = {240,0,32,41,2,13,3}
    for x = 1, 9 do
      for y = 1, 9 do
        
          if (self.led[x][y] == nil) then
            local m = self.set_led(x,y,0)
            message = concat_table(message,m)
          else
              local m = self.set_led(x,y,self.led[x][y])
              message = concat_table(message, m )
          end
      end
    end
    
    message = concat_table(message,{247})
    self.midi:send(message)
end

--

function MidiGrid.get_bounds(grid_start,grid_end)
  
  return {
      width = math.abs(grid_end.x - grid_start.x) + 1,
      height = math.abs(grid_end.y - grid_start.y) + 1,
      max_x = math.max(grid_start.x,grid_end.x),
      max_y = math.max(grid_start.y,grid_end.y),
      min_x = math.min(grid_start.x,grid_end.x),
      min_y = math.min(grid_start.y,grid_end.y),
  }
end

function MidiGrid.in_bounds(pos,bounds)
  return ( pos.x >= bounds.min_x and pos.x <= bounds.max_x and pos.y >= bounds.min_y and pos.y <= bounds.max_y )
end

function MidiGrid.grid_to_index(pos,grid_start,grid_end)

  local b = MidiGrid.get_bounds(grid_start,grid_end)

  if MidiGrid.in_bounds(pos,b) then
    return math.abs(pos.y - grid_start.y) * b.width + math.abs(pos.x - grid_start.x) + 1
  else
    
    -- out of bounds
    return false
  end
end


function MidiGrid.index_to_grid(index,grid_start,grid_end)
  local b = MidiGrid.get_bounds(grid_start, grid_end)
  local x,y

  if grid_start.x > grid_end.x then
    x = b.width - math.fmod(index - 1,b.width) + b.min_x - 1
  else
    x = math.fmod(index - 1,b.width) + b.min_x
  end

  if grid_start.y > grid_end.y then
    y = b.height - math.floor((index - 1)/b.width) + b.min_y - 1
  else
    y = math.floor((index - 1)/b.width) + b.min_y
  end
  if(y > b.max_y) then 
    return false
  else
    return {x=x,y=y}
  end
end


--

function concat_table(t1,t2)
   for i=1,#t2 do
      t1[#t1+1] = t2[i]
   end
   return t1
end

return MidiGrid