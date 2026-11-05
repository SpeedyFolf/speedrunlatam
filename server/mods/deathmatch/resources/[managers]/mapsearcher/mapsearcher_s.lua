-- Starts a next map vote with selected map
addEvent("mapsearcher_votemap", true)
addEventHandler("mapsearcher_votemap", root, function(resname)
	if not resname then return end
	executeCommandHandler("votemap", source, resname)
end )

addEvent("mapsearcher_getmaps", true)
addEventHandler("mapsearcher_getmaps", root, function()
	local tableOut = {}

	-- Gets mapmanager
	local mapmanager = getResourceFromName("mapmanager")
	if mapmanager and (getResourceState(mapmanager) ~= "running") then return end

	-- Scans through all gamemodes on the server
	local gamemodes = call(mapmanager, "getGamemodes")

	for id, gamemode in ipairs(gamemodes) do
		-- Only use "Race" gamemode
		if (getResourceInfo(gamemode, "name") or getResourceName(gamemode)) == "Race" then
			local maps = call(mapmanager, "getMapsCompatibleWithGamemode" , gamemode)
			-- Adds all of the maps on the server for Race gamemode
			for _, map in ipairs(maps) do
				-- Get mapratings
				local rate = tryExportedFunctionCall("mapratings", "getMapRating", getResourceName(map))
				if type(rate) == "table" then rate = string.format("%.1f", rate.average) else rate = "N/A" end

				-- Get times played
				local times = tryExportedFunctionCall("mapratings", "getMapTimesPlayed", getResourceName(map))
				if type(times) == "table" then times = times.playCount else times = "N/A" end

				table.insert(tableOut, {
					name = getResourceInfo(map, "name") or getResourceName(map),
					resname = getResourceName(map),
					racetype = getResourceInfo(map, "racetype") or "???",
					author = getResourceInfo(map, "author") or "Unknown",
					rating = rate,
					lastplayed = tryExportedFunctionCall("mapratings", "getMapLastTimePlayed", getResourceName(map)) or "Unknown",
					timesplayed = times or 0
				})
			end
		end
	end

	triggerClientEvent(source, "mapsearcher_getmaps_c", source, tableOut)
end )

function tryExportedFunctionCall(resName, funcName, param)
	local res = getResourceFromName(resName)
	local functions = getResourceExportedFunctions(res)
	for _, f in ipairs(functions) do
		if f == funcName then
			return call(res, funcName, param)
		end
	end
	return false
end
