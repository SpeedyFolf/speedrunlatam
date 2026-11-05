function table.dump(t, caption, depth)
	if not depth then
		depth = 1
	end
	if depth == 1 and caption then
		outputDebugString(caption .. ':')
	end
	if not t then
		outputDebugString('Table is nil')
	elseif type(t) ~= 'table' then
		outputDebugString('Argument passed is of type ' .. type(t))
		local str = tostring(t)
		if str then
			outputDebugString(str)
		end
	else
		local braceIndent = string.rep('  ', depth-1)
		local fieldIndent = braceIndent .. '  '
		outputDebugString(braceIndent .. '{')
		for k,v in pairs(t) do
			if type(v) == 'table' and k ~= 'siblings' and k ~= 'parent' then
				outputDebugString(fieldIndent .. tostring(k) .. ' = ')
				table.dump(v, nil, depth+1)
			else
				outputDebugString(fieldIndent .. tostring(k) .. ' = ' .. tostring(v))
			end
		end
		outputDebugString(braceIndent .. '}')
	end
end


function table.filter(t, callback, cmpval)
	if cmpval == nil then
		cmpval = true
	end
	for k,v in pairs(t) do
		if callback(v) ~= cmpval then
			t[k] = nil
		end
	end
	return t
end

function table.create(keys, vals)
	local result = {}
	if type(vals) == 'table' then
		for i,k in ipairs(keys) do
			result[k] = vals[i]
		end
	else
		for i,k in ipairs(keys) do
			result[k] = vals
		end
	end
	return result
end

function table.each(t, index, callback, ...)
	local args = { ... }
	if type(index) == 'function' then
		table.insert(args, 1, callback)
		callback = index
		index = false
	end
	for k,v in pairs(t) do
		callback(index and v[index] or v, unpack(args))
	end
	return t
end

function table.insertUnique(t,val)
	if not table.find(t, val) then
		table.insert(t,val)
	end
end

function table.count(t)
	if type(t) ~= "table" then return nil end
	local c = 0
	for _,_ in pairs(t) do
		c = c +1
	end
	return c
end


function Set(...)
  local set = {}
  for _, l in ipairs(arg) do set[l] = true end
  return set
end

function IfElse(condition, a, b)
	if condition then return a end
	return b
end


function string:split(sep)
	if #self == 0 then
		return {}
	end
	sep = sep or ' '
	local result = {}
	local from = 1
	local to
	repeat
		to = self:find(sep, from, true) or (#self + 1)
		result[#result+1] = self:sub(from, to - 1)
		from = to + 1
	until from == #self + 2
	return result
end



--
-- PLAYER
--

-- remove color coding from string
function removeColorCoding (name)
	return type(name)=="string" and string.gsub(name, "#%x%x%x%x%x%x", "") or name
end

-- getPlayerKey with color coding removed
local _getPlayerName = getPlayerName
function getPlayerName(player)
	if type(player) == "string" then
		return removeColorCoding(player)
	end

	-- Check if the variable is a valid element and is actually a player
	if player and isElement(player) and getElementType(player) == "player" then
		return removeColorCoding(_getPlayerName(player))
	end

	-- Return false or a fallback string if it's not a valid player
	return false
end

getPlayerKey = getPlayerName


ModelID = {
	MotorBikes = Set(448, 461, 462, 463, 468, 471, 521, 522, 523, 581, 586),
	Bikes = Set(481, 509, 510),
	Boats = Set(539, 447, 472, 473, 493, 595, 484, 430, 453, 452, 446, 454),
	Aircraft = Set(592, 577, 511, 548, 512, 593, 425, 520, 417, 487, 553, 488, 497, 563, 476, 447, 519, 460, 469, 513),
	Exempt = Set(441, 464, 465, 501, 564, 594, 537, 538, 569, 590, 594, 449)
}
