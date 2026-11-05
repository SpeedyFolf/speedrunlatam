local debug = false

local playerSpawnIndex = {}
local currentRaceState = "Unknown"
local spawnChoiceEnabled = false

local disableReason = ""
local spawnpoints = {} -- cached ONCE

local function dbg(msg)
	if debug then
		outputDebugString("[SpawnChoice] " .. tostring(msg))
	end
end

local function attr(element, name)
	return getElementData(element, name)
end

---------------------------------------------------
-- META.XML SETTINGS
---------------------------------------------------
local function getMapSetting(settingName)
	local mapmanagerRes = getResourceFromName("mapmanager")
	if mapmanagerRes and getResourceState(mapmanagerRes) == "running" then

		local map = exports.mapmanager:getRunningGamemodeMap()
		if not map then return nil end
		local mapName = getResourceName(map)
		local value = get(mapName .. "." .. settingName)
		if not value then return nil end
		return tostring(value):gsub("%s", "")
	end
end

local function isSettingEnabled(settingName, defaultValue)
	local value = getMapSetting(settingName)
	if value == nil then return defaultValue end
	return value:find("true") ~= nil
end

---------------------------------------------------
-- CACHE SPAWNPOINTS
---------------------------------------------------
local function buildSpawnpoints()
	spawnpoints = {}
	for i, spawnpoint in ipairs(getElementsByType("spawnpoint")) do
		local x = tonumber(attr(spawnpoint, "posX"))
		local y = tonumber(attr(spawnpoint, "posY"))
		local z = tonumber(attr(spawnpoint, "posZ"))

		if x and y and z then
			local rx = tonumber(attr(spawnpoint, "rotX")) or 0
			local ry = tonumber(attr(spawnpoint, "rotY")) or 0
			local rz = tonumber(attr(spawnpoint, "rotZ")) or 0
			local legacyRot = tonumber(attr(spawnpoint, "rotation"))

			if legacyRot then rx, ry, rz = 0, 0, legacyRot end

			spawnpoints[i] = {
				index = i,
				position = { x, y, z },
				rotation = { rx, ry, rz }
			}
		end
	end
end

local function getDisableReason(state)
	if not isSettingEnabled("spawnchoice", true) then
		return "Explicitly disabled in this map's settings."
	end
	if not isSettingEnabled("ghostmode", true) then
		return "Ghostmode is OFF on this map."
	end
	if #spawnpoints <= 1 then
		return "Only 1 spawnpoint available."
	end
	return ""
end

local function getCurrentMapName()
	local mapmanagerRes = getResourceFromName("mapmanager")
	if mapmanagerRes and getResourceState(mapmanagerRes) == "running" then

		local map = exports.mapmanager:getRunningGamemodeMap()
		return map and getResourceName(map) or ""
	end
end

---------------------------------------------------
-- MOVE PLAYER
---------------------------------------------------
local function movePlayerToSpawn(player, index)
	if not spawnChoiceEnabled then return false end
	local vehicle = getPedOccupiedVehicle(player)
	if not vehicle then return false end

	local spawn = spawnpoints[index]
	if not spawn then return false end

	local x, y, z = unpack(spawn.position)
	local rx, ry, rz = unpack(spawn.rotation)

	setElementFrozen(vehicle, true)
	setElementPosition(vehicle, x, y, z)
	setElementRotation(vehicle, rx, ry, rz)
	setElementVelocity(vehicle, 0, 0, 0)
	setElementAngularVelocity(vehicle, 0, 0, 0)
	setCameraTarget(player)

	playerSpawnIndex[player] = index
	dbg("Moved " .. getPlayerName(player) .. " -> " .. index)

	return true
end

local function findPlayerSpawnIndex(player)
	return playerSpawnIndex[player] or 1
end

---------------------------------------------------
-- STATE HANDLERS
---------------------------------------------------
addEventHandler("onRaceStateChanging", root, function(newState, oldState)
	currentRaceState = newState

	if newState == "LoadingMap" or newState == "NoMap" then
		buildSpawnpoints()
		playerSpawnIndex = {}
	end

	---------------------------------------------------
	-- RACE STARTS (COUNTDOWN ENDS)
	---------------------------------------------------
	if oldState == "GridCountdown" and newState == "Running" then
		disableReason = ""
		spawnChoiceEnabled = false

		for _, player in ipairs(getElementsByType("player")) do
			triggerClientEvent(player, "spawnChoice.enable", resourceRoot, false, "", getCurrentMapName())
			triggerClientEvent(player, "spawnChoice.onRaceStarted", resourceRoot)
		end
		return
	end

	---------------------------------------------------
	-- PRE-GRID & GRID COUNTDOWN
	---------------------------------------------------
	disableReason = getDisableReason(newState)

	local shouldEnable =
		(newState == "PreGridCountdown" or newState == "GridCountdown")
		and isSettingEnabled("spawnchoice", true)
		and isSettingEnabled("ghostmode", true)
		and #spawnpoints > 1

	spawnChoiceEnabled = shouldEnable

	for _, player in ipairs(getElementsByType("player")) do
		triggerClientEvent(player, "spawnChoice.enable", resourceRoot, shouldEnable, disableReason, getCurrentMapName())
	end
end)

---------------------------------------------------
-- JOIN & INPUT HANDLERS
---------------------------------------------------
addEvent("spawnChoice.ready", true)
addEventHandler("spawnChoice.ready", resourceRoot, function()
	triggerClientEvent(client, "spawnChoice.enable", resourceRoot, spawnChoiceEnabled, disableReason, getCurrentMapName())
end)

addEvent("spawnChoice.sync", true)
addEventHandler("spawnChoice.sync", root, function()
	if client then
		triggerClientEvent(client, "spawnChoice.enable", resourceRoot, spawnChoiceEnabled, disableReason, getCurrentMapName())
	end
end)

addEvent("spawnChoice.request", true)
addEventHandler("spawnChoice.request", resourceRoot, function(direction)
	local player = client
	if not player or not spawnChoiceEnabled then return end
	if currentRaceState ~= "PreGridCountdown" and currentRaceState ~= "GridCountdown" then return end
	if #spawnpoints <= 1 or type(direction) ~= "number" or direction == 0 then return end

	local currentIndex = findPlayerSpawnIndex(player)
	local nextIndex = currentIndex + direction

	while nextIndex < 1 do nextIndex = nextIndex + #spawnpoints end
	while nextIndex > #spawnpoints do nextIndex = nextIndex - #spawnpoints end

	if movePlayerToSpawn(player, nextIndex) then
		triggerClientEvent(player, "spawnChoice.onIndexChanged", resourceRoot, nextIndex, false)
	end
end)

addEvent("spawnChoice.requestAbsolute", true)
addEventHandler("spawnChoice.requestAbsolute", resourceRoot, function(index, isAutoRestore)
	local player = client
	if not player or not spawnChoiceEnabled then return end
	if currentRaceState ~= "PreGridCountdown" and currentRaceState ~= "GridCountdown" then return end
	if #spawnpoints <= 1 or type(index) ~= "number" or index == 0 then return end

	index = math.floor(index)
	if index < 1 or index > #spawnpoints then return end

	if movePlayerToSpawn(player, index) then
		triggerClientEvent(player, "spawnChoice.onIndexChanged", resourceRoot, index, isAutoRestore or false)
	end
end)

addEvent("spawnChoice.requestClosestCP", true)
addEventHandler("spawnChoice.requestClosestCP", resourceRoot, function()
	local player = client
	if not player or not spawnChoiceEnabled then return end
	if currentRaceState ~= "PreGridCountdown" and currentRaceState ~= "GridCountdown" then return end

	local racepoints = getElementsByType("racepoint")
	if #racepoints == 0 then racepoints = getElementsByType("checkpoint") end

	local cp1 = nil
	for _, cp in ipairs(racepoints) do
		local id = attr(cp, "id") or attr(cp, "number")
		if id == 1 or id == "1" then cp1 = cp break end
	end

	if not cp1 and #racepoints > 0 then cp1 = racepoints[1] end
	if not cp1 then return end

	local cX = tonumber(attr(cp1, "posX") or attr(cp1, "x"))
	local cY = tonumber(attr(cp1, "posY") or attr(cp1, "y"))
	local cZ = tonumber(attr(cp1, "posZ") or attr(cp1, "z"))

	if not cX then cX, cY, cZ = getElementPosition(cp1) end

	local closestIndex = 1
	local minDistance = 9999999.0

	for i, spawn in ipairs(spawnpoints) do
		local sX, sY, sZ = unpack(spawn.position)
		local dist = math.sqrt((sX - cX) ^2 + (sY - cY) ^2 + (sZ - cZ) ^2)
		if dist < minDistance then
			minDistance = dist
			closestIndex = i
		end
	end

	if movePlayerToSpawn(player, closestIndex) then
		triggerClientEvent(player, "spawnChoice.onIndexChanged", resourceRoot, closestIndex, false)
	end
end)

addEventHandler("onPlayerQuit", root, function()
	playerSpawnIndex[source] = nil
end)
