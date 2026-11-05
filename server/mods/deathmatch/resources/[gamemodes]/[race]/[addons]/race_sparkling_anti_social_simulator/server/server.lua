local MAP_DATA = {
	GHOST_MODE = false,
	GHOST_ALPHA = 255,
}

local GHOST_MODE = {
	ENABLED = false,
	ALPHA = 255,
}

function onResourceStart()
	setTimer(onMapStarting, 1000, 1)
end
addEventHandler("onResourceStart", resourceRoot, onResourceStart)

function getCorrectMapData()
	local ghostmode = get("*race.ghostmode")
	ghostmode = ghostmode == "true" or ghostmode == true

	local ghostmode_override = get("*race.ghostmode_map_can_override")
	ghostmode_override = ghostmode_override == "true" or ghostmode_override == true

	local map_ghostmode = nil

	local mapmanager = getResourceFromName("mapmanager")
	if mapmanager then
		local mapResource = getResourceName(call(getResourceFromName("mapmanager"), "getRunningGamemodeMap"))
		if mapResource then
			map_ghostmode = get(mapResource .. ".ghostmode")
		end
	end

	if (map_ghostmode == nil) then
		map_ghostmode = ghostmode
	end

	map_ghostmode = map_ghostmode == "true" or map_ghostmode == true

	return ghostmode, ghostmode_override, map_ghostmode
end

function onMapStarting()
	local ghostmode, ghostmode_override, map_ghostmode = getCorrectMapData()

	GHOST_MODE.ENABLED = (ghostmode_override and map_ghostmode) or (not ghostmode_override and ghostmode)

	GHOST_MODE.ALPHA = tonumber(get("*race.ghostalphalevel")) or 255

	triggerClientEvent(getElementsByType("player"), "sendGhostModeData", resourceRoot, GHOST_MODE)
end
addEventHandler("onMapStarting", root, onMapStarting)

function onPlayerLogin()
	triggerClientEvent(source, "sendGhostModeData", source, GHOST_MODE, true)
end
addEventHandler("onPlayerLogin", resourceRoot, onPlayerLogin)

function onPlayerJoin()
	triggerClientEvent(source, "sendGhostModeData", source, GHOST_MODE)
end
addEventHandler("onPlayerJoin", resourceRoot, onPlayerJoin)
