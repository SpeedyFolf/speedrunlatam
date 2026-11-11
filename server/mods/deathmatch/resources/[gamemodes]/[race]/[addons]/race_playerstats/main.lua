g_StatsReset = false

local currentRacestate = ""
local playersStarted = {}
local playersFinished = {}
local finishRanks = {}
local beatWR = {}
local pointsAwarded = false

-- Sincroniza la experiencia al element data "XP" para la columna del scoreboard.
local function syncExperienceElementData(player)
	if not (isElement(player) and getElementType(player) == "player") then
		return
	end
	local xp = GetPlayerStatValueInternal(player, Stat.EXPERIENCE_POINTS) or 0
	setElementData(player, "XP", xp, true)
end

local function displayWelcomeMessage(player)
	local welcomeMessage = tostring(Settings["welcomeMessage"] or "")
	if welcomeMessage:len() > 0 then
		chat(welcomeMessage, player)
	end
end

-- Guarda el pais en la cuenta (para mostrarlo en el top aunque el jugador
-- este offline). Se actualiza al loguear.
local function syncCountryAccountData(player)
	local account = getPlayerAccount(player)
	if not account or isGuestAccount(account) then
		return
	end
	local ip2c = getResourceFromName("ip2c")
	if ip2c and getResourceState(ip2c) == "running" then
		local code = exports.ip2c:getPlayerCountry(player)
		if type(code) == "string" and code ~= "" then
			setAccountData(account, "race_playerstats.country", string.lower(code))
		end
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
	syncExperienceElementData(player)
	syncCountryAccountData(player)
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
			-- Quita la columna XP del scoreboard al salir de la cuenta.
			setElementData(source, "XP", nil, true)
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


-- Agrega la columna "XP" al scoreboard (si esta corriendo) y lo re-agrega
-- cuando el scoreboard se reinicia.
local function ensureExperienceScoreboardColumn()
	local scoreboard = getResourceFromName("scoreboard")
	if scoreboard and getResourceState(scoreboard) == "running" then
		exports.scoreboard:addScoreboardColumn("XP")
	end
end

addEventHandler("onResourceStart", resourceRoot,
	function()
		ensureExperienceScoreboardColumn()
		local players = getElementsByType("player")
		for _,player in ipairs(players) do
			handle_PlayerJoin(player)
		end
	end
)

addEventHandler("onResourceStart", root,
	function(resource)
		if getResourceName(resource) == "scoreboard" then
			ensureExperienceScoreboardColumn()
		end
	end
)

-- Mantiene sincronizado el element data "XP" cuando cambia la experiencia.
addEventHandler("onPlayerStatsUpdate", root,
	function(playerName, key, value, previousValue)
		if key == Stat.EXPERIENCE_POINTS and isElement(source) and getElementType(source) == "player" then
			setElementData(source, "XP", value or 0, true)
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
		finishRanks = {}
		beatWR = {}
		pointsAwarded = false
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


-- Otorga experiencia a los finishers del podio cuando termina el mapa.
-- Elegibilidad: al menos 'minPlayers' participantes (aunque alguno no termine).
-- Bono: segun cuantos TERMINARON.
local function awardExperiencePoints()
	if pointsAwarded then return end
	pointsAwarded = true

	-- Participantes reales: los que estuvieron listos para largar (deduplicado).
	local participantCount = 0
	local seen = {}
	for _, player in ipairs(playersStarted) do
		if isElement(player) and not seen[player] then
			seen[player] = true
			participantCount = participantCount + 1
		end
	end

	-- Contamos a todos los que terminaron (aunque se hayan desconectado)
	-- para el tamano del campo, pero solo premiamos a los conectados.
	local finisherCount = 0
	local awardable = {}
	for player, rank in pairs(finishRanks) do
		finisherCount = finisherCount + 1
		if isElement(player) and getElementType(player) == "player" then
			awardable[#awardable + 1] = { player = player, rank = rank }
		end
	end

	-- Anti-farm: si corrio solo (menos de 2 participantes), no hay puntos.
	if participantCount < PointsConfig.minPlayers then
		alert("Experience: %u participante(s), minimo %u. Sin puntos.", participantCount, PointsConfig.minPlayers)
		return
	end

	local bonus = getFinisherBonus(finisherCount)
	for _, entry in ipairs(awardable) do
		local base = PointsConfig.basePoints[entry.rank]
		if base then
			local wrBonus = beatWR[entry.player] and PointsConfig.wrBonus or 0
			local points = base + bonus + wrBonus
			local playerKey = getPlayerKey(entry.player)
			local loggedIn = playerKey ~= nil
			alert("Experience: %s rank=%u participants=%u finishers=%u bonus=%u wr=%u -> +%u (cuenta=%s)", tostring(playerKey), entry.rank, participantCount, finisherCount, bonus, wrBonus, points, tostring(loggedIn))
			if not isElement(entry.player) then
				-- jugador desconectado, no hay a quien avisar
			elseif loggedIn then
				IncrementPlayerStatInternal(entry.player, Stat.EXPERIENCE_POINTS, points)
				local wrText = wrBonus > 0 and string.format(" (+%u WR)", wrBonus) or ""
				outputChatBox(string.format("#33FF66[Puntos] #FFFFFFGanaste %u de experiencia por terminar %uº%s.", points, entry.rank, wrText), entry.player, 255, 255, 255, true)
			else
				-- Invitado: no se guarda, solo se avisa.
				outputChatBox(string.format("#FFB154[Puntos] #FFFFFFTerminaste %uº y ganaste %u puntos, pero no tienes sesión iniciada: no se guardarán.", entry.rank, points), entry.player, 255, 255, 255, true)
			end
		end
	end
end


-- tell everyone to save their stats when a map ends
addEventHandler("onGamemodeMapStop", root,
	function()
		awardExperiencePoints()

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
	    -- getVehicleOccupant puede devolver un ped (NPC de trafico), no solo players.
	    if player and getElementType(player) == "player" then
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
		finishRanks[source] = rank
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
		finishRanks[source] = 1
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
		finishRanks[source] = rank
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
			-- Nuevo #1 del mapa (WR): bono de XP al final del mapa.
			beatWR[source] = true
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
		local targetPlayer = source
		if not playerName then
			playerName = getPlayerKey(source)
		else
			local player = findPlayer(playerName)
			if player then
				playerName = getPlayerKey(player)
				targetPlayer = player
			else
				targetPlayer = nil
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
			-- Mostramos el nick, aunque la clave interna sea la cuenta.
			local displayName = isElement(targetPlayer) and getPlayerName(targetPlayer) or playerName
			triggerClientEvent(source, "onClientUpdateStats", source, displayName, PlayerData[playerName].Stats)
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
