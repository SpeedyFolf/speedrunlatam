
-- This sucks
StatMergeExclude = Set(
	Stat.LAST_SEEN,
	Stat.FAT,
	Stat.STAMINA,
	Stat.BODY_MUSCLE,
	Stat.MAX_HEALTH,
	Stat.MAX_STREAKS,
	3001,
	3002
)

--
-- COMMANDS
--

function consoleDeleteStat(playerSource, commandName, statKey)
	if not statKey then
		chat("Syntax: /%s <stat key>", playerSource, commandName)
		return
	end
	local result = DeleteStats(statKey)
	if result then
		for _,player in ipairs(getElementsByType("player")) do
			ClearPlayerStats(getPlayerKey(player), tonumber(statKey))
		end
		local message = "Stats for key "..statKey.." were deleted by "..getPlayerKey(playerSource)
		chat(message)
	else
		local message = "Could not delete stat for key " .. statKey
		alert(message)
		chat(message, playerSource)
	end
end
addCommandHandler("stats_reset_key", consoleDeleteStat, true, false)


function consoleDeletePlayerStats(playerSource, commandName, playerName)
	if not playerName then
		chat("Syntax: /%s <player name>", playerSource, commandName)
		return
	end
	local result = DeletePlayerStats(playerName)
	if result then
		ClearPlayerStats(playerName)
		local message = "Stats for player "..playerName.." were deleted by "..getPlayerKey(playerSource)
		--alert(message)
		chat(message)
	else
		local message = "Could not delete stats for player " .. playerName
		alert(message)
		chat(message, playerSource)
	end
end
addCommandHandler("stats_reset_player", consoleDeletePlayerStats, true, false)


function consoleResetStats(playerSource, commandName)
	local result = DeleteAllStats()
	if result then
		-- signal a stats reset
		g_StatsReset = true

		for _,player in ipairs(getElementsByType("player")) do
			ClearPlayerStats(getPlayerKey(player))
		end
		local message = "Stats have been reset by "..getPlayerKey(playerSource)
		chat(message)
	else
		local message = "Could not reset stats"
		alert(message)
		chat(message, playerSource)
	end
end
addCommandHandler("stats_reset_all", consoleResetStats, true, false)


function consoleMergeStats(playerSource, commandName, sourcePlayerName, targetPlayerName)
	if not (sourcePlayerName and targetPlayerName) then
		chat("Syntax: /%s <source player name> <target player name>", playerSource, commandName)
		return
	end

	local sourceStats = LoadPlayerStats(sourcePlayerName, true);
	if table.count(sourceStats) == 0 then
		chat("Stats of source player %s not found", playerSource, sourcePlayerName)
		return
	end

	local targetStats = LoadPlayerStats(targetPlayerName, true);
	if table.count(targetStats) == 0 then
		chat("Stats of target player %s not found", playerSource, targetPlayerName)
		return
	end

	for k,v in pairs(sourceStats) do
		local targetValue = targetStats[k] or 0
		if not StatMergeExclude[k] then
			targetValue = targetValue + (tonumber(v) or 0)
		else
			targetValue = math.max(targetValue, tonumber(v) or 0)
		end
		targetStats[k] = targetValue
		alert("Incremented target stat %u by %.2f. New value = %.2f", k, v, targetValue)
	end

	local targetPlayer = getPlayerFromKey(targetPlayerName)
	if targetPlayer then
		alert("Target player %s online, applying stats...", targetPlayerName)
		BatchApplyPedStats(targetPlayer, targetStats)
		--PlayerData[targetPlayerName].Stats = targetStats
	end
	chat("Saving new stats for player %s...", playerSource, targetPlayerName)
	SavePlayerStats(targetPlayerName, targetStats)
end
addCommandHandler("stats_merge", consoleMergeStats, true, false)


function consoleRenamePlayer(playerSource, commandName, oldPlayerName, newPlayerName)
	if not (oldPlayerName and newPlayerName) then
		chat("Syntax: /%s <current player name> <new player name>", playerSource, commandName)
		return
	end

	local oldId = GetPlayerId(oldPlayerName)
	if newId == 0 then
		chat("Player '%s' does not exist", playerSource, oldPlayerName)
		return
	end

	local newId = GetPlayerId(newPlayerName)
	if newId > 0 then
		alert("Deleting target player name '%s'...", newPlayerName)
		DeletePlayer(newPlayerName)
		PlayerData[newPlayerName] = nil
	end

	local ret = RenamePlayer(oldPlayerName, newPlayerName)
	if ret then
		chat("Player '%s' renamed to '%s'", playerSource, oldPlayerName, newPlayerName)
		if PlayerData[oldPlayerName] then
			PlayerData[newPlayerName] = PlayerData[oldPlayerName]
			PlayerData[oldPlayerName] = nil
		end
	else
		chat("Could not rename player '%s' to '%s'", playerSource, oldPlayerName, newPlayerName)
	end
end
addCommandHandler("stats_rename_player", consoleRenamePlayer, false, false)



function consoleStatsDump(playerSource, commandName, playerName)
	if not playerName then
		chat("Syntax: /%s <playername>", playerSource, commandName)
		return
	end

	local sourceStats = LoadPlayerStats(playerName, true);
	if table.count(sourceStats) == 0 then
		alert("Stats of player %s not found", playerName)
		return
	end

	console("Stats for player %s:", playerSource, playerName)
	for k,v in pairs(sourceStats) do
		local targetValue = sourceStats[k]
		local statName = string.format("[%u]", k)
		if StatLabel[k] then
			statName = statName .. " " .. StatLabel[k]
		end
		console("%s = %s", playerSource, statName, tostring(targetValue))
	end
end
addCommandHandler("stats_dump_player", consoleStatsDump, false, false)


function consoleClearUnusedStats(playerSource, commandName)
	local players = GetPlayerList()
	alert("Processing %u players...", #players)
	local deleted = {}
	for _,player in ipairs(players) do
		local playerId = tonumber(player["rowid"])
		local playerName = tostring(player["nick"])
		local playerStats = LoadPlayerStats(playerName)
		if table.count(playerStats) > 0 then
			local points = playerStats[2010]
			if not points then
				deleted[#deleted + 1] = playerName
				alert("Player %s has no points", playerName)
			end
		else
			deleted[#deleted + 1] = playerName
			alert("Player %s doesn't have point stats", playerName)
		end
	end
	if #deleted > 0 then
		local count = 0
		for _, playerName in ipairs(deleted) do
			if DeletePlayer(playerName) then
				count = count + 1
			end
		end
		alert("Deleted %u players from database", count)
	else
		alert("No players meet the deletion criteria")
	end
end
addCommandHandler("stats_cleanup", consoleClearUnusedStats, true, false)


function ExportPlayerStats_Callback(result)
	alert("ExportPlayerStats: Export server acknowledged "..tostring(result));
end

function ExportPlayerStats(playerName, statsTable)
	if not Settings["statsExportUrl"] or string.len(Settings["statsExportUrl"]) == 0 then
		alert("ExportPlayerStats: StatsExportUrl is not set")
		return false
	end

	local playerId = GetPlayerId(playerName)
	if playerId == 0 then
		alert("ExportPlayerStats: Player %s not found", playerName)
		return false
	end

	if type(playerName) ~= "string" then
		playerName = getPlayerKey(playerName)
	else
		playerName = removeColorCoding(playerName)
	end

	if not statsTable then
		alert("ExportPlayerStats: Loading stats for player %s", playerName)
		statsTable = LoadPlayerStats(playerName)
	end

	if not statsTable or (table.count(statsTable) == 0) then
		alert("ExportPlayerStats: Nothing to export")
		return false
	end

	local payload = {
		playerId = playerId,
		playerName = playerName,
		stats = statsTable
	}

	if Settings["serverKey"] and type(Settings["serverKey"]) == "string" and Settings["serverKey"] ~= '' then
		payload["key"] = Settings["serverKey"]
	end

	alert("ExportPlayerStats: Sending stats...")
	return callRemote(Settings["statsExportUrl"], ExportPlayerStats_Callback, payload)
end


function consoleExportPlayerStats(playerSource, commandName, playerName)
	local statsTable = LoadPlayerStats(playerName)
	ExportPlayerStats(playerName, statsTable)
end
addCommandHandler("stats_export", consoleExportPlayerStats)
