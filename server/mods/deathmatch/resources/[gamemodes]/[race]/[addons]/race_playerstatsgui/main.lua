-- tell the client to show the stats panel
local function displayStatsPanel(player, playerName)
	if Settings["showStatsOnMapFinish"] then
		playerName = playerName or getPlayerName(player)

		local playerStats = exports["race_playerstats"]:GetPlayerStatsTable(playerName)
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


function consoleDisplayStats(playerSource, commandName, playerName)
	local targetPlayer = nil
	if playerName then
		targetPlayer = findPlayer(playerName)
	end
	if not targetPlayer then
		targetPlayer = playerSource
	end
	playerName = getPlayerName(targetPlayer)

	local playerStats = exports["race_playerstats"]:GetPlayerStatsTable(playerName)
	if not playerStats then
		alert("Unable to get stats for player "..playerName)
		return
	end

	triggerClientEvent(playerSource, "onClientUpdateStats", playerSource, playerName, playerStats)
	triggerClientEvent(playerSource, "onClientStatsDisplay", playerSource, true)
end
addCommandHandler("stats", consoleDisplayStats, false, false)
