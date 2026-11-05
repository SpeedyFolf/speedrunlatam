local enabled = false
local disableReason = nil
local lastShownReason = nil

local switchCooldown = 100 -- Milliseconds
local lastSwitchTick = 0

local currentMapName = ""
local hasRestoredForThisMap = false
local hasShownEnabledNotice = false
local hasShownDisabledNotice = false
local currentSpawnIndex = nil

---------------------------------------------------
-- LOCAL XML STORAGE
---------------------------------------------------
local function saveLocalSpawnIndex(mapName, index)
	if not mapName or mapName == "" then return end
	local xml = xmlLoadFile("spawns.xml") or xmlCreateFile("spawns.xml", "spawns")
	if xml then
		local child = nil
		for _, n in ipairs(xmlNodeGetChildren(xml)) do
			if xmlNodeGetAttribute(n, "map") == mapName then
				child = n
				break
			end
		end
		if not child then
			child = xmlCreateChild(xml, "spawn")
			xmlNodeSetAttribute(child, "map", mapName)
		end
		xmlNodeSetAttribute(child, "index", tostring(index))
		xmlSaveFile(xml)
		xmlUnloadFile(xml)
	end
end

local function loadLocalSpawnIndex(mapName)
	if not mapName or mapName == "" then return nil end
	local xml = xmlLoadFile("spawns.xml")
	if xml then
		for _, n in ipairs(xmlNodeGetChildren(xml)) do
			if xmlNodeGetAttribute(n, "map") == mapName then
				local idx = tonumber(xmlNodeGetAttribute(n, "index"))
				xmlUnloadFile(xml)
				return idx
			end
		end
		xmlUnloadFile(xml)
	end
	return nil
end

---------------------------------------------------
-- ENABLE / DISABLE & CHAT NOTIFICATIONS
---------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
	triggerServerEvent("spawnChoice.ready", resourceRoot)
end)

local function tryInitializeMap(mapName)
	if mapName and mapName ~= "" then
		currentMapName = mapName
	end

	-- STRICT CHECK: Output notices EXACTLY once per map
	if enabled and not hasShownEnabledNotice then
		hasShownEnabledNotice = true
		outputChatBox("[SpawnChoice] Enabled for this map! Use scroll, arrows, or RMB (CP #1).", 0, 255, 120)
	elseif not enabled and disableReason and disableReason ~= "" and not hasShownDisabledNotice then
		hasShownDisabledNotice = true
		outputChatBox("[SpawnChoice] Disabled: " .. disableReason, 255, 100, 100)
	end

	-- Auto-restore saved spawn quietly ONCE per map
	if enabled and currentMapName ~= "" and not hasRestoredForThisMap then
		local savedIdx = loadLocalSpawnIndex(currentMapName)
		if savedIdx then
			hasRestoredForThisMap = true
			currentSpawnIndex = savedIdx
			triggerServerEvent("spawnChoice.requestAbsolute", resourceRoot, savedIdx, true)
			outputChatBox("[SpawnChoice] Loaded saved spawn #" .. savedIdx .. " for this map.", 0, 255, 120)
		end
	end
end

addEvent("spawnChoice.enable", true)
addEventHandler("spawnChoice.enable", root, function(state, reason, mapName)
	enabled = state
	disableReason = reason or ""
	lastSwitchTick = 0

	tryInitializeMap(mapName)
end)

-- Reset flags immediately when a new map starts loading
addEventHandler("onClientMapStarting", root, function(mapInfo)
	disableReason = nil
	lastShownReason = nil
	hasRestoredForThisMap = false
	hasShownEnabledNotice = false
	hasShownDisabledNotice = false
	currentSpawnIndex = nil

	if mapInfo and mapInfo.resname then
		tryInitializeMap(mapInfo.resname)
	end
end)

---------------------------------------------------
-- INPUT HANDLERS
---------------------------------------------------
local function requestSwitch(direction)
	if type(direction) ~= "number" or direction == 0 or not enabled then return end
	if not localPlayer or not isPedInVehicle(localPlayer) then return end

	local now = getTickCount()
	if now - lastSwitchTick < switchCooldown then return end
	lastSwitchTick = now

	triggerServerEvent("spawnChoice.request", resourceRoot, direction)
end

local function requestClosestSpawnToFirstCP()
	if not enabled or not localPlayer or not isPedInVehicle(localPlayer) then return end
	triggerServerEvent("spawnChoice.requestClosestCP", resourceRoot)
end

bindKey("arrow_u", "down", function() requestSwitch(-1) end)
bindKey("arrow_d", "down", function() requestSwitch(1) end)

bindKey("arrow_l", "down", function() requestSwitch(-1) end)
bindKey("arrow_r", "down", function() requestSwitch(1) end)

bindKey("mouse_wheel_up", "down", function() requestSwitch(-1) end)
bindKey("mouse_wheel_down", "down", function() requestSwitch(1) end)

bindKey("mouse2", "down", requestClosestSpawnToFirstCP)

---------------------------------------------------
-- COMMAND
---------------------------------------------------
addCommandHandler("spawnchoice", function(_, arg)
	if not arg or not enabled then return end

	arg = tostring(arg):gsub("%s+", "")
	local absoluteIndex = tonumber(arg)

	if absoluteIndex then
		if absoluteIndex == 0 then return end
		triggerServerEvent("spawnChoice.requestAbsolute", resourceRoot, absoluteIndex, false)
		return
	end

	local offset = tonumber(arg)
	if offset and offset ~= 0 then
		requestSwitch(offset)
	end
end)

---------------------------------------------------
-- SERVER CONFIRMATION & RACE START OUTPUT
---------------------------------------------------
addEvent("spawnChoice.onIndexChanged", true)
addEventHandler("spawnChoice.onIndexChanged", resourceRoot, function(newIndex, isAutoRestore)
	if currentMapName ~= "" then
		currentSpawnIndex = newIndex

		-- Only re-save to XML if the user manually picked a new spawn
		if not isAutoRestore then
			saveLocalSpawnIndex(currentMapName, newIndex)
		end
	end
end)

-- Print final saved spawn selection ONCE when race countdown finishes
addEvent("spawnChoice.onRaceStarted", true)
addEventHandler("spawnChoice.onRaceStarted", resourceRoot, function()
	if currentSpawnIndex then
		outputChatBox("[SpawnChoice] Saved spawn #" .. currentSpawnIndex .. " locally for this map.", 0, 255, 120)
	end
end)
