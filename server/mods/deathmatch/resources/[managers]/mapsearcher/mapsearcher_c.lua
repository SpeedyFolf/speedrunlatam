local mapSearcherWindow = nil
local g_mapsTable = {}
local totalMapCountLabel = nil

-- Cols in UI
local COL_RACETYPE = 1
local COL_NAME = 2
local COL_AUTHOR = 3
local COL_RATING = 4
local COL_LASTPLAYED = 5
local COL_TIMES = 6
local COL_RESNAME = 7

-- State of the window
local window_state = {
	text = "",
	mapname = true,
	author = false
}

-- Function that receives data from the server
addEvent("mapsearcher_getmaps_c", true)
addEventHandler("mapsearcher_getmaps_c", localPlayer, function(data)
	if data then g_mapsTable = data end
	guiChanged()
end )

function closeWindow()
	if not mapSearcherWindow then return end

	-- Closes window
	window_state.text = guiGetText(MapListSearch)
	window_state.mapname = guiRadioButtonGetSelected(radio_MapName)
	window_state.author = guiRadioButtonGetSelected(radio_Author)

	destroyElement(mapSearcherWindow)
	mapSearcherWindow = nil
	totalMapCountLabel = nil
	guiSetInputMode("allow_binds")
	showCursor(false)
end

function guiChanged()
	guiGridListClear(MapList)

	local text = string.lower(guiGetText(MapListSearch))
	if text == "" then
		-- Empty request, show all maps
		for id, map in pairs(g_mapsTable) do
			local row = guiGridListAddRow(MapList)
			guiGridListSetItemText(MapList, row, COL_RACETYPE, map.racetype, false, false)
			guiGridListSetItemText(MapList, row, COL_NAME, map.name, false, false)
			guiGridListSetItemText(MapList, row, COL_AUTHOR, map.author, false, false)
			guiGridListSetItemText(MapList, row, COL_RATING, map.rating, false, true)
			guiGridListSetItemText(MapList, row, COL_LASTPLAYED, map.lastplayed, false, true)
			guiGridListSetItemText(MapList, row, COL_TIMES, map.timesplayed, false, true)
			guiGridListSetItemText(MapList, row, COL_RESNAME, map.resname, false, false)
		end
	else
		-- Show found maps
		for id, map in pairs(g_mapsTable) do
			local stringToCompare = ""
			if guiRadioButtonGetSelected(radio_MapName) then stringToCompare = string.lower(map.name.. " " ..map.resname)
			elseif guiRadioButtonGetSelected(radio_Author) then stringToCompare = string.lower(map.author) end

			if string.find(stringToCompare, text, 1, true) then
				local row = guiGridListAddRow(MapList)
				guiGridListSetItemText(MapList, row, COL_RACETYPE, map.racetype, false, false)
				guiGridListSetItemText(MapList, row, COL_NAME, map.name, false, false)
				guiGridListSetItemText(MapList, row, COL_AUTHOR, map.author, false, false)
				guiGridListSetItemText(MapList, row, COL_RATING, map.rating, false, true)
				guiGridListSetItemText(MapList, row, COL_LASTPLAYED, map.lastplayed, false, true)
				guiGridListSetItemText(MapList, row, COL_TIMES, map.timesplayed, false, true)
				guiGridListSetItemText(MapList, row, COL_RESNAME, map.resname, false, false)
			end
		end
	end

	if totalMapCountLabel and isElement(totalMapCountLabel) then
		guiSetText(totalMapCountLabel, "Total Map Count: " .. tostring(#g_mapsTable))
	end

	guiSetInputMode("no_binds_when_editing")
end

-- Command for Map Searcher
addCommandHandler("maps", function(player, command)
	if mapSearcherWindow and guiGetVisible(mapSearcherWindow) then
		closeWindow()
	else
		-- Opens window
		if mapSearcherWindow == nil then
			local sx, sy = guiGetScreenSize()
			mapSearcherWindow = guiCreateWindow (sx / 2 - 310, sy / 2 - 260, sx / 2, 620, "", false)
			guiWindowSetSizable(mapSearcherWindow, false)

			guiSetText(mapSearcherWindow, "Map Searcher by Discoordination")

			guiCreateLabel(0.03, 0.06, 0.1, 0.04, "Search: ", true, mapSearcherWindow)
			MapListSearch = guiCreateEdit(0.13, 0.06, 0.84, 0.04, window_state.text, true, mapSearcherWindow)

			guiCreateLabel(0.03, 0.11, 0.1, 0.04, "Search by: ", true, mapSearcherWindow)
			radio_MapName = guiCreateRadioButton(0.15, 0.105, 0.15, 0.04, "Map Name", true, mapSearcherWindow)
			radio_Author = guiCreateRadioButton(0.30, 0.105, 0.15, 0.04, "Author", true, mapSearcherWindow)

			totalMapCountLabel = guiCreateLabel(0.50, 0.11, 0.47, 0.04, "Total Map Count: " .. tostring(#g_mapsTable), true, mapSearcherWindow)
			guiLabelSetHorizontalAlign(totalMapCountLabel, "right")

			guiRadioButtonSetSelected(radio_MapName, window_state.mapname)
			guiRadioButtonSetSelected(radio_Author, window_state.author)

			MapList = guiCreateGridList(0.03, 0.15, 0.94, 0.79, true, mapSearcherWindow)

			guiGridListAddColumn(MapList, "Type", 0.06)
			guiGridListAddColumn(MapList, "Map Name", 0.36)

			guiGridListAddColumn(MapList, "Author", 0.24)
			guiGridListAddColumn(MapList, "Rating", 0.1)
			guiGridListAddColumn(MapList, "Last Played", 0.15)
			guiGridListAddColumn(MapList, "Times Played", 0.15)
			guiGridListAddColumn(MapList, "Resource Name", 0.36)

			local exitButton = guiCreateButton(0.83, 0.953, 0.14, 0.04, "Close", true, mapSearcherWindow)

			addEventHandler("onClientGUIClick", radio_MapName, function(button, state)
				if button == "left" and state == "up" then guiChanged() end
			end, false )

			addEventHandler("onClientGUIClick", radio_Author, function(button, state)
				if button == "left" and state == "up" then guiChanged() end
			end, false )

			addEventHandler("onClientGUIChanged", mapSearcherWindow, guiChanged)

			addEventHandler("onClientGUIDoubleClick", MapList, function(button, state)
				if button ~= "left" or state ~= "up" then return end

				local mapResName = guiGridListGetItemText(MapList, guiGridListGetSelectedItem(MapList), COL_RESNAME)
				if mapResName == "" then return end

				triggerServerEvent("mapsearcher_votemap", localPlayer, mapResName)
			end, false )

			addEventHandler("onClientGUIClick", exitButton, function(button, state)
				if button == "left" and state == "up" then
					if mapSearcherWindow and guiGetVisible(mapSearcherWindow) then closeWindow() end
				end
			end, false )

			-- Request maps from the server when menu opened first time
			if #g_mapsTable == 0 then triggerServerEvent("mapsearcher_getmaps", localPlayer)
			else guiChanged() end
		end

		guiSetVisible(mapSearcherWindow, true)
		showCursor(true)
	end
end )
