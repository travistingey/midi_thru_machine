--Extends util to include additional helpers for this App
local u = {}

function u.concat_table(t1,t2)
    for i=1,#t2 do
       t1[#t1+1] = t2[i]
    end
    return t1
 end

function u.unrequire(name)
	package.loaded[name] = nil
	_G[name] = nil
end

function u.removeDuplicates(arr)
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

-- Takes a table of functions as a parameter and returns a single function chained in a pipeline
function u.chain_functions(funcs)
    return function(input)
        local value = input
        for i, func in ipairs(funcs) do
            value = func(value)
        end
        return value
    end
end



-- Then return the combined table
return u