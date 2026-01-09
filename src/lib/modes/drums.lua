local Mode = require('Foobar/lib/components/app/mode')
local Default = require('Foobar/lib/components/mode/default')

local DrumsMode = Mode:new({
    id = 2,
    components = { Default:new({}) }
})

return DrumsMode 
