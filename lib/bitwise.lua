Bitwise = {}
function Bitwise:new(o)
  o = o or {}
  
  setmetatable(o, self)
  self.__index = self
  o.name = o.name 
  o.length = o.length or 16
  o.chance = o.chance or 0.5

  o.triggers = o.triggers or {}
  o.values = o.values or {}
 

  if o.lock == nil then
    local lock = {}
    for i=1, o.length do
      lock[i] = false
    end
    o.lock = lock
  end

  if o.track == nil then
    o:seed()
  end
  
  return o
  
end

function Bitwise:get(i)
    i = i or 1
    if self.format ~= nil then
      return { state = self.triggers[i],  value = self.format(self.values[i]), raw = self.values[i] }
    else
      return { state = self.triggers[i],  value = self.values[i], raw = self.values[i] }
    end
end

function Bitwise:update()
  local v = {}
  local t = {}
  local track = self.track
  
  for i = 1, self.length,1 do
    local length_mask = 65535 >> (16 - self.length)
    
    -- Read value from bits
    if (not self.lock[i]) then
      local mask = 255
      
      -- Is this necessary?
      if self.length < 8 then
        mask = length_mask
      end
      
      local value = (track & mask) / mask
      v[i] = value
      t[i] = (track & 1 > 0)
      else
        if self.values[i] then v[i] = self.values[i] else v[i] = 0 end
        t[i] = true  
    end
 
    track = (track >> 1) | ( track << self.length - 1) & length_mask
  end
    
  self.values = v
  self.triggers = t
end

function Bitwise:cycle(reverse)
  if reverse then
    self:mutate(self.length)

    self.track = (self.track << 1) | ( self.track >> self.length - 1) & 65535 
    
    local v = table.remove(self.values)
    table.insert(self.values,1,v)

    local t = table.remove(self.triggers)
    table.insert(self.triggers,1,t)
    
    local l = table.remove(self.lock)
    table.insert(self.lock,1,l)
  else
    
    self:mutate(1)

    self.track = (self.track >> 1) | ( self.track << self.length - 1) & 65535 
    
    local v = table.remove(self.values,1)
    table.insert(self.values,v)

    local t = table.remove(self.triggers,1)
    table.insert(self.triggers,t)
    
    local l = table.remove(self.lock,1)
    table.insert(self.lock,l)
  end
  

end

function Bitwise:seed(track)
  self.track =  track or math.random(0,65535)
  self.lock = {}
  
  for i=1, self.length do
    self.lock[i] = false
  end
  
  self:update()
end

function Bitwise:mutate(i)
    i = i or 1
    if math.random() > self.chance and not self.lock[i] then
        self:flip(i)
        self:update()
    end
end

function Bitwise:flip(i)
    self.track = self.track ~ (1 << i - 1)
    self:update()
end


return Bitwise
