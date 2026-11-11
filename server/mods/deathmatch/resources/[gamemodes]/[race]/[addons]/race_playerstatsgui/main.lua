local STAT_PLAYING_TIME = 1001

-- Copia el stats table con "Tiempo jugado" tomado de time-rp (asi el panel y
-- el scoreboard coinciden). Los invitados no tienen tiempo (0).
local function withPlaytime(targetPlayer, playerStats)
	if not playerStats then
		return nil
	end
	local copy = {}
	for k, v in pairs(playerStats) do
		copy[k] = v
	end
	copy[STAT_PLAYING_TIME] = tonumber(getElementData(targetPlayer, "Time Played Seconds")) or 0
	return copy
end

-- tell the client to show the stats panel
local function displayStatsPanel(player, playerName)
	if Settings["showStatsOnMapFinish"] then
		playerName = playerName or getPlayerName(player)

		-- Pasamos el elemento (no el nick) para que race_playerstats resuelva
		-- la clave correcta (cuenta) cuando playerKeyType = AccountName.
		local playerStats = withPlaytime(player, exports["race_playerstats"]:GetPlayerStatsTable(player))
		if not playerStats then
			alert("Unable to get stats for player "..playerName)
			return
		end

		triggerClientEvent(player, "onClientUpdateStats", resourceRoot, playerName, playerStats)
		-- 'source' is set to resourceRoot to signal automatic panel display
		triggerClientEvent(player, "onClientStatsDisplay", resourceRoot, true)
	end
end

local function hideStatsPanel(player)
	triggerClientEvent(player, "onClientStatsDisplay", resourceRoot, false)
end


-- player joined mid-race?
addEventHandler("onNotifyPlayerReady", root,
	function()
		hideStatsPanel(source)
	end
)

addEvent("onPlayerRaceFinish")
addEventHandler("onPlayerRaceFinish", root,
	function()
		displayStatsPanel(source)
	end
)

-- Al salir de la cuenta, ocultar el panel y limpiar sus datos.
addEventHandler("onPlayerLogout", root,
	function()
		hideStatsPanel(source)
	end
)


function consoleDisplayStats(playerSource, commandName, playerName)
	local targetPlayer = nil
	if playerName then
		targetPlayer = findPlayer(playerName)
	end
	if not targetPlayer then
		targetPlayer = playerSource
	end
	playerName = getPlayerName(targetPlayer)

	-- El nick es solo para mostrar; las stats se resuelven por elemento/cuenta.
	local playerStats = withPlaytime(targetPlayer, exports["race_playerstats"]:GetPlayerStatsTable(targetPlayer))
	if not playerStats then
		alert("Unable to get stats for player "..playerName)
		return
	end

	triggerClientEvent(playerSource, "onClientUpdateStats", playerSource, playerName, playerStats)
	triggerClientEvent(playerSource, "onClientStatsDisplay", playerSource, true)
end
addCommandHandler("stats", consoleDisplayStats, false, false)


-- Top del servidor por experiencia (XP). Incluye pais y estado online.
local function topListCountry(accountName, onlinePlayer)
	if onlinePlayer then
		local ip2c = getResourceFromName("ip2c")
		if ip2c and getResourceState(ip2c) == "running" then
			local code = exports.ip2c:getPlayerCountry(onlinePlayer)
			if type(code) == "string" and code ~= "" then
				return string.lower(code)
			end
		end
	end
	-- Offline: usar el pais guardado en la cuenta al loguear.
	local account = getAccount(accountName)
	if account then
		local stored = getAccountData(account, "race_playerstats.country")
		if type(stored) == "string" then
			return stored
		end
	end
	return ""
end

addEvent("onRequestTopPlayers", true)
addEventHandler("onRequestTopPlayers", root,
	function()
		-- Mapa de cuentas online -> jugador.
		local onlineByAccount = {}
		for _, player in ipairs(getElementsByType("player")) do
			local account = getPlayerAccount(player)
			if account and not isGuestAccount(account) then
				onlineByAccount[getAccountName(account)] = player
			end
		end

		local list = exports["race_playerstats"]:GetPlayerList(2010, "DESC", nil, nil) or {}
		local result = {}
		for _, row in ipairs(list) do
			local nick = tostring(row.nick or "")
			if nick ~= "" then
				local onlinePlayer = onlineByAccount[nick]
				result[#result + 1] = {
					name = nick,
					points = tonumber(row.val) or 0,
					online = onlinePlayer ~= nil,
					country = topListCountry(nick, onlinePlayer),
				}
			end
		end
		triggerClientEvent(source, "onClientTopList", resourceRoot, result)
	end
)
