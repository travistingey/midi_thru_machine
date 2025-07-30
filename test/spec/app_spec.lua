require('norns')
local AppMod = require('lib/app')

App = {ppqn=24, device_manager={get=function() return {send=function() end} end}}

describe('App event system', function()
  it('registers and emits events', function()
    local a = AppMod:new{}
    local hit=false
    a:on('ping', function() hit=true end)
    a:emit('ping')
    assert.is_true(hit)
  end)
end)
