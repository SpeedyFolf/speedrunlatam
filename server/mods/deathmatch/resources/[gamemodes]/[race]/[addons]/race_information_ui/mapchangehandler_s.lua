g_mapInfo = {}
g_raceGamemode = getResourceRootElement(getResourceFromName("race"))
g_mapManager = getResourceFromName("mapmanager")
g_mapResource = nil

function mapInfoChanged(theKey, oldValue, newValue)
	if (theKey ~= "info") then return end
	if not newValue or type(newValue) ~= "table" or not newValue.mapInfo then return end

	if g_mapManager then
		g_mapResource = exports.mapmanager:getRunningGamemodeMap()
	end

	local resourceName = newValue.mapInfo.resname or "<none>"

	-- Fetch the organizational path dynamically on map change
	local resourcePath = newValue.mapInfo.respath
	if (not resourcePath or resourcePath == "") and g_mapResource then
		resourcePath = getResourceOrganizationalPath(g_mapResource)
	end
	if not resourcePath or resourcePath == "" then
		resourcePath = "<none>"
	end

	local raceData = getRaceGamemodeSettings()

	local gm = getBool(resourceName .. ".ghostmode")
	local vw = getBool(resourceName .. ".vehicleweapons")
	local hm = getBool(resourceName .. ".hunterminigun")
	local rs = getString(resourceName .. ".respawn")
	if gm == nil then gm = raceData.ghostmode end
	if vw == nil then vw = raceData.vehicleweapons end
	if hm == nil then hm = raceData.hunterminigun end
	if rs == nil then rs = raceData.respawnmode end

	local racetype = "???"
	if resourceName and resourceName ~= "<none>" then
		racetype = getResourceInfo(g_mapResource, "racetype")
	end

	local mapInfo = newValue.mapInfo or {}
	local mapOptions = newValue.mapOptions or {}

	g_mapInfo = {
		resname = resourceName,
		respath = resourcePath,
		name = mapInfo.name,
		author = mapInfo.author,
		racetype = racetype,
		description = getResourceInfo(g_mapResource, "description"),

		numSpawnpoints = mapInfo.numSpawnpoints or 0,
		numCheckpoints = mapInfo.numCheckpoints or 0,
		numObjects = mapInfo.numObjects or 0,
		numRemovedObjects = mapInfo.numRemovedObjects or 0,
		numPickups = mapInfo.numPickups or 0,
		numRegularPickups = mapInfo.numRegularPickups or 0,
		allowonfoot = mapOptions.allowonfoot,
		fastsprint = isGlitchEnabled("fastsprint"),

		ghostmode = ternary(raceData.ghostmode_map_can_override, gm, raceData.ghostmode),
		vehicleweapons = ternary(raceData.vehicleweapons_map_can_override, vw, raceData.vehicleweapons),
		hunterminigun = ternary(raceData.hunterminigun_map_can_override, hm, raceData.hunterminigun),
		respawn = rs,
		respawntime = mapOptions.respawntime or raceData.respawntime,
	}

	triggerClientEvent(root, "onMapChangedC", resourceRoot, g_mapInfo)
end
addEventHandler("onElementDataChange", g_raceGamemode, mapInfoChanged)

addEventHandler("onResourceStart", resourceRoot,
	function ()
		local mapmanager = getResourceFromName("mapmanager")
		local fetchedData = getElementData(getResourceRootElement(getResourceFromName("race")), "info" )
		local raceData = getRaceGamemodeSettings()

		if not fetchedData or type(fetchedData) ~= "table" then
			fetchedData = {}
		end

		local mapInfo = fetchedData.mapInfo or {}
		local mapOptions = fetchedData.mapOptions or {}

		if mapmanager then
			local mapResource = exports.mapmanager:getRunningGamemodeMap()
			if mapResource then
				local mapFile = getResourceName(mapResource)
				local mapPath = getResourceOrganizationalPath(mapResource)
				local gm = getBool(mapFile .. ".ghostmode")
				local vw = getBool(mapFile .. ".vehicleweapons")
				local hm = getBool(mapFile .. ".hunterminigun")
				local rs = getString(mapFile .. ".respawn")
				if gm == nil then gm = raceData.ghostmode end
				if vw == nil then vw = raceData.vehicleweapons end
				if hm == nil then hm = raceData.hunterminigun end
				if rs == nil then rs = raceData.respawnmode end

				g_mapInfo = {
					resname = mapFile,
					respath = mapPath,
					name = getResourceInfo(mapResource, "name"),
					author = getResourceInfo(mapResource, "author"),
					racetype = getResourceInfo(mapResource, "racetype") or getString(mapFile .. ".racetype") or "???",
					description = getResourceInfo(mapResource, "description"),

					numSpawnpoints = mapInfo.numSpawnpoints or 0,
					numCheckpoints = mapInfo.numCheckpoints or 0,
					numObjects = mapInfo.numObjects or 0,
					numRemovedObjects = mapInfo.numRemovedObjects or 0,
					numPickups = mapInfo.numPickups or 0,
					numRegularPickups = mapInfo.numRegularPickups or 0,
					allowonfoot = mapOptions.allowonfoot,
					fastsprint = isGlitchEnabled("fastsprint"),

					ghostmode = ternary(raceData.ghostmode_map_can_override, gm, raceData.ghostmode),
					vehicleweapons = ternary(raceData.vehicleweapons_map_can_override, vw, raceData.vehicleweapons),
					hunterminigun = ternary(raceData.hunterminigun_map_can_override, hm, raceData.hunterminigun),
					respawn = rs,
					respawntime = mapOptions.respawntime or raceData.respawntime,
				}
			end
		end
	end
)

function getRaceGamemodeSettings()
	return {
		ghostmode = getBool("race.ghostmode"),
		ghostmode_map_can_override = getBool("race.ghostmode_map_can_override"),
		vehicleweapons = getBool("race.vehicleweapons"),
		vehicleweapons_map_can_override = getBool("race.vehicleweapons_map_can_override"),
		hunterminigun = getBool("race.hunterminigun"),
		hunterminigun_map_can_override = getBool("race.hunterminigun_map_can_override"),
		respawnmode = getString("race.respawnmode"),
		respawntime = getNumber("race.respawntime"),
	}
end

addEvent("onClientWantMapData", true)
addEventHandler("onClientWantMapData", root,
	function()
		triggerClientEvent(source, "onMapChangedC", resourceRoot, g_mapInfo)
	end
)
