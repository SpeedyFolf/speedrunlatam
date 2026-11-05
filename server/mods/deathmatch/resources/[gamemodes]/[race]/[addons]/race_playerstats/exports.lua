
local c_MaxStatValue = 1000

---
--- EXPORTS
---


-- exported function; do extra checking
function IncrementPlayerStat(playerOrName, statKey, amount)
	if not playerOrName then
		outputDebugString("Missing first parameter: playerOrName [userdata or string]")
		return false
	end

	if not statKey then
		outputDebugString("Missing second parameter: statKey [integer]")
		return false
	end

	if not amount then
		outputDebugString("Missing third parameter: amount [float]");
		return false
	end

	if amount == 0 then
		return true
	end

	return IncrementPlayerStatInternal(playerOrName, statKey, amount)
end


function GetPlayerStatsTable(playerOrName)
	if not playerOrName then
		outputDebugString("Missing first parameter: playerOrName [userdata or string]")
		return false
	end

	return GetPlayerStatsTableInternal(playerOrName)
end

-- exported function; do extra checking
function GetPlayerStatValue(playerOrName, statKey)
	if not playerOrName then
		outputDebugString("Missing first parameter: playerOrName [userdata or string]")
		return false
	end

	if not statKey then
		outputDebugString("Missing second parameter: statKey [integer]")
		return false
	end

	return GetPlayerStatValueInternal(playerOrName, statKey)
end


-- exported function; do extra checking
function SetPlayerStatValue(playerOrName, statKey, value)
	if not playerOrName then
		outputDebugString("Missing first parameter: playerOrName [userdata or string]")
		return false
	end

	if not statKey then
		outputDebugString("Missing second parameter: statKey [integer]")
		return false
	end

	if not value then
		outputDebugString("Missing third parameter: value [float]");
		return false
	end

	return SetPlayerStatValueInternal(playerOrName, statKey, value)
end


-- exported function; do extra checking
function ClearPlayerStats(playerOrName, statKey)
	if not playerOrName then
		outputDebugString("Missing first parameter: playerOrName [userdata or string]")
		return false
	end

	if type(playerOrName) == "userdata" and getElementType(playerOrName) == "player" then
		playerOrName = getPlayerKey(playerOrName)
	else
		playerOrName = removeColorCoding(playerOrName)
	end

	if not playerOrName then return end

	if not tonumber(statKey) then
		InitializePlayerData(playerOrName)
	else
		PlayerData[playerOrName].Stats[tonumber(statKey)] = nil
	end
	return true
end


--
-- INTERNALS
--

function IncrementPlayerStatInternal(playerOrName, key, amount)
	if (amount or 0) == 0 then return end

	alert("IncrementPlayerStatInternal: Nick=%s; Key=%u; Amount=%.2f", tostring(getPlayerKey(playerOrName) or playerOrName), key, amount)

	local originalValue = GetPlayerStatValueInternal(playerOrName, key) or 0

	alert("IncrementPlayerStatInternal: Original value=%.2f", originalValue)

	local value = originalValue + amount

	return SetPlayerStatValueInternal(playerOrName, key, value)
end


function GetPlayerStatsTableInternal(playerOrName)
	local player, playerName = getPlayerAndName(playerOrName)
	if not playerName then return end

	if PlayerData[playerName] then
		--alert("GetPlayerStatsTableInternal: Nick=%s; Storage=MEMORY", playerName)
		return PlayerData[playerName].Stats
	else
		--alert("GetPlayerStatsTableInternal: Nick=%s; Storage=DB", playerName)
		return LoadPlayerStats(playerName)
	end
	return nil
end


function GetPlayerStatValueInternal(playerOrName, key)
	local player, playerName = getPlayerAndName(playerOrName)
	if not playerName then return end
	if PlayerData[playerName] and PlayerData[playerName].Stats then
		return PlayerData[playerName].Stats[key]
	else
		alert("Loading stats from database for player %s", tostring(playerName))
		local playerStats = LoadPlayerStats(playerName)
		if playerStats then
			alert("...loaded!")
			return playerStats[key]
		end
	end
	return nil
end


function SetPlayerStatValueInternal(playerOrName, key, value)
	local player, playerName = getPlayerAndName(playerOrName)
	if not playerName then return end

	local originalValue = value or 0
	if player then
		if key < 1000 then
			-- check for overflow
			if value > c_MaxStatValue then
				value = c_MaxStatValue
			end
			setPedStat(player, key, value)
		end
	end

	local previousValue = 0
	if PlayerData[playerName] then
		if not PlayerData[playerName].Stats then
			PlayerData[playerName].Stats = {}
		end
		previousValue = PlayerData[playerName].Stats[key] or 0
		PlayerData[playerName].Stats[key] = originalValue
	end

	if not player then
		local stats = {}
		stats[key] = originalValue
		SavePlayerStats(playerName, stats, true)
	else
		triggerEvent("onPlayerStatsUpdate", player or root, playerName, key, value, previousValue)
	end
	return true
end


function BatchApplyPedStats(player, statTable)
	local playerName = getPlayerKey(player)
	if not playerName then return end

	if not PlayerData[playerName] then
		PlayerData[playerName] = {}
	end

	if not PlayerData[playerName].Stats then
		PlayerData[playerName].Stats = {}
	end

	for key,value in pairs(statTable) do
		local originalValue = value or 0
		PlayerData[playerName].Stats[key] = value
		if key < 1000 then
			-- check for overflow
			if value > c_MaxStatValue then
				value = c_MaxStatValue
			end
			setPedStat(player, key, value)
		end
		--setElementData(player, "stats."..key, originalValue, false)
	end
end
