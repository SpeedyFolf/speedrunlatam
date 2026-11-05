local tikis = {}
local collected = {}
local tikiDefs = {}
local mapTotals = {}
local currentMapInfo

local COL_RADIUS = 1.4
local currentMap = nil
local dataReady = false
local isLoggedIn = false

local hudMessage = nil
local hudTimer = nil

local tikiEnabled = true
local showInfo = true
local showBlips = true
local showText = false
local isGuiVisible = false
local gui = {}
local blips = {}

local SETTINGS_FILE = "tiki_settings.json"

local congratsLines = {
	"this text appears when you successfully find all tiki on a map",
	"gg go next",
	"tiki > black packages",
	"where's the achievement for this",
	"you did the thing",
	"congratulations from the bottom of my heart",
	"number go up",
	"joshimuz is oh so proud of you",
	"happy happy, joy joy",
	"your collection is getting expansive",
	"whoop-de-fricking-doo",
	"wonderful, wonderful, truly wonderful",
	"heightens the senses",
	"the tiki tickles in your tummy",
	"a map to be remembered",
	"who is hiding these",
	"isn't tiki lovely",
	"xoxoxo, -tiki",
	"how many licks does it take to get to the centre of a tiki",
	"you went and found yourself",
	"congratulations, you earned a tiki",
	"satisfactory elation with each collectation",
	"i'm so excited and i just can't hide it",
	"it's only very slightly addictive",
	"completionism reigns supreme",
	"you take my breath away",
	"boredom shall never prevail",
	"entertainment in moderate doses",
	"sunk cost fallacy is not real",
	"another stirring performance by you",
	"this one's to you",
	"beep boop",
	"running out of pocket space",
	"pink is my favourite colour",
	"i'm captain tiki, and this is my favorite map on the server",
	"utterly beaming with happiness",
	"oh man, that tiki filled a hole",
	"slimy, yet satisfying",
	"weeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
	"and it's sweet, sweet, sweet victory",
	"thank you for collecting me",
	"this might fill the void in you",
	"tiki today tiki tomorrow",
	"yay",
	"see you next time <3",
	"ladies and gentlemen, we got him",
	"do you think lotsofs will delete me one day",
	"yes, even that one",
	"already excited for the next hunt",
	"gotta collect 'em all",
	"i am your possession, unopened at your feet",
	"getting closer to 100%",
	"thought you'd never find me",
	"mission passed     respect+",
}

local function trim(s)
	return s and tostring(s):gsub("^%s*(.-)%s*$", "%1") or nil
end

local function getTableSize(t)
	local c = 0
	for _ in pairs(t) do c = c + 1 end
	return c
end

local function saveSettings()
	local data = { showInfo = showInfo, showBlips = showBlips, tikiEnabled = tikiEnabled, showText = showText }
	local file = fileCreate(SETTINGS_FILE)
	if file then
		fileWrite(file, toJSON(data))
		fileClose(file)
	end
end

local function loadSettings()
	if fileExists(SETTINGS_FILE) then
		local file = fileOpen(SETTINGS_FILE)
		local data = fromJSON(fileRead(file, fileGetSize(file)))
		fileClose(file)
		if data then
			showInfo = data.showInfo or false
			showBlips = (data.showBlips ~= nil) and data.showBlips or true
			tikiEnabled = (data.tikiEnabled ~= nil) and data.tikiEnabled or true
			showText = (data.showText ~= nil) and data.showText or false
		end
	end
end

local function getMapProgress(mapName)
	if not mapName then return 0, 0 end
	local count = 0
	for id, def in pairs(tikiDefs) do
		-- Check if it's assigned to this map AND if it exists in the 'collected' table
		if def.maps[mapName] and collected[id] then
			-- Count it if it's a table (saved) OR if it's currently "Saving..."
			count = count + 1
		end
	end
	return count, mapTotals[mapName] or 0
end

local function printMapProgress()
	if not currentMap then return end
	local count, total = getMapProgress(currentMap)
	if total > 0 then
		outputChatBox("[Tiki] You've collected #FFEA66" .. count .. " #FF96FFout of #FFEA66" .. total .. " #FF96FFtiki on #FFEA66" .. currentMap .. "#FF96FF!", 255, 150, 255, true)
	end
end

local function updateBlips()
	for _, blip in pairs(blips) do if isElement(blip) then destroyElement(blip) end end
	blips = {}

	-- Make sure we have a map loaded before trying to spawn blips
	if not showBlips or not dataReady or not currentMap then return end

	for id, def in pairs(tikiDefs) do
		-- def.maps[currentMap] ensures we only show blips for the current map
		if def.maps[currentMap] and collected[id] and collected[id] ~= "Saving..." then
			local blip = createBlip(def.x, def.y, def.z, 0, 1, 255, 150, 255, 255, 0, 250)
			blips[id] = blip
		end
	end
end

---------------------------------------------------
-- LOAD XML DEFINITIONS
---------------------------------------------------
local function loadTikis()
	local xml = xmlLoadFile("tikis.map")
	if not xml then return false end

	tikiDefs = {}
	mapTotals = {}

	for _, node in ipairs(xmlNodeGetChildren(xml)) do
		if xmlNodeGetName(node) == "tiki" then
			local id = trim(xmlNodeGetAttribute(node, "id"))
			local mapStr = trim(xmlNodeGetAttribute(node, "map"))
			local x = tonumber(xmlNodeGetAttribute(node, "posX"))
			local y = tonumber(xmlNodeGetAttribute(node, "posY"))
			local z = tonumber(xmlNodeGetAttribute(node, "posZ"))

			if id and mapStr and x and y and z then
				local mapTable = {}
				-- Split comma-separated maps into a table
				for m in string.gmatch(mapStr, '([^,]+)') do
					local cleanMap = trim(m)
					mapTable[cleanMap] = true
					mapTotals[cleanMap] = (mapTotals[cleanMap] or 0) + 1
				end

				tikiDefs[id] = { id = id, mapDisplay = mapStr, maps = mapTable, x = x, y = y, z = z + 0.5 }
			end
		end
	end
	xmlUnloadFile(xml)
end

---------------------------------------------------
-- SPAWN / DESTROY / LOGIC
---------------------------------------------------
local function spawnTikis()
	if not currentMap or not dataReady or not tikiEnabled then return end
	for _, data in pairs(tikis) do
		if isElement(data.object) then destroyElement(data.object) end
		if isElement(data.col) then destroyElement(data.col) end
	end
	tikis = {}
	for id, def in pairs(tikiDefs) do
		-- Check against the multi-map table
		if def.maps[currentMap] and not collected[id] then
			local obj = createObject(1276, def.x, def.y, def.z)
			setElementCollisionsEnabled(obj, false)
			local col = createColSphere(def.x, def.y, def.z, COL_RADIUS)
			setElementData(col, "tiki:id", id, false)
			tikis[id] = { object = obj, col = col }
		end
	end
end

local function toggleTikiResource(state)
	tikiEnabled = state
	saveSettings()

	if isElement(gui.tikiToggle) then
		guiCheckBoxSetSelected(gui.tikiToggle, tikiEnabled)
	end

	if not tikiEnabled then
		-- Cleanly clear all existing physical elements
		for _, data in pairs(tikis) do
			if isElement(data.object) then destroyElement(data.object) end
			if isElement(data.col) then destroyElement(data.col) end
		end
		tikis = {}

		-- Clear blips
		for _, blip in pairs(blips) do if isElement(blip) then destroyElement(blip) end end
		blips = {}

		hudMessage = nil
		if isTimer(hudTimer) then killTimer(hudTimer) end
	else
		-- Respawn everything if enabled
		spawnTikis()
		updateBlips()
		if showInfo then printMapProgress() end
	end
end

---------------------------------------------------
-- GUI FUNCTIONS
---------------------------------------------------
local function updateProgressText()
	if not isElement(gui.progressLabel) then return end
	local totalCollected = getTableSize(collected)
	local totalTikis = getTableSize(tikiDefs)
	if totalCollected == 0 then
		guiSetText(gui.progressLabel, "There are ".. totalTikis .. " tiki waiting for especially for you to collect.")
	elseif totalCollected >= totalTikis then
		guiSetText(gui.progressLabel, "You've collected all " .. totalTikis .. " tiki! Your collection is complete.")
	else
		local percent = (totalCollected / totalTikis) * 100
		guiSetText(gui.progressLabel, "You've collected a grand total of " .. totalCollected .. " out of " .. totalTikis .. " tiki! (" .. string.format("%.1f", percent) .. "%)")
	end
end

local function refreshGrid()
	if not gui.list then return end
	guiGridListClear(gui.list)

	local sortedIDs = {}
	for id in pairs(tikiDefs) do table.insert(sortedIDs, id) end

	table.sort(sortedIDs, function(a, b)
		local numA = tonumber(a:match("%d+")) or 0
		local numB = tonumber(b:match("%d+")) or 0
		return numA < numB
	end)

	for _, id in ipairs(sortedIDs) do
		local def = tikiDefs[id]
		local seqStr = ""
		local statusStr = "Uncollected"
		local rCol, gCol, bCol = 255, 255, 255

		if collected[id] then
			if type(collected[id]) == "table" then
				seqStr = string.format("%03d", collected[id].seq)
				statusStr = collected[id].time
			else
				seqStr = "?"
				statusStr = tostring(collected[id])
			end
			rCol, gCol, bCol = 255, 150, 255
		end

		-- Add leading zeroes for sorting cause cba changing IDs
		local displayID = id:gsub("%d+", function(num)
			return string.format("%03d", tonumber(num))
		end)

		-- Atomic insertion
		local r = guiGridListAddRow(gui.list, displayID, seqStr, def.mapDisplay, statusStr)

		-- Save real id
		guiGridListSetItemData(gui.list, r, 1, id)

		guiGridListSetItemColor(gui.list, r, 1, rCol, gCol, bCol)
		guiGridListSetItemColor(gui.list, r, 2, rCol, gCol, bCol)
		guiGridListSetItemColor(gui.list, r, 3, rCol, gCol, bCol)
		guiGridListSetItemColor(gui.list, r, 4, rCol, gCol, bCol)
	end

	updateProgressText()
end

local function createTikiWindow()
	local screenWidth, screenHeight = guiGetScreenSize()
	local windowWidth, windowHeight = 800, 600

	-- Calculate the center position
	local x = (screenWidth - windowWidth) / 2
	local y = (screenHeight - windowHeight) / 2

	gui.win = guiCreateWindow(x, y, windowWidth, windowHeight, "", false)

	gui.progressLabel = guiCreateLabel(0.02, 0.06, 0.96, 0.05, "", true, gui.win)
	guiLabelSetHorizontalAlign(gui.progressLabel, "center")

	gui.tabPanel = guiCreateTabPanel(0.02, 0.08, 0.96, 0.70, true, gui.win)

	-- Tab 1: Progress
	gui.tabMyTikis = guiCreateTab("Progress", gui.tabPanel)
	gui.list = guiCreateGridList(0, 0, 1, 1, true, gui.tabMyTikis)
	guiGridListAddColumn(gui.list, "ID", 0.15)
	guiGridListAddColumn(gui.list, "#", 0.07)
	guiGridListAddColumn(gui.list, "Map", 0.45)
	guiGridListAddColumn(gui.list, "Status", 0.25)

	-- Tab 2: Leaderboard
	gui.tabLeaderboard = guiCreateTab("Leaderboard", gui.tabPanel)
	gui.lbList = guiCreateGridList(0, 0, 1, 1, true, gui.tabLeaderboard)
	guiGridListAddColumn(gui.lbList, "Rank", 0.1)
	guiGridListAddColumn(gui.lbList, "Player", 0.5)
	guiGridListAddColumn(gui.lbList, "Progress", 0.15)
	guiGridListAddColumn(gui.lbList, "Percentage", 0.15)

	-- Bottom Controls
	gui.tikiToggle = guiCreateCheckBox(0.05, 0.81, 0.6, 0.04, "Global enable or disable (/tikitoggle)", tikiEnabled, true, gui.win)
	gui.infoToggle = guiCreateCheckBox(0.05, 0.85, 0.6, 0.04, "Show map info in chat when loading (/tikimap)", showInfo, true, gui.win)
	gui.blipToggle = guiCreateCheckBox(0.05, 0.89, 0.6, 0.04, "Show collected blips (/tikiblips)", showBlips, true, gui.win)
	gui.textToggle = guiCreateCheckBox(0.05, 0.93, 0.6, 0.04, "Show pickup info in chat when collected (/tikitext)", showText, true, gui.win)

	-- Close button
	gui.close = guiCreateButton(0.65, 0.82, 0.29, 0.14, "Close", true, gui.win)

	-- Close button closes
	addEventHandler("onClientGUIClick", gui.close, function()
		isGuiVisible = false; guiSetVisible(gui.win, false); showCursor(false)
	end, false)

	-- Resource toggle
	addEventHandler("onClientGUIClick", gui.tikiToggle, function()
		local selected = guiCheckBoxGetSelected(gui.tikiToggle)
		toggleTikiResource(selected)
	end, false)

	-- Blips toggle
	addEventHandler("onClientGUIClick", gui.blipToggle, function()
		showBlips = guiCheckBoxGetSelected(gui.blipToggle)
		saveSettings(); updateBlips()
	end, false)

	-- Map info toggle
	addEventHandler("onClientGUIClick", gui.infoToggle, function()
		showInfo = guiCheckBoxGetSelected(gui.infoToggle)
		saveSettings(); if showInfo then printMapProgress() end
	end, false)

	-- Pickup info toggle
	addEventHandler("onClientGUIClick", gui.textToggle, function()
		showText = guiCheckBoxGetSelected(gui.textToggle)
		saveSettings()
	end, false)

	local function checkTabRefresh()
		if guiGetSelectedTab(gui.tabPanel) == gui.tabLeaderboard then
			guiGridListClear(gui.lbList)
			local r = guiGridListAddRow(gui.lbList)
			guiGridListSetItemText(gui.lbList, r, 2, "Tiki are everywhere...", false, false)
			triggerServerEvent("tiki:requestLeaderboard", resourceRoot)
		end
	end
	addEventHandler("onClientGUITabSwitched", gui.tabLeaderboard, checkTabRefresh, false)
	guiSetVisible(gui.win, false)
end

addEvent("tiki:forceClose", true)
addEventHandler("tiki:forceClose", resourceRoot, function()
	if gui.win and isElement(gui.win) and guiGetVisible(gui.win) then
		guiSetVisible(gui.win, false)
		showCursor(false)
		isGuiVisible = false
	end
end)

---------------------------------------------------
-- EVENTS & COMMANDS
---------------------------------------------------
addEventHandler("onClientMapStarting", root, function(mapInfo)
	currentMapInfo = mapInfo
end)

addEventHandler("onClientScreenFadedIn", root, function()
	if not currentMapInfo then return end

	currentMap = currentMapInfo.resname
	spawnTikis()
	updateBlips()

	if showInfo and tikiEnabled then
		printMapProgress()
	end

	currentMapInfo = nil
end)

addEvent("tiki:sync", true)
addEventHandler("tiki:sync", root, function(serverList, loggedInStatus)
	collected = serverList or {}
	isLoggedIn = loggedInStatus
	dataReady = true
	spawnTikis()
	updateBlips()
end)

addEventHandler("onClientColShapeHit", root, function(element, matchingDimension)
	if element ~= localPlayer or not matchingDimension then return end
	local tikiID = trim(getElementData(source, "tiki:id"))
	if not tikiID or collected[tikiID] then return end

	if not isLoggedIn then
		outputChatBox("[Tiki] You must be logged in to collect tiki.", 255, 150, 255, true)
		return
	end

	local vehicle = getPedOccupiedVehicle(localPlayer)
	if vehicle and getVehicleType(vehicle) == "Helicopter" then
		outputChatBox("[Tiki] Collecting is meant to be done for the love of the game.", 255, 150, 255, true)
		return
	end

	playSound("pickup.mp3")

	collected[tikiID] = "Saving..."
	triggerServerEvent("tiki:collect", resourceRoot, tikiID, currentMap)

	if tikis[tikiID] then
		destroyElement(tikis[tikiID].object)
		destroyElement(tikis[tikiID].col)
		tikis[tikiID] = nil
	end

	local count, total = getMapProgress(currentMap)

	if total > 0 then

			if showText then
			-- Fake leading zero lol
			local numericPart = tonumber(tikiID:match("%d+")) or 0
			local displayID = string.format("tiki (%03d)", numericPart)

			outputChatBox("[Tiki] Collected #FFEA66" .. displayID .. "#FF96FF! You've collected #FFEA66" .. count .. " #FF96FFout of #FFEA66" .. total .. " #FF96FFtiki on #FFEA66" .. currentMap .. "#FF96FF.", 255, 150, 255, true)
		end

		hudMessage = string.format("Tiki Collected\n\n%d out of %d on %s", count, total, currentMap)

		-- Map fully collected
		if count >= total then

			setTimer(playSound, 250, 1, "map.mp3")

			local randomMsg = congratsLines[math.random(#congratsLines)]
			hudMessage = hudMessage .. "\n\n" .. randomMsg
		end

		if isTimer(hudTimer) then killTimer(hudTimer) end
		hudTimer = setTimer(function() hudMessage = nil end, 6666, 1)
	end
end)

addEvent("tiki:updateSingle", true)
addEventHandler("tiki:updateSingle", root, function(tikiID, timestamp, sequenceNum)
	-- Store both time and sequential number
	collected[tikiID] = { time = timestamp, seq = sequenceNum }
	updateBlips()
	if isGuiVisible then refreshGrid() end
end)

addEvent("tiki:receiveLeaderboard", true)
addEventHandler("tiki:receiveLeaderboard", root, function(lbData, localAccount)
	if not isElement(gui.lbList) then return end
	guiGridListClear(gui.lbList)

	-- Get the global total from the loaded XML definitions
	local totalTikis = getTableSize(tikiDefs)
	if totalTikis == 0 then totalTikis = 1 end -- Fallback

	for i, row in ipairs(lbData) do
		local r = guiGridListAddRow(gui.lbList)
		guiGridListSetItemText(gui.lbList, r, 1, tostring(i), false, false)

		-- Display last known nickname
		guiGridListSetItemText(gui.lbList, r, 2, row.nickname or row.account, false, false)

		-- Display as collected_amount
		guiGridListSetItemText(gui.lbList, r, 3, tostring(row.total), false, false)

		-- Calculate percentage and format to 1 decimal place
		local percentage = (row.total / totalTikis) * 100
		guiGridListSetItemText(gui.lbList, r, 4, string.format("%.1f", percentage) .. "%", false, false)

		-- Highlights player (Updated to include the 4th column)
		if localAccount and row.account == localAccount then
			guiGridListSetItemColor(gui.lbList, r, 1, 255, 150, 255)
			guiGridListSetItemColor(gui.lbList, r, 2, 255, 150, 255)
			guiGridListSetItemColor(gui.lbList, r, 3, 255, 150, 255)
			guiGridListSetItemColor(gui.lbList, r, 4, 255, 150, 255)
		end
	end
end)

addCommandHandler("tiki", function()
	if not gui.win then createTikiWindow() end
	isGuiVisible = not isGuiVisible
	guiSetVisible(gui.win, isGuiVisible)
	showCursor(isGuiVisible)
	if isGuiVisible then
		refreshGrid()
		guiSetSelectedTab(gui.tabPanel, gui.tabMyTikis)
	end
end)

addCommandHandler("tikimap", function(player)
	printMapProgress()
end)

addCommandHandler("tikiblips", function()
	showBlips = not showBlips
	guiCheckBoxSetSelected(gui.blipToggle, showBlips)
	saveSettings()
	updateBlips()
end)

addCommandHandler("tikitoggle", function()
	toggleTikiResource(not tikiEnabled)
	local status = tikiEnabled and "#FFEA66shown" or "#FF0000hidden"
	outputChatBox("[Tiki] Everything tiki will now be " .. status .. "#FF96FF.", 255, 150, 255, true)
end)

addEventHandler("onClientRender", root, function()
	if not hudMessage then return end

	local sx, sy = guiGetScreenSize()

	-- Filter out the empty strings caused by \n\n
	local lines = {}
	for line in string.gmatch(hudMessage, "[^\r\n]+") do
		table.insert(lines, line)
	end

	dxDrawBorderedText(1, lines[1], 0, sy * 0.25, sx, sy, tocolor(255, 150, 255, 255), 3.6, "pricedown", "center", "top", false, false, false, true)
	dxDrawBorderedText(1, lines[2], 0, sy * 0.25 + 90, sx, sy, tocolor(255, 255, 255, 255), 1.6, "bankgothic", "center", "top", false, false, false, true)

	if lines[3] then
		dxDrawBorderedText(0.6, lines[3], 0, sy * 0.25 + 160, sx, sy, tocolor(255, 150, 255, 255), 1.5, "unifont", "center", "top", false, false, false, true)
	end
end)

addEventHandler("onClientRender", root, function()
	if not isGuiVisible or not isElement(gui.win) then return end

	local wx, wy = guiGetPosition(gui.win, false)
	local ww, wh = guiGetSize(gui.win, false)

	dxDrawBorderedText(1, "Tiki Collector", wx, wy - 80, wx + ww, wy, tocolor(255, 150, 255, 255), 3.4, "pricedown", "center", "top", false, false, true, true)
	dxDrawBorderedText(1, "go find yourself", wx, wy - 8, wx + ww, wy, tocolor(222, 222, 222, 255), 1, "bankgothic", "center", "top", false, false, true, true)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
	loadSettings()
	loadTikis()
	triggerServerEvent("tiki:requestSync", resourceRoot)
end)

function dxDrawBorderedText(outline, text, left, top, right, bottom, color, scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	if type(scaleY) == "string" then
		scaleY, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY = scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX
	end
	local outlineX = (scaleX or 1) * (1.333333333333334 * (outline or 1))
	local outlineY = (scaleY or 1) * (1.333333333333334 * (outline or 1))
	dxDrawText (text:gsub("#%x%x%x%x%x%x", ""), left - outlineX, top - outlineY, right - outlineX, bottom - outlineY, tocolor (0, 0, 0, 225), scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	dxDrawText (text:gsub("#%x%x%x%x%x%x", ""), left + outlineX, top - outlineY, right + outlineX, bottom - outlineY, tocolor (0, 0, 0, 225), scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	dxDrawText (text:gsub("#%x%x%x%x%x%x", ""), left - outlineX, top + outlineY, right - outlineX, bottom + outlineY, tocolor (0, 0, 0, 225), scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	dxDrawText (text:gsub("#%x%x%x%x%x%x", ""), left + outlineX, top + outlineY, right + outlineX, bottom + outlineY, tocolor (0, 0, 0, 225), scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	dxDrawText (text:gsub("#%x%x%x%x%x%x", ""), left - outlineX, top, right - outlineX, bottom, tocolor (0, 0, 0, 225), scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	dxDrawText (text:gsub("#%x%x%x%x%x%x", ""), left + outlineX, top, right + outlineX, bottom, tocolor (0, 0, 0, 225), scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	dxDrawText (text:gsub("#%x%x%x%x%x%x", ""), left, top - outlineY, right, bottom - outlineY, tocolor (0, 0, 0, 225), scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	dxDrawText (text:gsub("#%x%x%x%x%x%x", ""), left, top + outlineY, right, bottom + outlineY, tocolor (0, 0, 0, 225), scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
	dxDrawText (text, left, top, right, bottom, color, scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
end
