-- get string or default
function getString(var,default)
	local result = get(var)
	if not result then
		return default
	end
	return tostring(result)
end

-- get number or default
function getNumber(var,default)
	local result = get(var)
	if not result then
		return default
	end
	return tonumber(result)
end

-- get true or false or default
function getBool(var,default)
	local result = get(var)
	if not result then
		return default
	end
	return result == "true" or result == true
end

function ternary(condition,resultIfTrue,resultIfFalse)
	if (condition) then
		return resultIfTrue
	else
		return resultIfFalse
	end
end
