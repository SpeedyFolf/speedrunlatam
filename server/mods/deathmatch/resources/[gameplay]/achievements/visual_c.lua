local screenX, screenY = guiGetScreenSize()

local popupColors = {
	tocolor(0, 0, 0, 170), -- Background
	tocolor(0, 0, 0, 255), -- Shadow of the Icon
	tocolor(175, 202, 230, 255) -- Text
}

-- Settings that are stored on client in file settings.json
local settings = {
	type = 0,
	hide_unlocked = 0,
	posX = 0.4,
	posY = 0.1,
	borderEnabled = 1,
	borderLockedColor = 0xFF000000,
	borderUnlockedColor = 0xFF00C720
}

local settingsDefault = {
	type = 0,
	hide_unlocked = 0,
	posX = 0.4,
	posY = 0.1,
	borderEnabled = 1,
	borderLockedColor = 0xFF000000,
	borderUnlockedColor = 0xFF00C720
}

-- Rendering
local renderPool = {}
local boxZ = 0
local boxSize = { screenY * 5.1 / 11.5, screenY / 11.5 } -- posX, posY, width, height 480 93.9
local wordWrapSize = boxSize[1] * 0.8

-- Load icons
local iconsTextures = {} -- Unlocked Icons
local iconsTexturesLocked = {} -- Locked Icons
for _, v in ipairs(achievementsList) do
	for _, a in ipairs(v) do
		iconsTextures[a.ID] = dxCreateTexture("icons/" .. a.ID .. ".png")
		if fileExists("icons/gray/" .. a.ID .. ".png") then
			iconsTexturesLocked[a.ID] = dxCreateTexture("icons/gray/" .. a.ID .. ".png")
		end
	end
end

-- GUI
local window, tabPanel
local receivedData
local tabs = {}
local gridLists = {}
local iconsShader = dxCreateShader("shader.fx")

-- Tooltips
local toolTipX, toolTipY
local tooltipID, tooltipCat -- ID of achievement that displayed in the tooltip
local tooltipText

-- settings GUI
local settingsWindow
local movingPopup = false
local movingPopupOffsetX, movingPopupOffsetY = 0, 0
local previousTab

-- Bridges
local bridgeText = "What a waste of good balls!"
local bridgeTextEnabled -- Timer
local collectedBridges, showBridges = nil, false
local bridgesBlips = {}
local bridgeZones = nil

-- Colorpicker
tempColors = {
	["locked"] = settings.borderLockedColor,
	["unlocked"] = settings.borderUnlockedColor
}

-- Search function
local search, searchState = nil, ""
local matched = {}

function update()
	for i = #renderPool, 1, -1 do
		if getTickCount() > renderPool[i][1] + 10000 then
			table.remove(renderPool, i)
		end
	end

	-- Wheel state check (used Bridges)
	setElementData(localPlayer, "ach_wheelState", getPedOccupiedVehicle(localPlayer) and (isVehicleWheelOnGround(getPedOccupiedVehicle(localPlayer), 0) or isVehicleWheelOnGround(getPedOccupiedVehicle(localPlayer), 1) or isVehicleWheelOnGround(getPedOccupiedVehicle(localPlayer), 2) or isVehicleWheelOnGround(getPedOccupiedVehicle(localPlayer), 3)))
end

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

addEventHandler("onClientResourceStart", resourceRoot, function()
	-- Sort
	sortAchievements()

	if isTimer(updateTimer) then
		killTimer(updateTimer)
	end
	updateTimer = setTimer(update, 50, 0)

	-- Settings file management
	loadSettings()
end )

function loadSettings()
	if not fileExists("settings.json") then
		local file = fileCreate("settings.json")
		fileWrite(file, toJSON(settings))
		fileClose(file)
	else
		local file = fileOpen("settings.json", false)
		local contents = fileRead(file, fileGetSize(file))
		contents = fromJSON(contents)
		if contents.type == 1 or contents.type == 0 then
			-- file is correct, read values
			for i, v in pairs(contents) do settings[i] = v end
			fileClose(file)

			tempColors["locked"] = settings.borderLockedColor
			tempColors["unlocked"] = settings.borderUnlockedColor
		else
			-- file is not corrent
			outputChatBox("[Achievements] Settings file error. Creating new...")
			fileDelete(file)
			file = fileCreate("settings.json")
			fileWrite(file, toJSON(settings))
			fileClose(file)
		end
	end
end

function saveSettings()
	settings.borderLockedColor = tempColors["locked"]
	settings.borderUnlockedColor = tempColors["unlocked"]

	fileDelete("settings.json")
	local file = fileCreate("settings.json")
	fileWrite(file, toJSON(settings))
	fileClose(file)
end

addEvent("showPopup", true)
addEventHandler("showPopup", root, function(achievementID, percentage)
	table.insert(renderPool, {getTickCount(), achievementID, percentage}) -- visuals
	playSoundFrontEnd(11) -- sound
end )

addEventHandler("onClientRender", root, function()
	-- Popup
	for i = #renderPool, 1, -1 do
		-- Background
		dxDrawRectangle(screenY * settings.posX, (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2, boxSize[1], boxSize[2], popupColors[1])

		-- Icon
		dxDrawRectangle(screenY * settings.posX + boxSize[2] * 0.085, (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 + boxSize[2] * 0.085, boxSize[2] * 0.87, boxSize[2] * 0.87, popupColors[2])
		dxDrawImage(screenY * settings.posX + boxSize[2] * 0.075, (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 + boxSize[2] * 0.075, boxSize[2] * 0.85, boxSize[2] * 0.85, iconsTextures[renderPool[i][2]], 0, 0, 0, tocolor(255, 255, 255, 255))

		-- Name
		dxDrawBorderedText(1, getAchievementByID(renderPool[i][2]).name, screenY * settings.posX + boxSize[2] + 3, (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 - boxSize[2] / 6.5 + 3, screenX, screenY, popupColors[2], screenY / 800, "beckett", "left", "top", true, false)
		dxDrawBorderedText(1, getAchievementByID(renderPool[i][2]).name, screenY * settings.posX + boxSize[2], (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 - boxSize[2] / 6.5, screenX, screenY, popupColors[3], screenY / 800, "beckett", "left", "top", true, false)

		-- Description
		local text, size = wordWrap(getAchievementByID(renderPool[i][2]).description, wordWrapSize, screenY / 1400)
		dxDrawBorderedText(1, text, screenY * settings.posX + boxSize[2], (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 + boxSize[2] / 3.8, screenX, screenY, popupColors[3], size, "bankgothic", "left", "top", true, false)

		-- How many players got
		dxDrawBorderedText(1, string.format("%.1f", renderPool[i][3]) .. "% of players got this achievement", screenY * settings.posX + boxSize[2], (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 + boxSize[2] / 1.3, screenX, screenY, popupColors[3], screenY / 1900, "bankgothic", "left", "top", true, false)
	end

	-- Example Popup for the settings
	if isElement(window) and guiGetSelectedTab(tabPanel) == tabs["settings"] then
		for i = 1, 2 do
			dxDrawRectangle(screenY * settings.posX, (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2, boxSize[1], boxSize[2], popupColors[1])

			dxDrawRectangle(screenY * settings.posX + boxSize[2] * 0.085, (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 + boxSize[2] * 0.085, boxSize[2] * 0.87, boxSize[2] * 0.87, popupColors[2])
			dxDrawImage(screenY * settings.posX + boxSize[2] * 0.075, (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 + boxSize[2] * 0.075, boxSize[2] * 0.85, boxSize[2] * 0.85, iconsTextures["disco4"], 0, 0, 0, tocolor(255, 255, 255, 255))

			dxDrawBorderedText(1, "Example", screenY * settings.posX + boxSize[2] + 3, (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 - boxSize[2] / 6.5 + 3, screenX, screenY, popupColors[2], screenY / 800, "beckett", "left", "top", true, false)
			dxDrawBorderedText(1, "Example", screenY * settings.posX + boxSize[2], (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 - boxSize[2] / 6.5, screenX, screenY, popupColors[3], screenY / 800, "beckett", "left", "top", true, false)

			local text, size = wordWrap("Mow every lawn as Lance Vance on Vance Landscaping", wordWrapSize, screenY / 1400)
			dxDrawBorderedText(1, text, screenY * settings.posX + boxSize[2], (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 + boxSize[2] / 3.8, screenX, screenY, popupColors[3], size, "bankgothic", "left", "top", true, false)

			dxDrawBorderedText(1, "69.4% of players got this achievement", screenY * settings.posX + boxSize[2], (screenY - screenY * settings.posY) - boxSize[2] * (i-1) * 1.2 + boxSize[2] / 1.3, screenX, screenY, popupColors[3], screenY / 1900, "bankgothic", "left", "top", true, false)
		end
	end

	-- Bridges text message
	if isTimer(bridgeTextEnabled) then
		dxDrawRectangle(0, screenY / 4.1, screenX, (screenY / 5.05), tocolor(0, 0, 0, 80))
		dxDrawBorderedText(1, "Under The Bridge", screenX / 2, screenY / 4, screenX / 2, screenY / 4, tocolor(255, 255, 255, 255), screenY / 350, "pricedown", "center", "top")
		dxDrawBorderedText(1, bridgeText, screenX / 2, screenY / 3, screenX / 2, screenY / 3, tocolor(175, 202, 230, 255), screenY / 600, "pricedown", "center", "top")
	end

	-- Icons
	if isElement(window) and settings.type == 0 and (guiGetText(guiGetSelectedTab(tabPanel)) ~= "Settings" and guiGetText(guiGetSelectedTab(tabPanel)) ~= "Leaderboard" and guiGetText(guiGetSelectedTab(tabPanel)) ~= "Stats" and guiGetText(guiGetSelectedTab(tabPanel)) ~= "Checklist" and guiGetText(guiGetSelectedTab(tabPanel)) ~= "Bridges") then
		local activeTab = guiGetSelectedTab(tabPanel)
		local tabWidth, tabHeight = guiGetSize(activeTab, false)
		local windowPosX, windowPosY = guiGetPosition(window, false)
		local tabPosX, tabPosY = guiGetPosition(tabPanel, false)

		tabPosX = tabPosX + windowPosX
		tabPosY = tabPosY + windowPosY

		-- Find out whats this tab actually is
		local achCategory
		for i = 1, #achievementsListTabs do
			if guiGetText(activeTab) == achievementsListTabs[i] then
				achCategory = i
				break
			end
		end

		-- Draw icons for this category
		local col, row = 1, 0
		for i, v in ipairs(achievementsList[achCategory]) do
			if ((settings.hide_unlocked == 1 and not receivedData[achCategory][i][1]) or (settings.hide_unlocked == 0))
			and (searchState == "" or receivedData[achCategory][i]["matched"]) then
				-- Define icon size and margin
				local iconSize = screenY * 0.07 												-- Actual icon size in px
				local iconSizeRelative = {w = iconSize / tabWidth, h = iconSize / tabHeight} 	-- Relative to window icon size
				local margin = {w = iconSizeRelative.w * 0.15, h = iconSizeRelative.h * 0.15}	-- Margine size (relative)
				local iconPosX, iconPosY = tabPosX + (margin.w + (iconSizeRelative.w + margin.w) * col - (iconSizeRelative.w + margin.w)) * tabWidth, tabPosY + (0.07 + row * (iconSizeRelative.h + margin.h)) * tabHeight

				if receivedData[achCategory][i][1] then
					-- Unlocked achievement
					if settings.borderEnabled == 1 then
						dxDrawRectangle(iconPosX, iconPosY, iconSize, iconSize, settings.borderUnlockedColor, true)
						dxDrawImage(iconPosX + iconSize * 0.03, iconPosY + iconSize * 0.03, iconSize - iconSize * 0.06, iconSize - iconSize * 0.06, iconsTextures[v.ID], 0, 0, 0, tocolor(255, 255, 255, 255), true)
					else dxDrawImage(iconPosX, iconPosY, iconSize, iconSize, iconsTextures[v.ID], 0, 0, 0, tocolor(255, 255, 255, 255), true) end
				else
					-- Locked Achievement
					local iconMaterial
					if iconsTexturesLocked[v.ID] then
						-- Custom B/W icon exists - Draw it
						iconMaterial = iconsTexturesLocked[v.ID]
					else
						-- Use shader to draw B/W icon
						dxSetShaderValue(iconsShader, "icon", iconsTextures[v.ID])
						iconMaterial = iconsShader
					end

					-- Draw icon
					if settings.borderEnabled == 1 then
						dxDrawRectangle(iconPosX, iconPosY, iconSize, iconSize, settings.borderLockedColor, true)
						dxDrawImage(iconPosX + iconSize * 0.03, iconPosY + iconSize * 0.03, iconSize - iconSize * 0.06, iconSize - iconSize * 0.06, iconMaterial, 0, 0, 0, tocolor(255, 255, 255, 255), true)
					else dxDrawImage(iconPosX, iconPosY, iconSize, iconSize, iconMaterial, 0, 0, 0, tocolor(255, 255, 255, 255), true) end
				end

				-- Next row of achievements
				col = col + 1
				if margin.w + (iconSizeRelative.w + margin.w) * col > 1 then
					row = row + 1
					col = 1
				end
			end
		end
	end

	-- The drawing of the tooltips
	if tooltipID and isElement(window) then
		-- Drawing yay
		local textWidth, textHeight = dxGetTextSize(tooltipText, dxGetTextWidth(tooltipText, 1.0, "default", false), 1.0, 1.0, "default")
		dxDrawRectangle(toolTipX + 5, toolTipY, textWidth + 20, textHeight + 20, tocolor(0, 0, 0, 255), true)
		dxDrawText(tooltipText, toolTipX + 15, toolTipY + 5, toolTipX, toolTipY, tocolor(255, 255, 255, 255), 1.0, 1.0, "default", "left", "top", false, false, true)
	end
end )

function loadGUI()
	updateSearch()

	for k, v in ipairs(receivedData) do
		if isElement(gridLists[k]) then
			destroyElement(gridLists[k])
		end

		if settings.type == 1 then
			-- Gridlist
			gridLists[k] = guiCreateGridList(0.02, 0.02, 0.97, 0.95, true, tabs[k])

			guiGridListAddColumn(gridLists[k], "Name", 0.24)
			guiGridListAddColumn(gridLists[k], "Description", 0.35)
			guiGridListAddColumn(gridLists[k], "Map", 0.15)
			guiGridListAddColumn(gridLists[k], "State", 0.09)
			guiGridListAddColumn(gridLists[k], "Progress", 0.12)
			guiGridListAddColumn(gridLists[k], "Percentage", 0.1)

			local text = string.gsub(string.lower(guiGetText(search)), " ", "")

			for i, contents in ipairs(receivedData[k]) do
				if (settings.hide_unlocked == 1 and not receivedData[k][i][1]) or (settings.hide_unlocked == 0) then
					local ach = getAchievementByGroupAndPos(k, i)

					-- Only show if search matches
					if text == "" or receivedData[k][i]["matched"] then
						local row = guiGridListAddRow(gridLists[k])

						guiGridListSetItemText(gridLists[k], row, 1, ach.name, false, false)
						guiGridListSetItemText(gridLists[k], row, 2, ach.description, false, false)

						-- Combine all map names into a single string
						local mapText = ""
						if ach.maps and #ach.maps > 0 then
							mapText = table.concat(ach.maps, ", ")
						end
						guiGridListSetItemText(gridLists[k], row, 3, mapText, false, false)

						-- State
						if receivedData[k][i][1] then
							guiGridListSetItemText(gridLists[k], row, 4, "Unlocked", false, false)
						else
							guiGridListSetItemText(gridLists[k], row, 4, "Locked", false, false)
						end

						guiGridListSetItemText(gridLists[k], row, 5, receivedData[k][i][2] .. "/" .. ach.stages, false, true)
						guiGridListSetItemText(gridLists[k], row, 6, string.format("%.1f", receivedData[k][i][3]) .. "%", false, true)
					end
				end
			end
		end
	end
end

function updateSearch()
	searchState = string.gsub(string.lower(guiGetText(search)), " ", "")

	for catID, achCategory in ipairs(achievementsList) do
		for i, ach in ipairs(achCategory) do
			local found = false

			if searchState ~= "" then
				-- Search achievement name if AchName is ticked
				if guiCheckBoxGetSelected(button_AchName) then
					local achName = string.gsub(string.lower(ach.name or ""), " ", "")
					if string.find(achName, searchState, 1, true) then
						found = true
					end
				end

				-- Search map names if MapName is ticked and not already found
				if not found and guiCheckBoxGetSelected(button_MapName) and ach.maps then
					for _, map in pairs(ach.maps) do
						local mapName = string.gsub(string.lower(map), " ", "")
						if string.find(mapName, searchState, 1, true) then
							found = true
							break
						end
					end
				end
			else
				-- Empty search matches everything
				found = true
			end

			receivedData[catID][i]["matched"] = found
		end
	end
end

-- Stage 1: Database request from the server
function showAchievements()
	if isElement(window) then
		colorPicker.closeSelect()
		saveSettings()
		searchState = guiGetText(search)
		destroyElement(window)
		guiSetInputMode("allow_binds")
		showCursor(false)
		previousTab = nil
	else
		-- Request data from DATABASE
		--triggerServerEvent("achs_requestBridges", localPlayer, false)
		triggerServerEvent("getAchievements", localPlayer)
	end
end
addCommandHandler("achievements", showAchievements)
addCommandHandler("ach", showAchievements)
bindKey("F1", "down", showAchievements)

-- Stage 2: Server send the achievements data, all tabs created here
addEvent("getAchievementsFromServer", true)
addEventHandler("getAchievementsFromServer", root, function(data, leaderboard, totalPlayers, currentMapRunning, achProgress, bridgesRawProgress)
	-- ReCreate Window
	if isElement(window) then
		destroyElement(window)
	end

	showCursor(true)
	guiSetInputMode("no_binds_when_editing")
	window = guiCreateWindow((1 - screenY / screenX * 0.92) / 2, 0.15, screenY / screenX * 0.92, 0.7, "Achievements", true)
	guiWindowSetSizable(window, false)
	tabPanel = guiCreateTabPanel(0, 0.05, 1, 0.88, true, window)

	-- Button
	local exitButton = guiCreateButton(0.85, 0.95, 0.15, 0.2, "Close", true, window)
	addEventHandler("onClientGUIClick", exitButton, function()
		if source == exitButton then
			showAchievements()
		end
	end )

	if not isElement(window) then
		return
	end
	if data == nil or leaderboard == nil or totalPlayers == nil then
		-- Player not logged in
		destroyElement(window)
		showCursor(false)
		return
	end

	local total, unlocked = 0, 0;
	for k, v in ipairs(data) do
		for i = 1, #data[k] do
			total = total + 1
			if data[k][i][1] == true then
				unlocked = unlocked + 1
			end
		end
	end

	receivedData = data -- Store it as this data used in tool tips that being displayed over icons

	-- Create Tabs
	tabs = {}
	gridLists = {}

	-- Create achs categories
	for k, v in ipairs(data) do
		tabs[k] = guiCreateTab(achievementsListTabs[k], tabPanel)
	end

	searchLabel = guiCreateLabel(0.025, 0.94, 0.25, 0.04, "Search by name:", true, window)
	search = guiCreateEdit(0.28, 0.945, 0.5, 0.04, searchState, true, window)

	button_AchName = guiCreateCheckBox(0.025, 0.96, 0.15, 0.04, "Achievement", true, true, window)
	button_MapName = guiCreateCheckBox(0.18, 0.96, 0.10, 0.04, "Map", true, true, window)

	addEventHandler("onClientGUIClick", button_MapName, updateSearch)
	addEventHandler("onClientGUIClick", button_AchName, updateSearch)

	if selectedTab == tabs[1] then
		guiSetVisible(button_AchName, true)
		guiSetVisible(button_MapName, false)
		guiCheckBoxSetSelected(button_AchName, true)
	else
		guiSetVisible(button_AchName, true)
		guiSetVisible(button_MapName, false)

	end

	addEventHandler("onClientGUIChanged", window, function()
		if source == search then
			if settings.type == 1 then
				loadGUI()
			elseif settings.type == 0 then
				updateSearch()
			end
		end
	end )

	loadGUI()

	-- Leaderboard
	tabs["Leaderboard"] = guiCreateTab("Leaderboard", tabPanel)
	local totalPlayers = guiCreateLabel(0.16, 0.95, 0.5, 0.5, "Total players participated: " .. totalPlayers, true, tabs["Leaderboard"])

	local grid = guiCreateGridList(0.15, 0.05, 0.70, 0.88, true, tabs["Leaderboard"])
	guiGridListAddColumn(grid, "№", 0.10)
	guiGridListAddColumn(grid, "Player", 0.65)
	guiGridListAddColumn(grid, "Completed", 0.20)

	local myName = getPlayerName(localPlayer):gsub("#%x%x%x%x%x%x", "")

	local limit = math.min(#leaderboard, 100)

	for i = 1, limit do
		local cleanName = leaderboard[i]["playername"]:gsub("#%x%x%x%x%x%x", "")
		local row = guiGridListAddRow(grid)

		guiGridListSetItemText(grid, row, 1, tostring(i), false, false)
		guiGridListSetItemText(grid, row, 2, cleanName, false, false)
		guiGridListSetItemText(grid, row, 3, leaderboard[i]["count"] .. "/" .. total, false, false)

		-- Highlight local player
		if cleanName == myName then
			guiGridListSetItemColor(grid, row, 1, 0, 255, 0)
			guiGridListSetItemColor(grid, row, 2, 0, 255, 0)
			guiGridListSetItemColor(grid, row, 3, 0, 255, 0)
		end
	end

	-- Stats
	tabs["stats"] = guiCreateTab("Stats", tabPanel)
	guiCreateLabel(0.16, 0.95, 0.5, 0.5, "Achievements unlocked: " .. unlocked .. "/" .. total, true, tabs["stats"])

	local stats = {}
	for k, v in pairs(achievementsList) do
		for i = 1, #achievementsList[k] do
			if data[k][i][1] then
				table.insert(stats, {k, i, data[k][i][4]})
			end
		end
	end

	-- Sort stats
	table.sort(stats, function(a, b)
		if a[3] > b[3] then
			return true
		end
		return false
	end )

	local grid = guiCreateGridList(0.15, 0.05, 0.70, 0.88, true, tabs["stats"])
	guiGridListAddColumn(grid, "№", 0.1)
	guiGridListAddColumn(grid, "Achievement", 0.50)
	guiGridListAddColumn(grid, "Timestamp", 0.34)

	for i = 1, #stats do
		local row = guiGridListAddRow(grid)

		guiGridListSetItemText(grid, row, 1, tostring(#stats + 1 - i), false, false)
		guiGridListSetItemText(grid, row, 2, getAchievementByGroupAndPos(stats[i][1], stats[i][2]).name, false, false)
		guiGridListSetItemText(grid, row, 3, os.date("%X —  %d.%m.%Y", stats[i][3]), false, false)
	end

	-- The Checklist
	if (currentMapRunning == "ProcedurallyGeneratedRace" or currentMapRunning == "SuperFleischbergAutos" or currentMapRunning == "SuperFleischbergAutosCollisions") and achProgress then
		-- Initialization
		local remaining = {}
		for i = 400, 611 do
			table.insert(remaining, i, i)
		end

		-- Exclude current progress
		for _, j in pairs(fromJSON(achProgress)) do
			table.remove(remaining, j)
			remaining[j] = nil
		end

		local displayTable = {}
		for i = 400, 611 do
			if remaining[i] then
				table.insert(displayTable, i)
			end
		end

		if #displayTable > 0 then
			-- Create the tabs and display the info
			tabs["checklist"] = guiCreateTab("Checklist", tabPanel)
			local str = ""
			local index = 1
			for i, k in pairs(displayTable) do
				str = str.. "" ..getVehicleNameFromModel(k).. " (" ..k.. ")"
				if index < #displayTable then
					str = str.. ", "
				else
					str = str.. "."
				end

				index = index + 1
			end

			guiSetFont(guiCreateLabel(0.05, 0.05, 0.8, 0.1, "Remaining vehicles you have to collect:", true, tabs["checklist"]), "default-bold-small")
			local list = guiCreateLabel(0.05, 0.1, 0.9, 0.9, str, true, tabs["checklist"])
			guiLabelSetHorizontalAlign(list, "left", true)
		end
	end

	-- Bridge Progress WIP
	if bridgesRawProgress then
		bridgeZones = bridgesRawProgress.zones

		tabs["bridges"] = guiCreateTab("Bridges", tabPanel)
		-- Sort LS Bridges
		local LSBridges = {}
		local totalCollectedInLS = 0
		local totalInLS = 0
		for zone, bridges in pairs(bridgeZones) do
			if string.find(zone, "Los Santos%s%p%s", 1) then
				totalInLS = totalInLS + #bridges
				local zoneName = string.gsub(zone, "Los Santos%s%p%s", "", 1)
				LSBridges[zoneName] = {total = #bridges, collected = 0}
				if bridgesRawProgress.collected then
					for _, b in ipairs(bridgesRawProgress.collected) do
						for _, zoneBridge in ipairs(bridges) do
							if b.ID == zoneBridge then
								LSBridges[zoneName].collected = LSBridges[zoneName].collected + 1
								totalCollectedInLS = totalCollectedInLS + 1
								break
							end
						end
					end
				end
				bridgeZones[zone] = nil
			end
		end

		-- Los Santos
		guiSetFont(guiCreateLabel(0.05, 0.05, 0.5, 0.2, "1. Los Santos", true, tabs["bridges"]), "default-bold-small")
		guiSetFont(guiCreateLabel(0.3, 0.05, 0.5, 0.2, totalCollectedInLS.. "/" ..totalInLS, true, tabs["bridges"]), "default-bold-small")
		local y = 1
		for LSZone, bridgesData in pairs(LSBridges) do
			guiSetFont(guiCreateLabel(0.06, 0.05 + 0.03 * y, 0.5, 0.2, "1." ..y.. " " ..LSZone, true, tabs["bridges"]), "default-bold-small")
			guiSetFont(guiCreateLabel(0.3, 0.05 + 0.03 * y, 0.5, 0.2, bridgesData.collected.. "/" ..bridgesData.total, true, tabs["bridges"]), "default-bold-small")
			y = y + 1
		end

		--y = 0
		for bridgeZoneName, bridgesTable in pairs(bridgeZones) do
			-- Name of the region
			guiSetFont(guiCreateLabel(0.05, 0.05 + 0.03 * y, 0.5, 0.2, (y - 18).. ". " ..bridgeZoneName, true, tabs["bridges"]), "default-bold-small")

			local collected = 0
			if bridgesRawProgress.collected then
				for _, b in ipairs(bridgesRawProgress.collected) do
					for _, zoneBridge in ipairs(bridgesTable) do
						if b.ID == zoneBridge then
							collected = collected + 1
							break
						end
					end
				end
			end

			guiSetFont(guiCreateLabel(0.3, 0.05 + 0.03 * y, 0.5, 0.2, collected.. "/" ..#bridgesTable, true, tabs["bridges"]), "default-bold-small")
			y = y + 1
		end
	end

	-- Settings
	tabs["settings"] = guiCreateTab("Settings", tabPanel)

	-- Display
	guiSetFont(guiCreateLabel(0.05, 0.05, 0.2, 0.1, "Display  type:", true, tabs["settings"]), "default-bold-small")
	local radio_type_icons = guiCreateRadioButton(0.3, 0.0108, 0.1, 0.1, "Icons", true, tabs["settings"])
	local radio_type_list  = guiCreateRadioButton(0.45, 0.0108, 0.1, 0.1, "Text list", true, tabs["settings"])

	-- Border
	guiSetFont(guiCreateLabel(0.05, 0.1, 0.2, 0.1, "Icons border: ", true, tabs["settings"]), "default-bold-small")
	local check_border = guiCreateCheckBox(0.3, 0.1, 0.2, 0.03, "Enable border", settings.borderEnabled == 1, true, tabs["settings"])
	local unlockedColorButton = guiCreateButton(0.5, 0.1, 0.21, 0.05, "Change Unlocked Color", true, tabs["settings"])
	local lockedColorButton = guiCreateButton(0.75, 0.1, 0.21, 0.05, "Change Locked Color", true, tabs["settings"])

	-- Achievements filters
	guiSetFont(guiCreateLabel(0.05, 0.18, 0.2, 0.1, "Filter achievements:", true, tabs["settings"]), "default-bold-small")
	local check_hide_unlocked = guiCreateCheckBox(0.3, 0.18, 0.2, 0.03, "Hide unlocked", settings.hide_unlocked == 1, true, tabs["settings"])

	-- Popup location
	guiSetFont(guiCreateLabel(0.05, 0.28, 0.2, 0.1, "Popup location:", true, tabs["settings"]), "default-bold-small")
	local info_text = guiCreateLabel(0.22, 0.28, 0.6, 0.25, "Hover over the popup, hold down the left mouse button and move the cursor to the place where you would like to place the popup.", true, tabs["settings"])
	guiLabelSetHorizontalAlign(info_text, "left", true)
	local resetPositionButton = guiCreateButton(0.82, 0.28, 0.15, 0.05, "Reset", true, tabs["settings"])

	-- Events for this GUI page
	addEventHandler("onClientGUIClick", window, function()
		if source == radio_type_icons or source == radio_type_list or source == check_hide_unlocked or source == check_border then
			-- Check display type
			if guiRadioButtonGetSelected(radio_type_icons) then
				settings.type = 0
			else
				settings.type = 1
			end

			-- Check border
			if guiCheckBoxGetSelected(check_border) then
				settings.borderEnabled = 1
			else
				settings.borderEnabled = 0
			end

			-- Check achievements filters
			if guiCheckBoxGetSelected(check_hide_unlocked) then
				settings.hide_unlocked = 1
			else
				settings.hide_unlocked = 0
			end

			-- Save settings and update GUI
			saveSettings()
			loadGUI()
		elseif source == resetPositionButton then
			settings.posX = settingsDefault.posX
			settings.posY = settingsDefault.posY
			saveSettings()
		elseif source == unlockedColorButton then
			colorPicker.constructor()
			colorPicker.openSelect("unlocked")
		elseif source == lockedColorButton then
			colorPicker.constructor()
			colorPicker.openSelect("locked")
		end
	end )

	if settings.type == 0 then
		guiRadioButtonSetSelected(radio_type_icons, true)
	else
		guiRadioButtonSetSelected(radio_type_list, true)
	end

	-- Event of changing tab
	previousTab = tabs[1]
	addEventHandler("onClientGUITabSwitched", tabPanel, function(selectedTab)
		if previousTab == tabs["settings"] then
			saveSettings()
		end

		-- Show/hide Map Name button depending on tab
		if selectedTab == tabs[1] then
    	    -- Tab 1: hide maps
    	    guiSetVisible(button_MapName, false)
    	    guiSetVisible(button_AchName, true)
    	    guiCheckBoxSetSelected(button_AchName, true)
    	    guiSetEnabled(search, true)
    	    guiSetVisible(search, true)
    	    guiSetVisible(searchLabel, true)
    	elseif selectedTab == tabs[2] or selectedTab == tabs[3] or selectedTab == tabs[4]
    	    or selectedTab == tabs[5] or selectedTab == tabs[6] or selectedTab == tabs[7] then
    	    -- Tabs 2–7: show both
    	    guiSetVisible(button_MapName, true)
    	    guiSetVisible(button_AchName, true)
    	    guiSetEnabled(search, true)
    	    guiSetVisible(search, true)
    	    guiSetVisible(searchLabel, true)
    	else
    	    -- Tabs 8+: hide everything
    	    guiSetVisible(button_MapName, false)
    	    guiSetVisible(button_AchName, false)
    	    guiSetEnabled(search, false)
    	    guiSetVisible(search, false)
    	    guiSetVisible(searchLabel, false)
    	end

		previousTab = selectedTab

		updateSearch()
		loadGUI()
	end )
end )


-- Wrapper for map display in mouse over
local function wordWrapMap(text, maxWidth)
	local wrapped, line, width = "", "", 0
	for word in text:gmatch("%S+") do
		local w = dxGetTextWidth(word) or 0
		if width + w > maxWidth then
			if wrapped ~= "" then
				wrapped = wrapped .. "\n"
			end
			wrapped = wrapped .. line
			line = word .. " "
			width = w
		else
			line = line .. word .. " "
			width = width + w
		end
	end
	wrapped = wrapped .. line
	return wrapped
end

-- The creation of tooltips
addEventHandler("onClientCursorMove", root, function(_, _, x, y)
	-- Tooltip creation
	if isElement(window) and settings.type == 0 and (guiGetText(guiGetSelectedTab(tabPanel)) ~= "Settings" and guiGetText(guiGetSelectedTab(tabPanel)) ~= "Leaderboard" and guiGetText(guiGetSelectedTab(tabPanel)) ~= "Stats" and guiGetText(guiGetSelectedTab(tabPanel)) ~= "Checklist" and guiGetText(guiGetSelectedTab(tabPanel)) ~= "Bridges") then
		local activeTab = guiGetSelectedTab(tabPanel)
		local tabWidth, tabHeight = guiGetSize(activeTab, false)
		local windowPosX, windowPosY = guiGetPosition(window, false)
		local tabPosX, tabPosY = guiGetPosition(tabPanel, false)

		tabPosX = tabPosX + windowPosX
		tabPosY = tabPosY + windowPosY

		-- Find out whats this tab actually is
		local achCategory
		for i = 1, #achievementsListTabs do
			if guiGetText(activeTab) == achievementsListTabs[i] then
				achCategory = i
				break
			end
		end

		local col, row = 1, 0
		local isCursorOverIcon = false
		for i, v in ipairs(achievementsList[achCategory]) do
			if ((settings.hide_unlocked == 1 and not receivedData[achCategory][i][1]) or (settings.hide_unlocked == 0))
			and (searchState == "" or receivedData[achCategory][i]["matched"]) then
				-- Define icon size and margin
				local iconSize = screenY * 0.07 												-- Actual icon size in px
				local iconSizeRelative = {w = iconSize / tabWidth, h = iconSize / tabHeight} 	-- Relative to window icon size
				local margin = {w = iconSizeRelative.w * 0.15, h = iconSizeRelative.h * 0.15}	-- Margine size (relative)
				local iconPosX, iconPosY = tabPosX + (margin.w + (iconSizeRelative.w + margin.w) * col - (iconSizeRelative.w + margin.w)) * tabWidth, tabPosY + (0.07 + row * (iconSizeRelative.h + margin.h)) * tabHeight

				if x >= iconPosX and x <= iconPosX + iconSize and y >= iconPosY and y <= iconPosY + iconSize then
					-- Store achievement ID of icon over the cursor
					if not tooltipID or tooltipID ~= v.ID then -- New icon
						tooltipID = v.ID
						tooltipCat = achCategory

						local achData = receivedData[tooltipCat][getAchievementPosByID(tooltipID)]
						local ach = getAchievementByID(tooltipID)

						-- State of the achievement
						local stateText
						if achData[1] then
							stateText = "Unlocked (" .. os.date("%d.%m.%Y", achData[4]) .. ")"
						else
							stateText = "Locked"
						end

						-- Map info
						local mapText = ""
						if ach.maps and #ach.maps > 0 then
							local mapTextWrapped = table.concat(ach.maps, ", ")
							mapText = "\n" .. wordWrapMap(mapTextWrapped, 500) .. "\n"
						end

						-- Text
						if ach.stages > 1 and receivedData ~= nil then
							tooltipText = ach.name .. "\n" .. ach.description .. "\n" .. mapText .. "\n" .. stateText .. "\n\nProgress: " .. achData[2] .. "/" .. ach.stages .. "\n\n" .. string.format("%.1f", achData[3]) .. "% of players got this achievement"
						else
							tooltipText = ach.name .. "\n" .. ach.description .. "\n" .. mapText .. "\n" .. stateText .. "\n\n" .. string.format("%.1f", achData[3]) .. "% of players got this achievement"
						end
					end

					-- Moves the tooltip icon with the cursor
					toolTipX, toolTipY = x, y
					isCursorOverIcon = true
					break
				end

				-- Next row of achievements
				col = col + 1
				if margin.w + (iconSizeRelative.w + margin.w) * col > 1 then
					row = row + 1
					col = 1
				end
			end
		end

		-- Hide the tooltip
		if not isCursorOverIcon then
			tooltipID = nil
		end
	end

	-- Settings
	if isElement(window) and guiGetSelectedTab(tabPanel) == tabs["settings"] and getKeyState("mouse1") and movingPopup then
		settings.posX = (x - movingPopupOffsetX) / screenY
		settings.posY = (screenY - y - movingPopupOffsetY) / screenY
	end
end )

-- Event used in the setting for moving the popup around the screen
addEventHandler("onClientClick", root, function(button, state, x, y)
	if isElement(window) and guiGetSelectedTab(tabPanel) == tabs["settings"] and button == "left" then
		if not movingPopup and state == "down" then
			-- Check position over the popup
			if x >= screenY * settings.posX and x <= screenY * settings.posX + boxSize[1] and y >= (screenY - screenY * settings.posY) and y <= (screenY - screenY * settings.posY) + boxSize[2] then
				-- store offset
				movingPopupOffsetX = x - screenY * settings.posX
				movingPopupOffsetY = screenY - y - screenY * settings.posY
				movingPopup = true
				guiSetAlpha(window, 0)
			end
		elseif movingPopup and state == "up" then
			-- finish moving
			movingPopup = false
			guiSetAlpha(window, 255)
			saveSettings()
		end
	end
end )

function wordWrap(text, maxwidth, size)
	local formattedText
	local textLine
	local linesCount = 1

	for i, v in pairs(split(text, " ")) do
		local testLine
		if not textLine then
			testLine = v
		else
			testLine = textLine .. " " .. v
		end

		if dxGetTextWidth(testLine, size, "bankgothic", false) > maxwidth then
			if not formattedText then
				formattedText = textLine .. "\n"
			else
				formattedText = formattedText .. "" .. textLine .. "\n"
			end
			textLine = v
			linesCount = linesCount + 1
		else
			if not textLine then
				textLine = v
			else
				textLine = textLine .. " " .. v
			end
		end
	end

	if not formattedText and textLine == nil then
		formattedText = text
	elseif not formattedText and textLine then
		formattedText = textLine
	elseif formattedText and textLine then
		formattedText = formattedText .. "" .. textLine
	end

	if linesCount > 2 then
		return wordWrap(text, maxwidth, size * 0.9)
	end

	return formattedText, size
end



addEvent("achs_collectedBridge", true)
addEventHandler("achs_collectedBridge", root, function(data, progress)
	if isTimer(bridgeTextEnabled) then
		killTimer(bridgeTextEnabled)
	end
	bridgeTextEnabled = setTimer(function() end, 6000, 1)
	bridgeText = data.playertotal .. " out of " .. data.total .. "\n" .. data.inzone .. " out of " .. data.totalinzone .. " in " .. data.zone
	playSoundFrontEnd(28)

	collectedBridges = progress
	if showBridges then
		toggleBridges()
		toggleBridges()
	end
end )

addEvent("achs_storeBridges", true)
addEventHandler("achs_storeBridges", root, function(data, bridgeZ, togglebridges)
	collectedBridges = data
	bridgeZones = bridgeZ
	if togglebridges then
		toggleBridges()
	end
end )

function toggleBridges()
	if not showBridges then
		if not collectedBridges then
			triggerServerEvent("achs_requestBridges", localPlayer, true)
		else
			for i, v in pairs(collectedBridges) do
				bridgesBlips[i] = createBlip(v[1], v[2], 0, 56, 2, 255, 255, 255, 255, 0, 580)
			end
			showBridges = true
		end
	else
		for i = 1, #bridgesBlips do
			destroyElement(bridgesBlips[i])
			showBridges = false
		end
	end
end
addCommandHandler("togglebridges", toggleBridges, false, false)
