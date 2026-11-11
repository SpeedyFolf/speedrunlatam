
local thisResource = getThisResource()
thisResourceName = getResourceName(thisResource)
thisResourceFriendlyName = getResourceInfo(thisResource, "name") or thisResourceName

--
-- DEBUG
--

function alert(message, ...)
	if not Settings["debugMessages"] then return end
	local text = string.format("[%s] %s", thisResourceName, message)
	outputDebugString(string.format(text, unpack({...})))
end

function console(message, ...)
	local recipient = root
	local args = {...}
	if args and #args > 0 then
		local arg1 = args[1]
		if type(arg1) == "userdata" then
			recipient = arg1
			table.remove(args, 1)
		end
	end
	local text = string.format("[%s] %s", thisResourceFriendlyName, message)
	if getElementType(recipient) == "console" then
		outputDebugString(string.format(text, unpack(args)))
	else
		outputConsole(string.format(text, unpack(args)), recipient)
	end
end

function chat(message, ...)
	local recipient = root
	local args = {...}
	if args and #args > 0 then
		local arg1 = args[1]
		if type(arg1) == "userdata" then
			recipient = arg1
			table.remove(args, 1)
		end
	end
	local text
	if getElementType(recipient) == "console" then
		text = string.format("[%s] %s", thisResourceFriendlyName, message)
		outputDebugString(string.format(text, unpack(args)))
	else
		text = string.format("%s%s", Settings["messageColor"], message)
		exports.infobox:outputInfoBox(recipient, string.format(text, unpack(args)))
	end
end


Stat = {
	-- Vehicles
	DIST_FOOT = 3,
	DIST_CAR = 4,
	DIST_BIKE = 5,
	DIST_BOAT = 6,
	DIST_AIRCRAFT = 8,
	DIST_SWIMMING = 26,
	DIST_CYCLE = 27,
	CARS_DESTROYED = 122,
	BIKES_DESTROYED = 1125,
	BOATS_DESTROYED = 123,
	AIRCRAFT_DESTROYED = 124,
	DAMAGE_TAKEN = 1090,
	VEHICLES_STOLEN = 183,


	--Player
	KILLS = 121,
	TIMES_DIED = 135,
	DRIVING_SKILL = 160,
	FLYING_SKILL = 223,
	BIKE_SKILL = 229,
	CYCLE_SKILL = 230,
	PLAYING_TIME = 1001,
	LAST_SEEN = 1002,
	FAT = 21,
	STAMINA = 22,
	BODY_MUSCLE = 23,
	MAX_HEALTH = 24,

	-- Cash
	CASH_EARNINGS = 1011,
	TOTAL_SHOPPING_BUDGET = 62,
	CURRENT_CASH_BALANCE = 1012,

	-- Races
	CHECKPOINTS_COLLECTED = 1024,
	TOTAL_RACES = 148,
	RACES_FINISHED = 1025,
	RACES_WON = 1026,
	TOPTIMES_SET = 1027,
	MAX_STREAKS = 1028,
	RACES_FINISHED2ND = 1032,
	RACES_FINISHED3RD = 1033,
	EXPERIENCE_POINTS = 2010
}


StatLabel = {
	[3]="Distance on foot",
	[4]="Distance by car",
	[5]="Distance by motorbike",
	[6]="Distance by boat",
	[8]="Distance by aircraft",
	[27]="Distance by bycicle",
	[122]="Cars destroyed",
	[1125]="Bikes destroyed",
	[123]="Boats destroyed",
	[124]="Planes & Helicopters destroyed",
	[183]="Vehicles stolen",

	[1090]="Damage taken",
	[121]="Kills",
	[135]="Deaths",
	[1001]="Playing time",
	[1002]="Last seen",
	[21]="Fatness",
	[23]="Muscle",

	[148]="Race starts",
	[1025]="Race finishes",
	[1026]="Race wins",
	[1027]="Toptimes set",
	[1028]="Max winning streaks",
	[1032]="2nd Places",
	[1033]="3rd Places",
	[2010]="Experience points"
}



DefaultStats = {
	[21] = 999
}


--
-- EXPERIENCE POINTS (puntaje por terminar carreras)
--
-- Criterio:
--   * Elegibilidad: se necesitan al menos 'minPlayers' participantes (jugadores
--     que largaron la carrera), aunque alguno no termine. Asi un jugador que
--     corre solo no puede farmear experiencia.
--   * Solo el podio recibe puntos (1o y 2o). Del 3o en adelante: 0.
--   * Bono extra segun la cantidad de jugadores que TERMINARON, con tope
--     (mas dificil de farmear: hay que competir hasta el final).
--   * Bono fijo extra si el jugador marco el WR del mapa (nuevo #1 en toptimes).
--
PointsConfig = {
	minPlayers = 2,
	basePoints = {
		[1] = 3,
		[2] = 2
	},
	wrBonus = 5,
	-- Se recorre de mayor a menor; gana la primera regla que cumpla.
	finisherBonus = {
		{ minFinishers = 5, bonus = 2 },
		{ minFinishers = 3, bonus = 1 }
	}
}

function getFinisherBonus(finisherCount)
	for _, rule in ipairs(PointsConfig.finisherBonus) do
		if finisherCount >= rule.minFinishers then
			return rule.bonus
		end
	end
	return 0
end

function getDestroyedVehicleStatKey(modelId)
	if not modelId then return nil end
	if ModelID.MotorBikes[modelId] then return Stat.BIKES_DESTROYED end
	if ModelID.Boats[modelId] then return Stat.BOATS_DESTROYED end
	if ModelID.Aircraft[modelId] then return Stat.AIRCRAFT_DESTROYED end
	if (not ModelID.Bikes[modelId]) and (not ModelID.Exempt[modelId]) then return Stat.CARS_DESTROYED end
	return nil
end





addEvent("onPlayerStatsUpdate", true)


--
-- PLAYER STATS DATA
--

--[[
The PlayerData structure holds a in-memory copy of
each players stats table.
It is synchronized when a map ends.

PlayerData = {
	"PlayerName" = {
		JoinTime = 0,
		Stats = {
			[4] = 0,
			[160] = 0.3242
		}
	}
}
]]

PlayerData = {}


function InitializePlayerData(playerName)
	if not PlayerData then
		PlayerData = {}
	end

	if not playerName then
		return
	end

	PlayerData[playerName] = {}
	PlayerData[playerName].SessionJoin = getTickCount()
	PlayerData[playerName].JoinTime = getTickCount()
	PlayerData[playerName].Stats = {}
end



--
-- PLAYERS
--

function getActivePlayers()
	local ret = {}
	for _,player in ipairs(getAlivePlayers()) do
		local state = getElementData(player, "state", false)
		if state == "alive" then
			ret[#ret + 1] = player
		end
	end
	return ret
end

function findPlayer(name)
	if not name then return end
	local player = getPlayerFromKey(name)
	if not player then
		local playerName = string.lower(name)
		for _,p in ipairs(getElementsByType("player")) do
			local key = getPlayerKey(p)
			if key then
				if string.find(string.lower(key), playerName, 1, true) then
					player = p
					break
				end
			end
		end
	end
	return player
end

function getPlayerAndName(player)
	local playerName
	if type(player) == "string" then
		playerName = player
		player = nil
	else
		playerName = getPlayerKey(player)
	end

	-- last chance
	if not player then
		for i,p in ipairs(getElementsByType("player")) do
			if getPlayerKey(p) == playerName then
				player = p
				break
			end
		end
	end

	return player, playerName
end



--
-- DATETIME
--

function getRealDateTimeNowString()
	return getRealDateTimeString(getRealTime())
end

function getRealDateTimeString(time)
	if not time or time.year == 0 then
		return ""
	end
	return string.format("%04d-%02d-%02d %02d:%02d:%02d"
		,time.year + 1900
		,time.month + 1
		,time.monthday
		,time.hour
		,time.minute
		,time.second
		)
end

function getRealTimeSeconds()
	return realTimeDateToSeconds(getRealTime())
end

function realTimeDateToSeconds(time)
	return time.timestamp
	-- local leapyears = math.floor((time.year - 72 + 3) / 4)
	-- local days = (time.year - 70) * 365 + leapyears + time.yearday
	-- local seconds = days * 60*60*24
	-- seconds = seconds + time.hour * 60*60
	-- seconds = seconds + time.minute * 60
	-- seconds = seconds + time.second
	-- seconds = seconds - time.isdst * 60*60
	-- return seconds
end


--
-- TABLES
--

function table.count(t)
if type(t) ~= "table" then return 0 end
local r = 0
	for _,_ in pairs(t) do
		r = r + 1
	end
	return r
end

function table.find(t, o)
	if type(t) == "table" then
		for k,v in pairs(t) do
			if o == v then
				return k
			end
		end
	end
	return nil
end

function table.insertUnique(t,val)
    if not table.find(t, val) then
        table.insert(t,val)
    end
end

function Set(...)
  local set = {}
  for _, l in ipairs(arg) do set[l] = true end
  return set
end
