function getMapToptimesInfo(mapName)
	local mapResource = getResourceFromActualName(mapName)
	local raceType = ""
	local mapAuthor = ""
	if (mapResource) then
		raceType = getResourceInfo(mapResource, "racetype") or "???"
		mapAuthor = getResourceInfo(mapResource, "author") or "Unknown"
	end

	local information = {}
	local times = executeSQLQuery("SELECT playerName,time,dateRecorded FROM maptimes WHERE (playerName, time) IN (SELECT playerName, MIN(time) FROM maptimes WHERE mapName = ? GROUP BY playerName) ORDER BY time ASC", mapName)
	if (#times == 0) then
		if (not mapName or mapName == "") then
			times[1] = {}
			times[1]["playerName"] = "-- Select a map --"
			times[1]["time"] = ""
			times[1]["dateRecorded"] = ""
		elseif (raceType ~= "R" and raceType ~= "SR") then
			times[1] = {}
			times[1]["playerName"] = "-- This map does not have leaderboards --"
			times[1]["time"] = ""
			times[1]["dateRecorded"] = ""
		else
			times[1] = {}
			times[1]["playerName"] = "-- Empty --"
			times[1]["time"] = ""
			times[1]["dateRecorded"] = ""
		end
	end
	information["times"] = times
	information["mapAuthor"] = mapAuthor
	information["raceType"] = raceType
	return information
end

function getAllToptimesInfo()
	local SQL = {}

	local maps_table = executeSQLQuery("SELECT DISTINCT mapName FROM maptimes");
	local maps_resources = exports.mapmanager:getMapsCompatibleWithGamemode(getResourceFromName("race"))

	local map_list = {}
	for _, map in ipairs(maps_resources) do
		local mapName = getResourceInfo(map, "name") or getResourceName(map)
		local raceType = getResourceInfo(maps_resources[1], "racetype") or "???"
		if (raceType == "R" or raceType == "SR" or raceType == "???" or tableContains(maps_table, mapName)) then
			map_list[#map_list+1] = mapName
		end
	end
	map_list[#map_list+1] = #maps_resources
	return map_list
end

function getResourceFromActualName(comparison)
	local maps_resources = exports.mapmanager:getMapsCompatibleWithGamemode(getResourceFromName("race"))
	for _, map in ipairs(maps_resources) do
		local mapName = getResourceInfo(map, "name") or getResourceName(map)
		if (mapName == comparison) then
			return map
		end
	end
	return false
end

function tableContains(table, value)
	for _, v in ipairs(table) do
		if (v == value) then
			return true
		end
	end
	return false
end
