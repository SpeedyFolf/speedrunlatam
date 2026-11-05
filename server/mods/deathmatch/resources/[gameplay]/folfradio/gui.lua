local radioWindow
local searchBox
local genreList
local stationList
local volumeBar
local volumeNameLabel
local volumeLabel
local stationKeys = {}
local gridListHeaderHeight = 25

for key in pairs(radioStations) do
	table.insert(stationKeys, key)
end
table.sort(stationKeys)

local function closeRadioWindow()
	if radioWindow and isElement(radioWindow) then
		destroyElement(radioWindow)
	end

	radioWindow = nil
	searchBox = nil
	genreList = nil
	stationList = nil
	volumeBar = nil
	volumeNameLabel = nil
	volumeLabel = nil
	showCursor(false)
	guiSetInputMode("allow_binds")
end

function updateRadioVolumeControl(volume)
	if not volumeBar or not isElement(volumeBar) then
		return
	end

	guiScrollBarSetScrollPosition(volumeBar, math.min(volume, 100))
	guiSetText(volumeLabel, volume .. "%")
end

local function refreshStationList()
	if not stationList or not isElement(stationList) then
		return
	end

	local searchText = guiGetText(searchBox):lower()
	local selectedGenre = guiComboBoxGetSelected(genreList)
	local genreFilter = selectedGenre >= 1 and guiComboBoxGetItemText(genreList, selectedGenre) or nil

	guiGridListClear(stationList)
	for _, key in ipairs(stationKeys) do
		local station = radioStations[key]
		local name = station.name:lower()
		local genre = station.genre:lower()
		local matchesSearch = searchText == ""
			or string.find(name, searchText, 1, true)
			or string.find(genre, searchText, 1, true)
			or string.find(key, searchText, 1, true)
		local matchesGenre = not genreFilter or station.genre == genreFilter

		if matchesSearch and matchesGenre then
			local row = guiGridListAddRow(stationList)
			guiGridListSetItemText(stationList, row, 1, station.name, false, false)
			guiGridListSetItemText(stationList, row, 2, station.genre, false, false)
			guiGridListSetItemText(stationList, row, 3, key, false, false)
		end
	end
end

local function playSelectedStation()
	local row = guiGridListGetSelectedItem(stationList)
	if row == -1 then
		outputChatBox("Select a radio station first.", 255, 150, 0)
		return
	end

	local key = guiGridListGetItemText(stationList, row, 3)
	local station = radioStations[key]
	if station then
		playRadioStream(station.url, station.name, station.genre)
	end
end

local function openRadioWindow()
	if radioWindow and isElement(radioWindow) then
		guiBringToFront(radioWindow)
		return
	end

	radioWindow = guiCreateWindow(0.15, 0.1, 0.7, 0.8, "Radio Stations", true)
	guiWindowSetSizable(radioWindow, false)

	local _, screenHeight = guiGetScreenSize()
	guiCreateLabel(0.03, 0.055, 0.08, 0.045, "Search:", true, radioWindow)
	searchBox = guiCreateEdit(0.1, 0.05, 0.52, 0.03 - 1 / screenHeight, "", true, radioWindow)
	genreList = guiCreateComboBox(0.65, 0.05, 0.32, 0.5, "All genres", true, radioWindow)
	guiComboBoxAddItem(genreList, "All genres")

	local genres = {}
	for _, station in pairs(radioStations) do
		genres[station.genre] = true
	end

	local sortedGenres = {}
	for genre in pairs(genres) do
		table.insert(sortedGenres, genre)
	end
	table.sort(sortedGenres)
	for _, genre in ipairs(sortedGenres) do
		guiComboBoxAddItem(genreList, genre)
	end
	guiComboBoxSetSelected(genreList, 0)

	stationList = guiCreateGridList(0.03, 0.13, 0.94, 0.77, true, radioWindow)
	guiGridListAddColumn(stationList, "Station", 0.31)
	guiGridListAddColumn(stationList, "Genre", 0.23)
	guiGridListAddColumn(stationList, "Key", 0.4)
	guiGridListSetSortingEnabled(stationList, true)

	local playButton = guiCreateButton(0.03, 0.92, 0.18, 0.055, "Play selected", true, radioWindow)
	local stopButton = guiCreateButton(0.22, 0.92, 0.18, 0.055, "Stop radio", true, radioWindow)
	volumeNameLabel = guiCreateLabel(0.475, 0.915, 0.12, 0.04, "Volume:", true, radioWindow)
	guiLabelSetHorizontalAlign(volumeNameLabel, "center", false)
	volumeLabel = guiCreateLabel(0.595, 0.915, 0.12, 0.04, "100%", true, radioWindow)
	guiLabelSetHorizontalAlign(volumeLabel, "center", false)
	volumeBar = guiCreateScrollBar(0.475, 0.94, 0.24, 0.035, true, true, radioWindow)
	local closeButton = guiCreateButton(0.79, 0.92, 0.18, 0.055, "Close", true, radioWindow)

	guiScrollBarSetScrollPosition(volumeBar, math.min(currentRadioVolume, 100))
	guiSetText(volumeLabel, currentRadioVolume .. "%")

	addEventHandler("onClientGUIChanged", searchBox, refreshStationList, false)
	addEventHandler("onClientGUIComboBoxAccepted", genreList, refreshStationList, false)
	addEventHandler("onClientGUIScroll", volumeBar, function()
		local volume = math.floor(guiScrollBarGetScrollPosition(volumeBar) + 0.5)
		setRadioVolume(volume)
	end, false)
	addEventHandler("onClientGUIClick", playButton, playSelectedStation, false)
	addEventHandler("onClientGUIClick", stopButton, stopRadioStream, false)
	addEventHandler("onClientGUIClick", closeButton, closeRadioWindow, false)
	addEventHandler("onClientGUIDoubleClick", stationList, function(button, state, absoluteX, absoluteY)
		local _, windowY = guiGetPosition(radioWindow, false)
		local _, listY = guiGetPosition(stationList, false)
		local _, listHeight = guiGetSize(stationList, false)

		if button == "left" and absoluteY >= windowY + listY + gridListHeaderHeight and absoluteY <= windowY + listY + listHeight then
			playSelectedStation()
		end
	end, false)

	refreshStationList()
	showCursor(true)
	guiSetInputMode("no_binds_when_editing")
	guiBringToFront(searchBox)
end

function toggleRadioWindow()
	if radioWindow and isElement(radioWindow) then
		closeRadioWindow()
	else
		openRadioWindow()
	end
end

addCommandHandler("radios", toggleRadioWindow, false)
addEventHandler("onClientResourceStop", resourceRoot, closeRadioWindow)
