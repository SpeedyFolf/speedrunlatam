local _window
local _closeButton
local _searchBox
local _tabPanel
local _tabs = {}

local _gridListMain
local _gridListPlayers = {}
local _gridListMapsAll
local _gridListMaps = {}

local _cachedMainData = nil
local _cachedMapsData = nil

function toggleWindow()
	if _window and guiGetVisible(_window) then
		closeWindow()
	else
		openWindow()
	end
end
addCommandHandler("globalleaderboards", toggleWindow, false, false)
addCommandHandler("gldbs", toggleWindow, false, false)
addCommandHandler("gldb", toggleWindow, false, false)
addCommandHandler("glbs", toggleWindow, false, false)
addCommandHandler("glb", toggleWindow, false, false)

function closeWindow()
	if _window and isElement(_window) then
		guiGridListClear(_gridListMain)
		destroyElement(_gridListMain)
		for i = #_tabs, 1, -1 do
			destroyElement(_tabs[i])
		end
		for i, v in pairs(_gridListPlayers) do
			guiGridListClear(v)
			destroyElement(v)
			_gridListPlayers[i] = nil
		end
		for i, v in pairs(_gridListMaps) do
			guiGridListClear(v)
			destroyElement(v)
			_gridListMaps[i] = nil
		end

		if _searchBox and isElement(_searchBox) then
			destroyElement(_searchBox)
			_searchBox = nil
		end

		destroyElement(_tabPanel)
		destroyElement(_closeButton)
		destroyElement(_window)
		_window = nil
		showCursor(false)

		-- Revert the input mode back to normal
		guiSetInputMode("allow_binds")
	end
end

function openWindow()
	if isElement(_window) then
		closeWindow()
	end

	_window = guiCreateWindow(.1, .1, .8, .8, "Global Leaderboards", true)

	guiWindowSetSizable(_window, false)

	_tabPanel = guiCreateTabPanel(0, 0.09, 1, 0.91, true, _window)

	_closeButton = guiCreateButton(0.95, 0.03, 0.05, 0.05, "X", true, _window)
	addEventHandler("onClientGUIClick", _closeButton, function(button)
		if button == "left" then
			closeWindow()
		end
	end, false )

	_searchBox = guiCreateEdit(0.74, 0.03, 0.20, 0.05, "", true, _window)
	addEventHandler("onClientGUIChanged", _searchBox, onSearchBoxChanged, false)

	-- Prevent keybinds from firing when typing in the search box
	guiSetInputMode("no_binds_when_editing")

	guiBringToFront(_closeButton)
	guiBringToFront(_searchBox)

	_tabs = {}

	createMainList()
	createMapsList()
	addPlayerTab(getPlayerName(localPlayer))

	showCursor(true)
end

-- Handles real-time filtering when the player types
function onSearchBoxChanged()
	local searchText = guiGetText(_searchBox):lower()

	-- Filter Main Leaderboard
	if _cachedMainData then
		guiGridListClear(_gridListMain)
		if searchText == "" then
			displayMainData(_cachedMainData)
		else
			local filteredMain = {}
			for _, d in ipairs(_cachedMainData) do
				if string.find(d.playerName:lower(), searchText, 1, true) then
					table.insert(filteredMain, d)
				end
			end
			displayMainData(filteredMain)
		end
	end

	-- Filter Maps Data
	if _cachedMapsData then
		guiGridListClear(_gridListMapsAll)
		if searchText == "" then
			displayMapsData(_cachedMapsData)
		else
			local filteredMaps = {}
			for _, d in ipairs(_cachedMapsData) do
				if string.find(d.mapName:lower(), searchText, 1, true) then
					table.insert(filteredMaps, d)
				end
			end
			displayMapsData(filteredMaps)
		end
	end
end

function createMainList()
	_tabs["main"] = guiCreateTab("Leaderboard", _tabPanel)

	_gridListMain = guiCreateGridList(.02, .01, .96, .96, true, _tabs["main"])
	guiGridListAddColumn(_gridListMain, "Rank", .05)
	guiGridListAddColumn(_gridListMain, "Player", .2)
	guiGridListAddColumn(_gridListMain, "▤", .01)
	guiGridListAddColumn(_gridListMain, "Total Time", .1)
	guiGridListAddColumn(_gridListMain, "Top 1", .03)
	guiGridListAddColumn(_gridListMain, "Top 2", .03)
	guiGridListAddColumn(_gridListMain, "Top 3", .03)
	guiGridListAddColumn(_gridListMain, "Top 11", .03)
	guiGridListAddColumn(_gridListMain, "Ranked Maps", .05)
	guiGridListAddColumn(_gridListMain, "Unranked Maps", .06)
	guiGridListAddColumn(_gridListMain, "Sum of All Places", .07)

	if _cachedMainData then
		displayMainData(_cachedMainData)
	else
		triggerServerEvent("requestMainData", localPlayer)
	end

	addEventHandler("onClientGUIDoubleClick", _gridListMain, function(button)
		if (button ~= "left") then return end

		local selectedRow = guiGridListGetSelectedItem(_gridListMain)
		if not selectedRow or selectedRow == -1 then return end

		local playerName = guiGridListGetItemText(_gridListMain, selectedRow, 2)
		if not playerName or playerName == "" then return end

		addPlayerTab(playerName)
	end, false )
end

addEvent("sendMainDataToClient", true)
addEventHandler("sendMainDataToClient", resourceRoot, function(data)
	if data then
		-- Cache original ranks so they don't break during filtering
		for i, d in ipairs(data) do
			d.originalRank = i - 1
		end
		_cachedMainData = data
	end
	if not _window then return end
	guiGridListClear(_gridListMain)
	displayMainData(data)
end )

function displayMainData(data)
	for i,d in ipairs(data) do
		local row = guiGridListAddRow(_gridListMain,
			d.originalRank or (i - 1), -- Uses cached original rank
			d["playerName"],
			d["totalTime"],	-- Sorting column
			formatTime(d["totalTime"]),
			d["top1"],
			d["top2"],
			d["top3"],
			d["top11"],
			d["ranked"],
			d["unranked"],
			d["totalRankScore"]
		)
		if (d.playerName == getPlayerName(localPlayer)) then
			for col = 1, 11 do
				guiGridListSetItemColor(_gridListMain, row, col, 52, 255, 52 )
			end
		elseif (d.playerName == BEST_PLAYER_NAME or d.playerName == WORST_PLAYER_NAME) then
			for col = 1, 11 do
				guiGridListSetItemColor(_gridListMain, row, col, 196, 196, 196 )
			end
		else
			guiGridListSetItemColor(_gridListMain, row, 5, 255-(255-255)/4, 255-(255-215)/4, 255-(255-0)/4 )
			guiGridListSetItemColor(_gridListMain, row, 6, 255-(255-192)/4, 255-(255-192)/4, 255-(255-192)/4 )
			guiGridListSetItemColor(_gridListMain, row, 7, 255-(255-205)/4, 255-(255-127)/4, 255-(255-50)/4 )
		end
		guiGridListSetItemColor(_gridListMain, row, 3, 0, 0, 0, 0)
	end
end

function createMapsList()
	_tabs["mapsAll"] = guiCreateTab("Maps", _tabPanel)

	_gridListMapsAll = guiCreateGridList(.02, .01, .96, .96, true, _tabs["mapsAll"])
	guiGridListAddColumn(_gridListMapsAll, "Map Name", .2)
	guiGridListAddColumn(_gridListMapsAll, "▤", .01)
	guiGridListAddColumn(_gridListMapsAll, "Top Time", .07)
	guiGridListAddColumn(_gridListMapsAll, "Date", .14)
	guiGridListAddColumn(_gridListMapsAll, "▤", .01)
	guiGridListAddColumn(_gridListMapsAll, "Average Time", .07)
	guiGridListAddColumn(_gridListMapsAll, "Player Count", .05)
	guiGridListAddColumn(_gridListMapsAll, "▤", .01)
	guiGridListAddColumn(_gridListMapsAll, "Your Time", .07)
	guiGridListAddColumn(_gridListMapsAll, "Date", .14)
	guiGridListAddColumn(_gridListMapsAll, "Rank", .03)

	if (_cachedMapsData) then
		displayMapsData(_cachedMapsData)
	else
		triggerServerEvent("requestMapsData", localPlayer)
	end

	addEventHandler("onClientGUIDoubleClick", _gridListMapsAll, function(button)
		if (button ~= "left") then return end

		local selectedRow = guiGridListGetSelectedItem(_gridListMapsAll)
		if not selectedRow or selectedRow == -1 then return end

		local mapName = guiGridListGetItemText(_gridListMapsAll, selectedRow, 1)
		if not mapName or mapName == "" then return end

		addMapTab(mapName)
	end, false )
end

addEvent("sendMapsDataToClient", true)
addEventHandler("sendMapsDataToClient", resourceRoot, function(data)
	if not _window then return end
	if data then
		_cachedMapsData = data
	end
	guiGridListClear(_gridListMapsAll)
	displayMapsData(data)
end )

function displayMapsData(data)
	for i,d in ipairs(data) do
		local row = guiGridListAddRow(_gridListMapsAll,
			d["mapName"],
			d["topTime"], -- Sorting column
			formatTime(d["topTime"]),
			formatDate(d["topTimeDate"]),
			d["avgTime"],	-- Sorting column
			formatTime(d["avgTime"]),
			d["playerCount"],
			d["yourTime"] or 0, -- Sorting column
			formatTime(d["yourTime"]) or "None",
			formatDate(d["yourTimeDate"]) or "N/A",
			d["yourRank"]
		)
		guiGridListSetItemColor(_gridListMapsAll, row, 2, 0, 0, 0, 0)
		guiGridListSetItemColor(_gridListMapsAll, row, 5, 0, 0, 0, 0)
		guiGridListSetItemColor(_gridListMapsAll, row, 8, 0, 0, 0, 0)
	end
end

function addPlayerTab(name)
	local tabId = "Player:"..name
	if (_tabs[tabId]) then return end
	_tabs[tabId] = guiCreateTab("Player: "..name, _tabPanel);
	local gridList = guiCreateGridList(.02, .01, .96, .96, true, _tabs[tabId])
	_gridListPlayers[tabId] = gridList
	guiGridListAddColumn(gridList, "Map", .2)
	guiGridListAddColumn(gridList, "Rank", .05)
	guiGridListAddColumn(gridList, "Total Finishers", .06)
	guiGridListAddColumn(gridList, "Percentile", .05)
	guiGridListAddColumn(gridList, "▤", .01)
	guiGridListAddColumn(gridList, "Time", .07)
	guiGridListAddColumn(gridList, "▤", .01)
	guiGridListAddColumn(gridList, "Delta", .07)
	guiGridListAddColumn(gridList, "▤", .01)
	guiGridListAddColumn(gridList, "Delta %", .05)
	guiGridListAddColumn(gridList, "Date", .15)

	triggerServerEvent("requestPlayerDataFromServer", localPlayer, name)

	addEventHandler("onClientGUIDoubleClick", _gridListPlayers[tabId], function(button)
		if (button ~= "left") then return end

		local selectedRow = guiGridListGetSelectedItem(_gridListPlayers[tabId])
		if not selectedRow or selectedRow == -1 then return end

		local mapName = guiGridListGetItemText(_gridListPlayers[tabId], selectedRow, 1)
		if not mapName or mapName == "" then return end

		addMapTab(mapName)
	end, false )
end

addEvent("sendPlayerDataToClient", true)
addEventHandler("sendPlayerDataToClient", resourceRoot, function(playerName, data)
	if not _window then return end
	local tabId = "Player:"..playerName
	for _,d in pairs(data) do
		local delta = math.abs(d.topTime - d.bestTime)
		local deltaPercent = math.floor((delta/d.topTime)*100)
		local row = guiGridListAddRow(_gridListPlayers[tabId],
			d.mapName,
			d.rank,
			d.totalFinishers,
			math.floor((d.rank-1) / d.totalFinishers * 100 + 1),
			d.bestTime,	-- sort column
			formatTime(d.bestTime),
			delta,	-- sort column
			"+"..formatTime(delta),
			deltaPercent,	-- sort column
			"+"..deltaPercent.."%",
			formatDate(d.dateRecorded)
		)
		guiGridListSetItemColor(_gridListPlayers[tabId], row, 5, 0, 0, 0, 0 )
		guiGridListSetItemColor(_gridListPlayers[tabId], row, 7, 0, 0, 0, 0 )
		guiGridListSetItemColor(_gridListPlayers[tabId], row, 9, 0, 0, 0, 0 )
	end
end )

function addMapTab(map)
	local tabId = "Map:"..map
	if (_tabs[tabId]) then return end
	_tabs[tabId] = guiCreateTab("Map: "..map, _tabPanel);
	local gridList = guiCreateGridList(.02, .01, .96, .96, true, _tabs[tabId])
	_gridListMaps[tabId] = gridList
	guiGridListAddColumn(gridList, "Rank", .05)
	guiGridListAddColumn(gridList, "Player", .2)
	guiGridListAddColumn(gridList, "Time", .1)
	guiGridListAddColumn(gridList, "Date", .15)

	triggerServerEvent("requestMapDataFromServer", localPlayer, map)

	addEventHandler("onClientGUIDoubleClick", _gridListMaps[tabId], function(button)
		if (button ~= "left") then return end

		local selectedRow = guiGridListGetSelectedItem(_gridListMaps[tabId])
		if not selectedRow or selectedRow == -1 then return end

		local playerName = guiGridListGetItemText(_gridListMaps[tabId], selectedRow, 2)
		if not playerName or playerName == "" then return end

		addPlayerTab(playerName)
	end, false )
end

addEvent("sendMapDataToClient", true)
addEventHandler("sendMapDataToClient", resourceRoot, function(mapName, data)
	if not _window then return end
	local tabId = "Map:"..mapName
	if not data then
		guiGridListAddRow(_gridListMaps[tabId], "", "Still working")
		guiGridListAddRow(_gridListMaps[tabId], "", "Check back later")
		return
	end
	for i,d in pairs(data) do
		local row = guiGridListAddRow(_gridListMaps[tabId],
			i,
			d.playerName,
			formatTime(d.bestTime),
			formatDate(d.dateRecorded)
		)

		if (d.playerName == getPlayerName(localPlayer)) then
			for col = 1, 4 do
				guiGridListSetItemColor(_gridListMaps[tabId], row, col, 52, 255, 52 )
			end
		end
	end
end )

function formatDate(d)
	if (not d) then
		return false
	end
	time = getRealTime(d)
	return string.format("%04d-%02d-%02d %02d:%02d:%02d", time.year + 1900, time.month + 1, time.monthday, time.hour, time.minute, time.second)
end

function formatTime(t)
	if (not t) then
		return false
	end
	local sign = ""
	if t < 0 then
		t = math.abs(t)
		sign = "-"
	end
	local ms = t % 1000
	local s = t/1000
	local m = s/60
	local h = m/60
	s = s % 60
	m = m % 60
	h = math.floor(h)
	m = math.floor(m)
	s = math.floor(s)
	-- return sign..string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
	if h == 0 then
		return sign..string.format("%01d:%02d.%03d", m, s, ms)
	else
		return sign..string.format("%01d:%02d:%02d.%03d", h, m, s, ms)
	end
end
