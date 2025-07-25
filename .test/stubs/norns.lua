-- Stubs for norns hardware APIs to run tests headlessly

screen = setmetatable({}, {
  __index = function()
    return function() end
  end
})

engine = setmetatable({}, {
  __index = function()
    return function() end
  end
})

params = {
  _values = {},
  add_number = function() end,
  add_option = function() end,
  add_binary = function() end,
  add_control = function() end,
  add_separator = function() end,
  add_group = function() end,
  hide = function() end,
  set = function(_, k, v) params._values[k] = v end,
  get = function(_, k) return params._values[k] end,
  set_action = function() end
}

midi = {
  vports = {},
  connect = function() return {name = 'none', send = function() end} end,
  to_msg = function(msg) return msg end
}

clock = {
  run = function(fn) return fn end,
  sync = function() end,
  cancel = function() end,
  get_beats = function() return 0 end,
  get_tempo = function() return 120 end,
  sleep = function() end
}

util = {
  trim_string_to_width = function(s) return s end,
  string_starts = function(str, start) return str:sub(1,#start) == start end,
  clamp = function(x,a,b) if x<a then return a elseif x>b then return b else return x end end,
  wrap = function(x,a,b) if b<=a then return a end return ((x-a) % (b-a+1)) + a end
}

crow = {
  send = function() end,
  input = { {}, {} },
  output = { {}, {}, {}, {} }
}

return {
  screen = screen,
  engine = engine,
  params = params,
  midi = midi,
  clock = clock,
  util = util,
  crow = crow
}
