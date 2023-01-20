Mode = {}

function Mode:save()
    tab.save(Mode, '')
end

function Mode:load()
	
	for i = 1, 4 do
		self[i] = Seq:new({
			display = true,
			grid = g,
			div = 3 * 2^(params:get('mode_'.. i ..'_div')),
			length = params:get('mode_'.. i ..'_length'),
			actions = 16
		})
	end

	self[1].action = function(d) Preset.load(d) end
	self[2].action = function(d) print('Mode ' .. 2 .. ', Action ' .. d) end
	self[3].action = function(d) print('Mode ' .. 3 .. ', Action ' .. d) end
	self[4].action = function(d) print('Mode ' .. 4 .. ', Action ' .. d) end
    
	self.select = 1
	self[self.select]:set_grid()
end

function Mode:set_mode(d)
	for i = 1, 4 do
		if i == self.select then
			self[i].display = true
		else
			self[i].display = false
		end
	end

	self[self.select]:set_grid()
end