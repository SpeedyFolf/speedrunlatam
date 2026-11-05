g_StatsReset = false

local currentRacestate = ""
local playersStarted = {}
local playersFinished = {}

local function displayWelcomeMessage(player)
	local welcomeMessage = tostring(Settings["welcomeMessage"] or "")
	if welcomeMessage:len() > 0 then
		chat(welcomeMessage, player)
	end
end

addEvent("onPlayerStatsLoad")
-- loads the stats table from db, and stores it on a table
function handle_PlayerJoin(player)
	player = player or source

	local playerName = getPlayerKey(player)
	if not playerName then
		return
	end
	InitializePlayerData(playerName)

	-- load from db
	PlayerData[playerName].Stats = LoadPlayerStats(player, false) or {}
	BatchApplyPedStats(player, PlayerData[playerName].Stats)
	setElementData(player, "playerId", GetPlayerId(player), false)
	triggerEvent("onPlayerStatsLoad", player, PlayerData[playerName].Stats)
end
addEventHandler("onPlayerJoin", root,
	function()
		if Settings["playerKeyType"] == "PlayerName" then
			handle_PlayerJoin(source)
			displayWelcomeMessage(source)
		end
	end
)

addEventHandler("onPlayerLogin", root,
	function()
		if Settings["playerKeyType"] == "AccountName" then
			handle_PlayerJoin(source)
			displayWelcomeMessage(source)
		end
	end
)

-- store saved stats to db when player leaves
function handle_PlayerQuit(player)
	if (not player) or type(player) == "string" then
		player = source
	end

	local playerName = getPlayerKey(player or source)
	if not playerName then
		alert("PlayerQuit: no key for player %s", tostring(player or source))
		return
	end

	local shouldSave = false
	local ticks = PlayerData[playerName].SessionJoin or 0
	alert("PlayerQuit: Player %s joined at %u", tostring(playerName), ticks)
	if ticks > 0 then
		local seconds = math.floor((getTickCount() - ticks) / 1000)
		alert("PlayerQuit: Player %s played for %u seconds", tostring(playerName), seconds)
		if seconds > Settings["statsGracePeriod"] then
			shouldSave = true
		end
	end

	ticks = PlayerData[playerName].JoinTime or 0
	if ticks > 0 then
		local seconds = math.floor((getTickCount() - ticks) / 1000)
		if seconds > 0 then
			IncrementPlayerStatInternal(playerName, Stat.PLAYING_TIME, seconds)
		end
	end

	if shouldSave then
		SetPlayerStatValue(playerName, Stat.LAST_SEEN, getRealTimeSeconds())

		-- save to db
		SavePlayerStats(playerName, PlayerData[playerName].Stats)

		-- upload to remote server
		ExportPlayerStats(playerName, PlayerData[playerName].Stats)
	end

	PlayerData[playerName] = nil
end
addEventHandler("onPlayerQuit", root, handle_PlayerQuit)

addEventHandler("onPlayerLogout", root,
	function(previousAccount)
		if Settings["playerKeyType"] == "AccountName" then
			handle_PlayerQuit(previousAccount)
			triggerEvent("onPlayerAwardPoints", source, 0, "Logout")
		end
	end
)


function handle_PlayerChangeNick(oldNick, newNick)
	if Settings["playerKeyType"] == "AccountName" then
		return
	end

	if wasEventCancelled() then
		return
	end

	oldNick = removeColorCoding(oldNick)
	newNick = removeColorCoding(newNick)

	if oldNick == newNick then
		return
	end

	if not PlayerData[oldNick] then
		return
	end

	local ticks = PlayerData[oldNick].JoinTime or 0
	if ticks > 0 then
		local seconds = math.floor((getTickCount() - ticks) / 1000)
		if seconds > 0 then
			IncrementPlayerStatInternal(oldNick, Stat.PLAYING_TIME, seconds)
		end
	end

	-- save to db
	SavePlayerStats(oldNick, PlayerData[oldNick].Stats)
	PlayerData[oldNick] = nil

	InitializePlayerData(newNick)

	-- load from db
	PlayerData[newNick].Stats = LoadPlayerStats(newNick) or {}
	BatchApplyPedStats(source, PlayerData[newNick].Stats)
end
addEventHandler("onPlayerChangeNick", root, handle_PlayerChangeNick)


addEventHandler("onResourceStart", resourceRoot,
	function()
		local players = getElementsByType("player")
		for _,player in ipairs(players) do
			handle_PlayerJoin(player)
		end
	end
)


-- tell everyone to save their stats
addEventHandler("onResourceStop", resourceRoot,
	function()
		local players = getElementsByType("player")
		for _,player in ipairs(players) do
			handle_PlayerQuit(player)
		end
	end)


addEvent("onMapStarting", true)
addEventHandler("onMapStarting", root,
	function(mapInfo, mapOptions, gameOptions)
		g_StatsReset = false
		playersStarted = {}
		playersFinished = {}
		local players = getElementsByType("player")
		for _,player in ipairs(players) do
			local key = getPlayerKey(player)
			if key and PlayerData[key] then
				BatchApplyPedStats(player, PlayerData[key].Stats)
			end
		end
	end
)


addEvent("onRaceStateChanging")
addEventHandler("onRaceStateChanging", root,
	function(newState, oldState)
		currentRacestate = newState
		if oldState == "GridCountdown" and newState == "Running" then
			for _,player in ipairs(playersStarted) do
				IncrementPlayerStatInternal(player, Stat.TOTAL_RACES, 1)
			end
			alert("%u players started the race.", #playersStarted)
		end
	end
)


-- player joined mid-race?
addEvent("onNotifyPlayerReady", true)
addEventHandler("onNotifyPlayerReady", root,
	function()
		table.insert(playersStarted, source)
		if Settings["countMidraceJoinAsRacestart"] and (currentRacestate == "Running" or currentRacestate == "MidMapVote") then
			IncrementPlayerStatInternal(source, Stat.TOTAL_RACES, 1)
		end
		local key = getPlayerKey(source)
		if key and PlayerData[key] then
			BatchApplyPedStats(source, PlayerData[key].Stats)
		end
	end
)


-- tell everyone to save their stats when a map ends
addEventHandler("onGamemodeMapStop", root,
	function()
		local players = getElementsByType("player")
		for _,player in ipairs(players) do
			local playerName = getPlayerKey(player)
			if playerName and PlayerData[playerName] then
				local ticks = PlayerData[playerName].JoinTime or 0
				if ticks > 0 then
					local seconds = math.floor((getTickCount() - ticks) / 1000)
					if seconds > 0 then
						IncrementPlayerStatInternal(player, Stat.PLAYING_TIME, seconds)
					end
					PlayerData[playerName].JoinTime = getTickCount()
				end

				--save stats
				SavePlayerStats(player, PlayerData[playerName].Stats)

				-- upload to remote server
				ExportPlayerStats(playerName, PlayerData[playerName].Stats)
			end

		end
	end
)


addEventHandler("onVehicleEnter", root,
	function(player, seat, jacked)
		local vehicleId = getElementModel(source)
		if ModelID.Exempt[vehicleId] then
			return
		end
		--if seat ~= 0 then return end
		if not jacked then
			return
		end
		IncrementPlayerStatInternal(player, Stat.VEHICLES_STOLEN, 1)
	end
)


addEventHandler("onVehicleDamage", root,
	function(damage)
	    local player = getVehicleOccupant(source, 0)
	    -- Check there is a player in the vehicle
	    if player then
	    	IncrementPlayerStatInternal(player, Stat.DAMAGE_TAKEN, math.floor(damage))
	    end
	end
)


addEventHandler("onPlayerDamage", root,
	function(attacker, weapon, bodypart, damage)
		IncrementPlayerStatInternal(source, Stat.DAMAGE_TAKEN, math.floor(damage))
	end
)


-- player is dead, so show stats panel while it waits
addEventHandler("onPlayerWasted", root,
	function(ammo, attacker, weapon, bodypart)
		-- fake death
		if ammo == true then return end

		if not (playersFinished[source] and not Settings["countPostFinishDeath"]) then
			IncrementPlayerStatInternal(source, Stat.TIMES_DIED, 1)
		end

		if isElement(attacker) and getElementType(attacker) == "player" then
			IncrementPlayerStatInternal(attacker, Stat.KILLS, 1)
		end
	end
)


-- this is used to check which vehicle the player was driving when it died
addEvent("onPlayerRaceWasted", true)
addEventHandler("onPlayerRaceWasted", root,
	function(vehicle)
		if not (vehicle and isElement(vehicle)) then return end

		local playerName = getPlayerKey(source)
		if not playerName then return end

		local modelId = getElementModel(vehicle)

		if getElementHealth(vehicle) > Settings["vehicleWreckHealthLimit"] then return end -- wasn't on fire

		local statKey = getDestroyedVehicleStatKey(modelId)
		if statKey ~= nil then
			IncrementPlayerStatInternal(source, statKey, 1)
		end
	end
)

addEvent("onPlayerFinishDD")
addEventHandler("onPlayerFinishDD", root,
	function(rank)
		playersFinished[source] = true
		-- rank 1 triggers onPlayerWinDD
		IncrementPlayerStatInternal(source, Stat.RACES_FINISHED, 1)
		if rank == 2 then
			IncrementPlayerStatInternal(source, Stat.RACES_FINISHED2ND, 1)
		elseif rank == 3 then
			IncrementPlayerStatInternal(source, Stat.RACES_FINISHED3RD, 1)
		end
		triggerEvent("onPlayerRaceFinish", source, rank)
	end
)

addEvent("onPlayerWinDD")
addEventHandler("onPlayerWinDD", root,
	function()
		playersFinished[source] = true
		IncrementPlayerStatInternal(source, Stat.RACES_FINISHED, 1)
		IncrementPlayerStatInternal(source, Stat.RACES_WON, 1)
		triggerEvent("onPlayerRaceWin", source)
		triggerEvent("onPlayerRaceFinish", source, 1)
	end
)

addEvent("onPlayerFinish")
addEventHandler("onPlayerFinish", root,
	function(rank, time)
		playersFinished[source] = true
		IncrementPlayerStatInternal(source, Stat.RACES_FINISHED, 1)
		if rank == 1 then
			IncrementPlayerStatInternal(source, Stat.RACES_WON, 1)
			triggerEvent("onPlayerRaceWin", source)
		elseif rank == 2 then
			IncrementPlayerStatInternal(source, Stat.RACES_FINISHED2ND, 1)
		elseif rank == 3 then
			IncrementPlayerStatInternal(source, Stat.RACES_FINISHED3RD, 1)
		end
		triggerEvent("onPlayerRaceFinish", source, rank, time)
	end
)

addEvent("onPlayerToptimeImprovement")
addEventHandler("onPlayerToptimeImprovement", root,
	function(newPos, newTime, oldPos, oldTime)
		if newPos == 1 then
			IncrementPlayerStatInternal(source, Stat.TOPTIMES_SET, 1)
		end
	end
)



--
-- EVENTS
--

addEvent("onPlayerRaceFinish")
addEvent("onPlayerRaceWin")


-- This event is triggered by the client when it wishes to be sent the stats for a given player.
addEvent("onRequestPlayerStats", true)
addEventHandler("onRequestPlayerStats", root,
	function(playerName)
		if not playerName then
			playerName = getPlayerKey(source)
		else
			local player = findPlayer(playerName)
			if player then
				playerName = getPlayerKey(player)
			else
				if not PlayerData[playerName] then
					PlayerData[playerName] = {
						Stats = LoadPlayerStats(playerName, true)
					}
				end
			end
		end
		if not playerName then return end
		if not PlayerData[playerName] then return end

		if table.count(PlayerData[playerName].Stats) > 0 then
			triggerClientEvent(source, "onClientUpdateStats", source, playerName, PlayerData[playerName].Stats)
		end
	end
)


-- this event is triggered by the client when it sends stats changes
addEvent("onBulkUpdateStats", true)
addEventHandler("onBulkUpdateStats", root,
	function(statsTable)
		-- skip any stats update in case of a stats reset
		-- this flag will be disabled on next map start
		if g_StatsReset then return end
		for stat,amount in pairs(statsTable) do
			IncrementPlayerStatInternal(source, stat, amount)
		end
	end
)


addEvent("onUpdateStat", true)
addEventHandler("onUpdateStat", root,
	function(stat, value)
		IncrementPlayerStatInternal(source, stat, value)
	end
)


addEvent("onRequestPlayerList", true)
addEventHandler("onRequestPlayerList", root,
	function(sortKey, sortOrder, limit, offset, ...)
		local target = source or root
		local list = GetPlayerList(sortKey, sortOrder, limit, offset, ...)
		if list then
			triggerClientEvent(target, "onClientListPlayers", root, list)
		end

	end
)
