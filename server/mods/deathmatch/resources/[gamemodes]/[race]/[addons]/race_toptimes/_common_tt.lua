--
-- common_tt.lua
--	Common setting for server and client
--

--_DEBUG_LOG = {'UNDEF','MISC','OPTIMIZATION','TOPTIMES','STATE','JOINER','TIMER'}	-- More logging
_TESTING = false			 -- Any user can issue test commands

---------------------------------------------------------------------------
-- Math extentions
---------------------------------------------------------------------------
function math.lerp(from,to,alpha)
	return from + (to-from) * alpha
end

function math.clamp(low,value,high)
	return math.max(low,math.min(value,high))
end

function math.wrap(low,value,high)
	while value > high do
		value = value - (high-low)
	end
	while value < low do
		value = value + (high-low)
	end
	return value
end

function math.wrapdifference(low,value,other,high)
	return math.wrap(low,value-other,high)+other
end

-- curve is { {x1, y1}, {x2, y2}, {x3, y3} ... }
function math.evalCurve( curve, input )
	-- First value
	if input<curve[1][1] then
		return curve[1][2]
	end
	-- Interp value
	for idx=2,#curve do
		if input<curve[idx][1] then
			local x1 = curve[idx-1][1]
			local y1 = curve[idx-1][2]
			local x2 = curve[idx][1]
			local y2 = curve[idx][2]
			-- Find pos between input points
			local alpha = (input - x1)/(x2 - x1);
			-- Map to output points
			return math.lerp(y1,y2,alpha)
		end
	end
	-- Last value
	return curve[#curve][2]
end
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- String extentions
---------------------------------------------------------------------------
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
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- Table extentions
---------------------------------------------------------------------------
function table.map(t, callback, ...)
	for k,v in ipairs(t) do
		t[k] = callback(v, ...)
	end
	return t
end

function table.maptry(t, callback, ...)
	for k,v in pairs(t) do
		t[k] = callback(v, ...)
		if not t[k] then
			return false
		end
	end
	return t
end

function table.find(t, ...)
	local args = { ... }
	if #args == 0 then
		for k,v in pairs(t) do
			if v then
				return k
			end
		end
		return false
	end

	local value = table.remove(args)
	if value == '[nil]' then
		value = nil
	end
	for k,v in pairs(t) do
		for i,index in ipairs(args) do
			if type(index) == 'function' then
				v = index(v)
			else
				if index == '[last]' then
					index = #v
				end
				v = v[index]
			end
		end
		if v == value then
			return k
		end
	end
	return false
end

function table.merge(t1, t2)
	local l = #t1
	for i,v in ipairs(t2) do
		t1[l+i] = v
	end
	return t1
end

function table.removevalue(t, val)
	for i,v in ipairs(t) do
		if v == val then
			table.remove(t, i)
			return i
		end
	end
	return false
end

function table.deletevalue(t, val)
	for k,v in pairs(t) do
		if v == val then
			t[k] = nil
			return k
		end
	end
	return false
end

function table.deepcopy(t)
	local known = {}
	local function _deepcopy(t)
		local result = {}
		for k,v in pairs(t) do
			if type(v) == 'table' then
				if not known[v] then
					known[v] = _deepcopy(v)
				end
				result[k] = known[v]
			else
				result[k] = v
			end
		end
		return result
	end
	return _deepcopy(t)
end

function table.random(t)
	return t[math.random(#t)]
end

function table.dump(t, caption, depth)
	if not depth then
		depth = 1
	end
	if depth == 1 and caption then
		outputConsole(caption .. ':')
	end
	if not t then
		outputConsole('Table is nil')
	elseif type(t) ~= 'table' then
		outputConsole('Argument passed is of type ' .. type(t))
		local str = tostring(t)
		if str then
			outputConsole(str)
		end
	else
		local braceIndent = string.rep('  ', depth-1)
		local fieldIndent = braceIndent .. '  '
		outputConsole(braceIndent .. '{')
		for k,v in pairs(t) do
			if type(v) == 'table' and k ~= 'siblings' and k ~= 'parent' then
				outputConsole(fieldIndent .. tostring(k) .. ' = ')
				table.dump(v, nil, depth+1)
			else
				outputConsole(fieldIndent .. tostring(k) .. ' = ' .. tostring(v))
			end
		end
		outputConsole(braceIndent .. '}')
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

function table.popLast(t,val)
	if #t==0 then
		return false
	end
	local last = t[#t]
	table.remove(t)
	return last
end
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- Time functions
---------------------------------------------------------------------------
function getSecondCount()
 	return getTickCount() * 0.001
end

function msToTimeStr(ms)
	if not ms or ms == 0 then
		return ''
	end
	local milliseconds = tostring(math.floor(math.fmod(ms, 1000)))
	if #milliseconds == 1 then
		milliseconds = '00' .. milliseconds
	elseif #milliseconds == 2 then
		milliseconds = '0' .. milliseconds
	end
	local s = math.floor(ms / 1000)
	local seconds = tostring(math.fmod(s, 60))
	if #seconds == 1 then
		seconds = '0' .. seconds
	end
	local minutes = tostring(math.floor(s / 60))
	return minutes .. ':' .. seconds .. '.' .. milliseconds
end

function getTickTimeStr()
	return msToTimeStr(getTickCount())
end

function dateTextToDateCode( text )
	-- yyyy-mm-dd hh:mm:ss
	-- 123456789 123456789
	local year = tonumber(string.sub(text, 1, 4))
	local month = tonumber(string.sub(text, 6, 7))
	local day = tonumber(string.sub(text, 9, 10))
	local hour = tonumber(string.sub(text, 12, 13))
	local minute = tonumber(string.sub(text, 15, 16))
	local second = tonumber(string.sub(text, 18, 19))
	return getTimestamp(year, month, day, hour, minute, second)
end

function getTimestamp(year, month, day, hour, minute, second)
    -- initiate variables
    local monthseconds = { 2678400, 2419200, 2678400, 2592000, 2678400, 2592000, 2678400, 2678400, 2592000, 2678400, 2592000, 2678400 }
    local timestamp = 0
    local datetime = getRealTime()
    year, month, day = year or datetime.year + 1900, month or datetime.month + 1, day or datetime.monthday
    hour, minute, second = hour or datetime.hour, minute or datetime.minute, second or datetime.second

    -- calculate timestamp
    for i=1970, year-1 do timestamp = timestamp + (isLeapYear(i) and 31622400 or 31536000) end
    for i=1, month-1 do timestamp = timestamp + ((isLeapYear(year) and i == 2) and 2505600 or monthseconds[i]) end
    timestamp = timestamp + 86400 * (day - 1) + 3600 * hour + 60 * minute + second

    timestamp = timestamp - 3600 --GMT+1 compensation
    if datetime.isdst then timestamp = timestamp - 3600 end

    return timestamp
end

function isLeapYear(year)
    if year then year = math.floor(year)
    else year = getRealTime().year + 1900 end
    return ((year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0)
end

function dateCodeToDateText( seconds )
	if not seconds or seconds == 0 then
		return ''
	end

	time = getRealTime(seconds)

	return string.format( '%04d-%02d-%02d'-- %02d:%02d:%02d'
						,time.year + 1900
						,time.month + 1
						,time.monthday
						-- ,time.hour
						-- ,time.minute
						-- ,time.second
						)
end

---------------------------------------------------------------------------
-- Misc functions
---------------------------------------------------------------------------

-- Get player Team Color
function getPlayerNameColored(player)
	local playerTeam = getPlayerTeam ( player )
	if ( playerTeam ) then
		local r,g,b = getTeamColor ( playerTeam )
		local n1 = convertToHexColor(r)
		local n2 = convertToHexColor(g)
		local n3 = convertToHexColor(b)
		if r <= 16 then n1 = "0"..n1 end
		if g <= 16 then n2 = "0"..n2 end
		if b <= 16 then n3 = "0"..n3 end
		return "#"..n1..""..n2..""..n3..""..getPlayerNametagText(player)
	else
		return getPlayerNametagText(player)
	end
end

-- Convert rgb color to Hexcolor
function convertToHexColor ( n )
    local hexnums = {"0","1","2","3","4","5","6","7",
                     "8","9","a","b","c","d","e","f"}
    local str,r = "",n%16
    if n-r == 0 then str = hexnums[r+1]
    else str = convertToHexColor((n-r)/16)..hexnums[r+1] end
    return str
end

-- remove color coding from string
function removeColorCoding ( name )
	return type(name)=='string' and string.gsub ( name, '#%x%x%x%x%x%x', '' ) or name
end

-- getPlayerName with color coding removed
_getPlayerName = getPlayerName
function getPlayerName ( player )
	return removeColorCoding ( _getPlayerName ( player ) )
end
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- Camera functions
---------------------------------------------------------------------------
function getCameraRot()
	local px, py, pz, lx, ly, lz = getCameraMatrix()
	local rotz = math.atan2 ( ( lx - px ), ( ly - py ) )
 	local rotx = math.atan2 ( lz - pz, getDistanceBetweenPoints2D ( lx, ly, px, py ) )
 	return math.deg(rotx), 180, -math.deg(rotz)
end
---------------------------------------------------------------------------


---------------------------------------------------------------------------
-- Timer - Wraps a standard timer
---------------------------------------------------------------------------
Timer = {}
Timer.__index = Timer
Timer.instances = {}

-- Create a Timer instance
function Timer:create()
	local id = #Timer.instances + 1
	Timer.instances[id] = setmetatable(
		{
			id = id,
			timer = nil,		-- Actual timer
		},
		self
	)
	return Timer.instances[id]
end

-- Destroy a Timer instance
function Timer:destroy()
	self:killTimer()
	Timer.instances[self.id] = nil
	self.id = 0
end

-- Check if timer is valid
function Timer:isActive()
	return self.timer ~= nil
end

-- killTimer
function Timer:killTimer()
	if self.timer then
		killTimer( self.timer )
		self.timer = nil
	end
end

-- setTimer
function Timer:setTimer( theFunction, timeInterval, timesToExecute, ... )
	self:killTimer()
	self.fn = theFunction
	self.count = timesToExecute
	self.args = { ... }
	self.timer = setTimer( function() self:handleFunctionCall() end, timeInterval, timesToExecute )
end

function Timer:handleFunctionCall()
	-- Delete reference to timer if there are no more repeats
	if self.count > 0 then
		self.count = self.count - 1
		if self.count == 0 then
			self.timer = nil
		end
	end
	self.fn(unpack(self.args))
end

---------------------------------------------------------------------------
