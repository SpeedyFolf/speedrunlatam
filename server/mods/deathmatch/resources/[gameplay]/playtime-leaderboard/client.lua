local win = nil
local grid = nil
local searchEdit = nil

-- Store data here so we can filter it without asking the server again
local fullLeaderboardData = {}
local myAccountName = ""

-- Helper function to fill the grid based on a (potentially filtered) list
function populateGrid(dataList)
	guiGridListClear(grid)
	guiSetProperty(grid, "ConnectItems", "False") -- Optimization start

	for i, entry in ipairs(dataList) do
		local row = guiGridListAddRow(grid)

		-- Rank, Name, Time
		guiGridListSetItemText(grid, row, 1, tostring(entry.originalRank or i), false, true)
		guiGridListSetItemText(grid, row, 2, entry.name, false, false)
		guiGridListSetItemText(grid, row, 3, string.format("%dh %dm", entry.hours, entry.mins), false, false)

		-- HIGHLIGHT: If this row matches my account name, turn it GREEN
		if entry.name == myAccountName then
			for col = 1, 3 do
				guiGridListSetItemColor(grid, row, col, 0, 255, 0)
			end
		end
	end

	guiSetProperty(grid, "ConnectItems", "True") -- Optimization end
end

function createPlaytimeGUI()
	if isElement(win) then
		destroyElement(win)
		showCursor(false)
		win = nil
		return
	end

	local sw, sh = guiGetScreenSize()
	local w, h = 500, 600
	local x, y = (sw - w) / 2, (sh - h) / 2

	win = guiCreateWindow(x, y, w, h, "Player Playtime Rankings", false)
	guiWindowSetSizable(win, false)

	-- SEARCH BAR
	guiCreateLabel(0.02, 0.05, 0.2, 0.05, "Search Name:", true, win)
	searchEdit = guiCreateEdit(0.22, 0.045, 0.76, 0.045, "", true, win)

	-- GRIDLIST
	grid = guiCreateGridList(0.02, 0.105, 0.96, 0.78, true, win)
	guiGridListAddColumn(grid, "Rank", 0.15)
	guiGridListAddColumn(grid, "Name", 0.45)
	guiGridListAddColumn(grid, "Time Played", 0.35)

	-- CLOSE BUTTON
	local closeBtn = guiCreateButton(0.02, 0.90, 0.96, 0.083, "Close", true, win)

	-- Event: Close Button
	addEventHandler("onClientGUIClick", closeBtn, function()
		destroyElement(win)
		showCursor(false)
		win = nil
	end, false )

	-- Event: Typing in Search Bar
	addEventHandler("onClientGUIChanged", searchEdit, function()
		local text = guiGetText(source):lower()

		if text == "" then
			-- If empty, show full list
			populateGrid(fullLeaderboardData)
		else
			-- Create a filtered list
			local filtered = {}
			for i, entry in ipairs(fullLeaderboardData) do
				-- Check if name contains the typed text
				if string.find(entry.name:lower(), text, 1, true) then
					-- Preserve the original rank so #1 doesn't become #1 in a filtered list of 2 people
					entry.originalRank = i
					table.insert(filtered, entry)
				end
			end
			populateGrid(filtered)
		end
	end, false )

	showCursor(true)

	-- Disable binds while typing/the input box is focused
	guiSetInputMode("no_binds_when_editing")

	-- Request data from server
	triggerServerEvent("requestPlaytimeData", localPlayer)
end
addCommandHandler("playtime", createPlaytimeGUI, false)

addEvent("receivePlaytimeData", true)
addEventHandler("receivePlaytimeData", root, function(data, accName)
	if not isElement(grid) then
		return
	end

	fullLeaderboardData = data
	myAccountName = accName

	populateGrid(fullLeaderboardData)
end )
