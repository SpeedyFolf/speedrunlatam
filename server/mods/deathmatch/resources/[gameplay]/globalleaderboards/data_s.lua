MAX_DURATION = 86400
DEFAULT_DURATION = tonumber(get("race.duration")) or 1800

addEvent("requestMainData", true)
addEventHandler("requestMainData", root, function()
	local results = executeSQLQuery(QUERY_SELECT_MAIN)
	triggerClientEvent(client, "sendMainDataToClient", resourceRoot, results)
end)

addEvent("requestMapsData", true)
addEventHandler("requestMapsData", root, function()
	local results = executeSQLQuery(QUERY_SELECT_MAPLIST, getPlayerName(source))
	triggerClientEvent(client, "sendMapsDataToClient", resourceRoot, results)
end)

addEvent("requestPlayerDataFromServer", true)
addEventHandler("requestPlayerDataFromServer", root, function(playerName)
	local results = executeSQLQuery(QUERY_SELECT_PLAYER, playerName)
	triggerClientEvent(client, "sendPlayerDataToClient", resourceRoot, playerName, results)
end)

addEvent("requestMapDataFromServer", true)
addEventHandler("requestMapDataFromServer", root, function(mapName)
	local results = executeSQLQuery(QUERY_SELECT_MAP, mapName)
	triggerClientEvent(client, "sendMapDataToClient", resourceRoot, mapName, results)
end)

-- -----------------
-- -----------------
-- RESOURCE START --
-- -----------------
-- -----------------
addEventHandler("onResourceStart", resourceRoot, function()
	debugDump("Tables generating for the first time. This can take a few seconds...")
	local t = getTickCount()
	-- maps
	executeSQLQuery(QUERY_MAPS_DROP)
	executeSQLQuery(QUERY_MAPS_CREATE)
	executeSQLQuery(QUERY_MAPS_POPULATE)
	executeSQLQuery(QUERY_MAPS_INDEX)
	-- players
	executeSQLQuery(QUERY_PLAYERS_DROP)
	executeSQLQuery(QUERY_PLAYERS_CREATE)
	executeSQLQuery(QUERY_PLAYERS_POPULATE)
	executeSQLQuery(QUERY_PLAYERS_INDEX)
	-- rankings
	executeSQLQuery(QUERY_RANKINGS_DROP)
	executeSQLQuery(QUERY_RANKINGS_CREATE)
	debugDump("Generating huge table... ms "..getTickCount() - t)
	executeSQLQuery(QUERY_RANKINGS_POPULATE)
	debugDump("Finished creating huge table. Still working... ms "..getTickCount() - t)
	executeSQLQuery(QUERY_RANKINGS_INDEX_M)
	executeSQLQuery(QUERY_RANKINGS_INDEX_P)
	executeSQLQuery(QUERY_RANKINGS_INDEX_MP)
	executeSQLQuery(QUERY_RANKINGS_INDEX_MT)
	executeSQLQuery(QUERY_RANKINGS_INDEX_PT)
	-- more
	executeSQLQuery(QUERY_MAPS_UPDATE_RECORD_STATS)
	getMapList()
	executeSQLQuery(QUERY_MAPS_HANDLE_GONERS)
	executeSQLQuery(QUERY_RANKINGS_VALIDATE)
	debugDump("Working a second big table... ms "..getTickCount() - t)
	executeSQLQuery(QUERY_PLAYERS_UPDATE_STATS)
	debugDump("second big table done. Wrapping up... ms "..getTickCount() - t)
	executeSQLQuery(QUERY_WORST_PLAYER_INSERT)
	executeSQLQuery(QUERY_WORST_PLAYER_RANK)
	executeSQLQuery(QUERY_WORST_PLAYER_STATS)
	executeSQLQuery(QUERY_BEST_PLAYER_INSERT)
	executeSQLQuery(QUERY_BEST_PLAYER_RANK)
	executeSQLQuery(QUERY_BEST_PLAYER_STATS)
	debugDump("Finished! In ms "..getTickCount() - t)
	if true then return end
end)

-- Read all the resources present on the server
-- Then read all the maps with times in the database
-- The two are compared against one another to filter out removed maps, renamed maps, etc
function getMapList()
	local res = getResources()
	for _, r in ipairs(res) do
		processMap(r)
	end
end

function processMap(r)
	if (getResourceInfo(r, "type") ~= "map") then
		return
	end
	if (getResourceInfo(r, "gamemodes") ~= "race") then
		return
	end
	local fileName = getResourceName(r)
	local faceName = getResourceInfo(r, "name") or fileName
	local timeLimit = getMapDuration(fileName)
	local blacklisted = BLACKLISTED_MAP_FILES[fileName] or false
	executeSQLQuery(QUERY_MAPS_INSERT, faceName, fileName, timeLimit, blacklisted)
end

-- -------------
-- -------------
-- -- UTILITY --
-- -------------
-- -------------

function getMapDuration(fileName)
	local duration = tonumber(get(fileName..".duration")) or DEFAULT_DURATION
	duration = math.min(duration, MAX_DURATION)
	duration = duration * 1000
	if not (duration > 0) then
		duration = DEFAULT_DURATION
	end
	return duration
end

function getMapFileFromName(name)
	cmd = "SELECT resName FROM race_mapmanager_maps WHERE infoName = ?"
	local results = executeSQLQuery(cmd, name)
	if results and #results > 0 then
		return tostring(results[1].resName)
	else
		return false
	end
end

function debugDump(str)
	outputServerLog("[Global Leaderboards] "..str)
	iprint("[Global Leaderboards] "..str)
end
