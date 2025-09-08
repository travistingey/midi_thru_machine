local Mode = require('Foobar/lib/components/app/mode')
local ModeDefault = require('Foobar/lib/components/mode/modedefault')

local DrumsMode = Mode:new({
    id = 2,
    components = { ModeDefault:new({}) }
})

return DrumsMode 
