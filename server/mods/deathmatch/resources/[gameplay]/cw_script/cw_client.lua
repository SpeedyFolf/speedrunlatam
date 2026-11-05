local screenW, screenH = guiGetScreenSize()
local text_offset = 20
local teams = {}
local tags = {}
local c_round = 0
local m_round = 0
local f_round = false
local team_choosen = false
local isAdmin = false
local compact = false
local mode = "main"
local modeMessagesEnabled = false
local isWarEndedClient = false
local warActive = false
local ffaActive = false
local carbonActive = false
local margin = math.floor(10 * (screenW / 1920))
local showCountryFlags = true

local function toboolean(value)
	if value == nil then return nil end
	if type(value) == "boolean" then return value end

	local text = string.lower(tostring(value))
	if text == "true" then return true end
	if text == "false" then return false end
	return nil
end

-- Server will broadcast the active setting; listen for it and apply
addEvent("onCwShowCountries", true)
addEventHandler("onCwShowCountries", resourceRoot, function(value)
	if type(value) == "boolean" then
		showCountryFlags = value
	else
		local v = toboolean(value)
		showCountryFlags = v or false
	end
end)

local playerTitleCache = {}
local cachedT1Players = {}
local cachedT2Players = {}

local cachedT1c = "#bababa"
local cachedT2c = "#00ff00"
local roundStringCache = ""
local t1ScoreStrCache = "0"
local t2ScoreStrCache = "0"

local function repopulateAndSortCache()
	if isElement(teams[1]) then
		cachedT1Players = getPlayersInTeam(teams[1]) or {}
		table.sort(cachedT1Players, function(a, b) return (tonumber(getElementData(a, 'Score')) or 0) > (tonumber(getElementData(b, 'Score')) or 0) end)
		t1ScoreStrCache = tostring(getElementData(teams[1], 'Score') or 0)
	end
	if isElement(teams[2]) then
		cachedT2Players = getPlayersInTeam(teams[2]) or {}
		table.sort(cachedT2Players, function(a, b) return (tonumber(getElementData(a, 'Score')) or 0) > (tonumber(getElementData(b, 'Score')) or 0) end)
		t2ScoreStrCache = tostring(getElementData(teams[2], 'Score') or 0)
	end
end
setTimer(repopulateAndSortCache, 500, 0)

addEventHandler("onClientPlayerJoin", root, function()
	-- Refresh teams list
	setTimer(repopulateAndSortCache, 500, 1)
end)
addEventHandler("onClientPlayerQuit", root, repopulateAndSortCache)

local rowCount = 15
local rowHeight = math.floor(25 * (screenH / 1080))
local windowSizeX, windowSizeY = math.floor(250 * (screenW / 1920)), math.floor(rowHeight) * rowCount
local wX, wY = screenW - windowSizeX - 20, (screenH - windowSizeY) / 2

local fSize = screenH/1080
local fBold = dxCreateFont("fonts/Roboto-Bold.ttf", 9 * fSize, cleartype) or "default-bold"
local fReg = dxCreateFont("fonts/Roboto-Medium.ttf", 9 * fSize, cleartype) or "default"

local nickWidth = 160 * (screenW/1920)
local rankWidth = 40 * (screenW/1920)
local ptsWidth = 50 * (screenW/1920)
local flagWidth = 16 * (screenW/1920)
local flagHeight = 11 * (screenH/1080)


function serverCall(funcname, ...)
	local arg = { ... }
	if (arg[1]) then
		for key, value in next, arg do
			if (type(value) == "number") then arg[key] = tostring(value) end
		end
	end
	triggerServerEvent("onClientCallsServerFunction", resourceRoot , funcname, unpack(arg))
end

local allowedClientCalls = {
	["updateFFAState"] = true, ["updateCarbonState"] = true, ["updateTeamData"] = true,
	["updateTagData"] = true, ["updateRoundData"] = true, ["createGUI"] = true,
	["updateWarActive"] = true, ["updateAdminInfo"] = true, ["updateWarEndedClient"] = true,
	["updateAdminPanelText"] = true
}

function clientCall(funcname, ...)
	local arg = { ... }
	if (arg[1]) then
		for key, value in next, arg do arg[key] = tonumber(value) or value end
	end

	if type(funcname) == 'string' and allowedClientCalls[funcname] then
		if _G and type(_G[funcname]) == 'function' then
			pcall(_G[funcname], unpack(arg))
			return
		end
	end
	outputDebugString("clientCall: unsafe or inexistent function '"..tostring(funcname).."' blocked!")
end
addEvent("onServerCallsClientFunction", true)
addEventHandler("onServerCallsClientFunction", resourceRoot, clientCall)

addEvent("onSpectateRequest", true)
addEventHandler("onSpectateRequest", root, function()
	local team = getPlayerTeam(localPlayer)
	if team and getTeamName(team) == "Spectators" then
		setElementData(localPlayer, "state", "spectating")
	end
end)

local isWarEndedClient = false

function updateWarEndedClient(state)
	isWarEndedClient = state
end

function updateWarActive(state)
	warActive = state
	if not warActive then
		modeMessagesEnabled = false
		if isElement(c_window) then
			guiSetVisible(c_window, false)
		end
		-- Force correct cursor state: show if admin panel is visible, hide otherwise
		if isElement(a_window) and guiGetVisible(a_window) then
			showCursor(true)
			setTimer(function()
				if isElement(a_window) and guiGetVisible(a_window) then
					showCursor(true)
				end
			end, 100, 1)
		else
			showCursor(false)
		end
	else
		modeMessagesEnabled = true
		mode = "main"
	end
end

function updateFFAState(state)
	ffaActive = state
	-- Refresh the admin panel, if open, to update the captain/button lock
	if isElement(a_window) and guiGetVisible(a_window) then
		createAdminGUI()
		guiSetVisible(a_window, true)
		showCursor(true)
	end
end

function updateCarbonState(state)
	carbonActive = state
	-- Refresh the panel if open
	if isElement(a_window) and guiGetVisible(a_window) then
		createAdminGUI()
		guiSetVisible(a_window, true)
		showCursor(true)
	end
end

function dxDrawRoundedRectangle(x, y, width, height, radius, color, postGUI, subPixelPositioning)
	dxDrawRectangle(x+radius, y+radius, width-(radius*2), height-(radius*2), color, postGUI, subPixelPositioning)
	dxDrawCircle(x+radius, y+radius, radius, 180, 270, color, color, 16, 1, postGUI)
	dxDrawCircle(x+radius, (y+height)-radius, radius, 90, 180, color, color, 16, 1, postGUI)
	dxDrawCircle((x+width)-radius, (y+height)-radius, radius, 0, 90, color, color, 16, 1, postGUI)
	dxDrawCircle((x+width)-radius, y+radius, radius, 270, 360, color, color, 16, 1, postGUI)
	dxDrawRectangle(x, y+radius, radius, height-(radius*2), color, postGUI, subPixelPositioning)
	dxDrawRectangle(x+radius, y+height-radius, width-(radius*2), radius, color, postGUI, subPixelPositioning)
	dxDrawRectangle(x+width-radius, y+radius, radius, height-(radius*2), color, postGUI, subPixelPositioning)
	dxDrawRectangle(x+radius, y, width-(radius*2), radius, color, postGUI, subPixelPositioning)
end

function dxDrawBottomRoundedRectangle(x, y, width, height, radius, color, postGUI, subPixelPositioning)
	dxDrawRectangle(x+radius, y+radius, width-(radius*2), height-(radius*2), color, postGUI, subPixelPositioning)
	dxDrawCircle(x+radius, (y+height)-radius, radius, 90, 180, color, color, 16, 1, postGUI)
	dxDrawCircle((x+width)-radius, (y+height)-radius, radius, 0, 90, color, color, 16, 1, postGUI)
	dxDrawRectangle(x, y, radius, height-(radius), color, postGUI, subPixelPositioning)
	dxDrawRectangle(x+radius, y+height-radius, width-(radius*2), radius, color, postGUI, subPixelPositioning)
	dxDrawRectangle(x+width-radius, y, radius, height-(radius), color, postGUI, subPixelPositioning)
	dxDrawRectangle(x+radius, y, width-(radius*2), radius, color, postGUI, subPixelPositioning)
end

addEvent("syncScore", true)
addEventHandler("syncScore", root, function(newScore)
	setElementData(source, 'Score', newScore, false)
	repopulateAndSortCache()
end)

addEvent("syncTeamScore", true)
addEventHandler("syncTeamScore", root, function(newScore)
	setElementData(source, 'Score', newScore, false)
end)

function getPrefix(number)
	local n = number % 10
	if number >= 11 and number <= 13 then return 'th' end
	if n == 1 then return 'st' end
	if n == 2 then return 'nd' end
	if n == 3 then return 'rd' end
	return 'th'
end

local flagCache = {}

local function drawRows(pList, startRow, tr, tg, tb, maxRows)
	local drawnIndex = 0
	for _, player in ipairs(pList) do
		if isElement(player) and getElementType(player) == "player" then
			drawnIndex = drawnIndex + 1
			if maxRows and drawnIndex > maxRows then break end

			local rank = tonumber(getElementData(player, 'race rank')) or 1

			if not playerTitleCache[player] or playerTitleCache[player].raw ~= getPlayerName(player) then
				local tempName = getPlayerName(player)
				local textW = dxGetTextWidth(tempName, 1, fBold)
				while textW > nickWidth do
					tempName = string.sub(tempName, 1, -2)
					textW = dxGetTextWidth(tempName, 1, fBold)
				end

				local cleanNameForCrown = removeHex(tempName, 6)
				local cleanAuthW = dxGetTextWidth(cleanNameForCrown, 1, fBold)

				playerTitleCache[player] = {
					raw = getPlayerName(player),
					display = tempName,
					crownWidth = cleanAuthW
				}
			end
			local pName = playerTitleCache[player].display
			local crownWidth = playerTitleCache[player].crownWidth

			local y1 = wY + (rowHeight*(startRow+drawnIndex-1))
			local y2 = wY + (rowHeight*(startRow+drawnIndex))

			local drawNameX = wX + rankWidth
			local countryData = getElementData(player, 'cw_flag')
			if showCountryFlags and countryData then
				local country = string.lower(tostring(countryData))
				local flagPath = ":ip2c/client/images/flags/"..country..".png"
				if flagCache[country] == nil then
					flagCache[country] = fileExists(flagPath)
				end

				if flagCache[country] then
					local fY = y1 + (rowHeight - flagHeight) / 2
					dxDrawImage(drawNameX, fY, flagWidth, flagHeight, flagPath)
					drawNameX = drawNameX + flagWidth + 5
				end
			end

			dxDrawText(rank .. getPrefix(rank), wX + margin, y1, wX+rankWidth, y2, tocolor(255,255,255, 255), 1, fReg, "left", "center", false, false, false, true, false)
		dxDrawText(pName, drawNameX, y1, wX+nickWidth, y2, tocolor(tr, tg, tb, 255), 1.0, fBold, "left", "center", false, false, false, true, false)

		if getElementData(player, 'captain') then
			local iconSize = rowHeight * 0.6
			local iconY = y1 + (rowHeight - iconSize) / 2
			dxDrawImage(drawNameX + crownWidth + 5, iconY, iconSize, iconSize, "fonts/Crown.png")
		end

		dxDrawText((getElementData(player, 'Score') or 0) .. ' pts', wX + rankWidth + nickWidth, y1, wX+(nickWidth + rankWidth + ptsWidth), y2, tocolor(255, 255, 255, 255), 1.0, fReg, "center", "center", false, false, false, true, false)
		end
	end
end

function updateDisplay()
	if ffaActive and isElement(teams[1]) then
		local state = ""
		local sColor = "#ffffff"
		local r1, g1, b1 = getTeamColor(teams[1])
		local t1 = getTeamName(teams[1])
		local t1Players = cachedT1Players

		if not f_round then
			if c_round == m_round and m_round > 0 and isWarEndedClient then
				sColor = "#ff0000"
				state = "Ended"
			else
				sColor = "#00ff00"
				state = "Running"
			end
		else
			sColor = "#FFA500"
			state = "Free"
		end

		rowCount = #t1Players + 4
		if rowCount > 19 then rowCount = 19 end -- Limit high to avoid overflow if too many players

		windowSizeX, windowSizeY = math.floor(250 * (screenW / 1920)), math.floor(rowHeight) * rowCount

		if mode == "main" then
			local count = #t1Players
			if count > 15 then count = 15 end -- Limit display list

			-- Backgrounds
			dxDrawRoundedRectangle(wX, wY, windowSizeX, windowSizeY, 10, tocolor(0, 0, 0, 160), false, false)
			dxDrawRectangle(wX, wY + (rowHeight*2), windowSizeX, rowHeight, tocolor(r1, g1, b1, 30), false, false) -- t1 bg
			dxDrawBottomRoundedRectangle(wX, wY + (rowHeight * (rowCount-1)), windowSizeX, rowHeight, 10, tocolor(0, 0, 0, 160), false, false) -- mode bg
			dxDrawText("Press #bababaF1 #ffffffto change mode", wX, wY + (rowHeight * (rowCount-1)), wX+windowSizeX, wY + (rowHeight * (rowCount)), tocolor(255, 255, 255, 200), 1, fBold, "center", "center", false, false, true, true, false)

			-- Header info
			dxDrawText(sColor..state, wX, wY, wX+windowSizeX, wY+rowHeight, tocolor(255, 255, 255, 255), 1, fBold, "center", "center", false, false, true, true, false)
			dxDrawText(roundStringCache, wX, wY+rowHeight, wX+windowSizeX, wY+(rowHeight*2), tocolor(255, 255, 255, 255), 1, fBold, "center", "center", false, false, true, true, false)

			-- Team 1
			dxDrawText(getTeamName(teams[1]), wX + margin, wY + (rowHeight*2), wX+windowSizeX-margin, wY+(rowHeight*3), tocolor(r1, g1, b1, 255), 1, fBold, "left", "center", false, false, false, true, false)
			drawRows(t1Players, 3, r1, g1, b1, 15)

		elseif mode == "compact" then
			-- Compact for FFA / Carbon Mode
			-- Show exactly like main mode but only for the local player

			local myPlayers = {}
			local myRank = 1
			for i, p in ipairs(t1Players) do
				if p == localPlayer then
					table.insert(myPlayers, p)
					break
				end
			end

			-- Recalculate layout for single player
			local count = #myPlayers
			-- Header(2) + Team(1) + Player(1) + Footer(1) = 5 rows ideally,
			-- but let's stick to the styling of main mode.
			-- In main mode: dxDrawBottomRoundedRectangle uses rowCount-1

			-- Let's use a minimal rowCount that fits the content
			rowCount = 5
			if count == 0 then rowCount = 4 end -- Just headers if valid player not found

			windowSizeX, windowSizeY = math.floor(250 * (screenW / 1920)), math.floor(rowHeight) * rowCount

			-- Backgrounds
			dxDrawRoundedRectangle(wX, wY, windowSizeX, windowSizeY, 10, tocolor(0, 0, 0, 160), false, false)
			dxDrawRectangle(wX, wY + (rowHeight*2), windowSizeX, rowHeight, tocolor(r1, g1, b1, 30), false, false) -- t1 bg
			dxDrawBottomRoundedRectangle(wX, wY + (rowHeight * (rowCount-1)), windowSizeX, rowHeight, 10, tocolor(0, 0, 0, 160), false, false) -- mode bg
			dxDrawText("Press #bababaF1 #ffffffto change mode", wX, wY + (rowHeight * (rowCount-1)), wX+windowSizeX, wY + (rowHeight * (rowCount)), tocolor(255, 255, 255, 200), 1, fBold, "center", "center", false, false, true, true, false)

			-- Header info
			dxDrawText(sColor..state, wX, wY, wX+windowSizeX, wY+rowHeight, tocolor(255, 255, 255, 255), 1, fBold, "center", "center", false, false, true, true, false)
			dxDrawText(roundStringCache, wX, wY+rowHeight, wX+windowSizeX, wY+(rowHeight*2), tocolor(255, 255, 255, 255), 1, fBold, "center", "center", false, false, true, true, false)

			-- Team 1
			dxDrawText(getTeamName(teams[1]), wX + margin, wY + (rowHeight*2), wX+windowSizeX-margin, wY+(rowHeight*3), tocolor(r1, g1, b1, 255), 1, fBold, "left", "center", false, false, false, true, false)
			drawRows(myPlayers, 3, r1, g1, b1)

		else
			dxDrawRoundedRectangle(1,1,1,1, 0, tocolor(0, 0, 0, 0), false, false)
		end
	elseif isElement(teams[1]) and isElement(teams[2]) then
		local state = ""
		local sColor = "#ffffff"
		local r1, g1, b1 = getTeamColor(teams[1])
		local r2, g2, b2 = getTeamColor(teams[2])
		local t1tag = tags[1]
		local t2tag = tags[2]
		local t1 = getTeamName(teams[1])
		local t2 = getTeamName(teams[2])
		local t1Players = cachedT1Players
		local t2Players = cachedT2Players

		windowSizeX, windowSizeY = math.floor(250 * (screenW / 1920)), math.floor(rowHeight) * rowCount

		if not f_round then
			if c_round == m_round and m_round > 0 and isWarEndedClient then
				sColor = "#ff0000"
				state = "Ended"
			else
				sColor = "#00ff00"
				state = "Running"
			end
		else
			sColor = "#FFA500"
			state = "Free"
		end

		if #t1Players > 8 and #t2Players > 8 then
			rowCount = 8 + 8 + 5
		elseif #t1Players > 8 and #t2Players < 8 then
			rowCount = 8 + #t2Players + 5
		elseif #t1Players < 8 and #t2Players > 8 then
			rowCount = 8 + #t1Players + 5
		else
			rowCount = #t1Players + #t2Players + 5
		end

		if mode == "main" then
			local count = (#t1Players > 8) and 8 or #t1Players

			-- Backgrounds
			dxDrawRoundedRectangle(wX, wY, windowSizeX, windowSizeY, 10, tocolor(0, 0, 0, 160), false, false)
			dxDrawRectangle(wX, wY + (rowHeight*2), windowSizeX, rowHeight, tocolor(r1, g1, b1, 30), false, false) -- t1 bg
			dxDrawRectangle(wX, wY + (rowHeight*(2+(count+1))), windowSizeX, rowHeight, tocolor(r2, g2, b2, 30), false, false) -- t2 bg
			dxDrawBottomRoundedRectangle(wX, wY + (rowHeight * (rowCount-1)), windowSizeX, rowHeight, 10, tocolor(0, 0, 0, 160), false, false) -- mode bg
			dxDrawText("Press #bababaF1 #ffffffto change mode", wX, wY + (rowHeight * (rowCount-1)), wX+windowSizeX, wY + (rowHeight * (rowCount)), tocolor(255, 255, 255, 200), 1, fBold, "center", "center", false, false, true, true, false)

			-- Header info
			dxDrawText(sColor..state, wX, wY, wX+windowSizeX, wY+rowHeight, tocolor(255, 255, 255, 255), 1, fBold, "center", "center", false, false, true, true, false)
			dxDrawText(roundStringCache, wX, wY+rowHeight, wX+windowSizeX, wY+(rowHeight*2), tocolor(255, 255, 255, 255), 1, fBold, "center", "center", false, false, true, true, false)

			-- Team 1
			dxDrawText(getTeamName(teams[1]), wX + margin, wY + (rowHeight*2), wX+windowSizeX-margin, wY+(rowHeight*3), tocolor(r1, g1, b1, 255), 1, fBold, "left", "center", false, false, false, true, false)
			dxDrawText(t1ScoreStrCache, wX + rankWidth + nickWidth, wY + (rowHeight*2), wX+(nickWidth + rankWidth + ptsWidth), wY+(rowHeight*3), tocolor(r1, g1, b1, 255), 1, fBold, "center", "center", false, false, false, true, false)
			drawRows(t1Players, 3, r1, g1, b1, 8)

			-- Team 2
			local t2start = 3 + count
			dxDrawText(getTeamName(teams[2]), wX + margin, wY + (rowHeight*t2start), wX+windowSizeX-margin, wY+(rowHeight*(t2start+1)), tocolor(r2, g2, b2, 255), 1, fBold, "left", "center", false, false, false, true, false)
			dxDrawText(t2ScoreStrCache, wX + rankWidth + nickWidth, wY + (rowHeight*t2start), wX+(nickWidth + rankWidth + ptsWidth), wY+(rowHeight*(t2start+1)), tocolor(r2, g2, b2, 255), 1, fBold, "center", "center", false, false, false, true, false)
			drawRows(t2Players, t2start + 1, r2, g2, b2, 8)

		elseif mode == "compact" then
			rowCount = 5
			windowSizeX, windowSizeY = math.floor(250 * (screenW / 1920)), math.floor(rowHeight) * rowCount
			dxDrawRoundedRectangle(wX, wY, windowSizeX, windowSizeY, 10, tocolor(0, 0, 0, 160), false, false) -- background
			dxDrawRectangle(wX, wY + (rowHeight*2), windowSizeX, rowHeight, tocolor(r1, g1, b1, 20), false, false) -- t1 bg
			dxDrawBottomRoundedRectangle(wX, wY + (rowHeight * (rowCount-1)), windowSizeX, rowHeight, 10, tocolor(0, 0, 0, 160), false, false) -- mode bg
			dxDrawText("Press #bababaF1 #ffffffto change mode", wX, wY + (rowHeight * (rowCount-1)), wX+windowSizeX, wY + (rowHeight * (rowCount)), tocolor(255, 255, 255, 200), 1, fBold, "center", "center", false, false, true, true, false)
			dxDrawText(sColor..state, wX, wY, wX+windowSizeX, wY+rowHeight, tocolor(255, 255, 255, 255), 1, fBold, "center", "center", false, false, true, true, false)
			dxDrawText(roundStringCache, wX, wY+rowHeight, wX+windowSizeX, wY+(rowHeight*2), tocolor(255, 255, 255, 255), 1, fBold, "center", "center", false, false, true, true, false)

			-- Score line with Tags (Fallbacks if tags are missing)
			local dTag1 = (tags[1] and tags[1] ~= "") and tags[1] or "Team 1"
			local dTag2 = (tags[2] and tags[2] ~= "") and tags[2] or "Team 2"

			dxDrawText(cachedT1c..dTag1.."   "..t1ScoreStrCache.."  #ffffff-  "..cachedT2c..t2ScoreStrCache.."   "..dTag2, wX + margin, wY + (rowHeight*2), wX+windowSizeX-(margin*2), wY+(rowHeight*3), tocolor(r1, g1, b1, 255), 1, fBold, "center", "center", false, false, false, true, false)

			-- Local Player Information Row (Rank | Name | Points)
			local player = localPlayer
			local rank = tonumber(getElementData(player, 'race rank')) or 1
			local pName = getPlayerName(player)
			local pTeam = getPlayerTeam(player)
			local pR, pG, pB = 255, 255, 255
			if pTeam then pR, pG, pB = getTeamColor(pTeam) end

			if not playerTitleCache[player] or playerTitleCache[player].raw ~= getPlayerName(player) then
				local tempName = getPlayerName(player)
				local textW = dxGetTextWidth(tempName, 1, fBold)
				while textW > nickWidth do
					tempName = string.sub(tempName, 1, -2)
					textW = dxGetTextWidth(tempName, 1, fBold)
				end
				playerTitleCache[player] = { raw = getPlayerName(player), display = tempName }
			end
			pName = playerTitleCache[player].display

			local y1 = wY + (rowHeight*3)
			local y2 = wY + (rowHeight*4)

			local drawNameX = wX + rankWidth
			local countryData = getElementData(player, 'cw_flag')
			if countryData then
				local country = string.lower(tostring(countryData))
				local flagPath = ":ip2c/client/images/flags/"..country..".png"
				if flagCache[country] == nil then
					flagCache[country] = fileExists(flagPath)
				end

				if flagCache[country] then
					local fY = y1 + (rowHeight - flagHeight) / 2
					dxDrawImage(drawNameX, fY, flagWidth, flagHeight, flagPath)
					drawNameX = drawNameX + flagWidth + 5
				end
			end

			dxDrawText(rank .. getPrefix(rank), wX + margin, y1, wX+rankWidth, y2, tocolor(255,255,255, 255), 1, fReg, "left", "center", false, false, false, true, false)
			dxDrawText(pName, drawNameX, y1, wX+nickWidth, y2, tocolor(pR, pG, pB, 255), 1.0, fBold, "left", "center", false, false, false, true, false)
			dxDrawText((getElementData(player, 'Score') or 0) .. ' pts', wX + rankWidth + nickWidth, y1, wX+(nickWidth + rankWidth + ptsWidth), y2, tocolor(255, 255, 255, 255), 1.0, fReg, "center", "center", false, false, false, true, false)

		else
			dxDrawRoundedRectangle(1,1,1,1, 0, tocolor(0, 0, 0, 0), false, false)
		end
	end
end


local c_window

function createGUI(team1, team2)
	if isElement(c_window) then
		destroyElement(c_window)
	end
	c_window = guiCreateWindow(screenW/2-150, screenH/2-75, 300, 140, "Select Team", false)
	guiWindowSetMovable(c_window, false)
	guiWindowSetSizable(c_window, false)

	if ffaActive or carbonActive then
		local btnText = "Free-For-All"
		if carbonActive then btnText = "Carbon Mode" end
		local t1_button = guiCreateButton(40, 35, 220, 30, btnText, false, c_window)
		addEventHandler("onClientGUIClick", t1_button, team1Choosen, false)
	else
		-- Use TAGS for F3 buttons if available, otherwise fallback to team names
		local b1Text = (tags[1] and tags[1] ~= "") and tags[1] or team1
		local b2Text = (tags[2] and tags[2] ~= "") and tags[2] or (team2 or "")

		local t1_button = guiCreateButton(40, 35, 100, 30, b1Text, false, c_window)
		addEventHandler("onClientGUIClick", t1_button, team1Choosen, false)
		local t2_button = guiCreateButton(160, 35, 100, 30, b2Text, false, c_window)
		addEventHandler("onClientGUIClick", t2_button, team2Choosen, false)
	end

	local t3_button = guiCreateButton(40, 85, 220, 30, 'Spectators', false, c_window)
	addEventHandler("onClientGUIClick", t3_button, team3Choosen, false)
	showCursor(true)
end

function removeHex (text, digits)
	assert (type (text) == "string", "Bad argument 1 @ removeHex [String expected, got "..tostring(text).."]")
	assert (digits == nil or (type (digits) == "number" and digits > 0), "Bad argument 2 @ removeHex [Number greater than zero expected, got "..tostring (digits).."]")
	return string.gsub (text, "#"..(digits and string.rep("%x", digits) or "%x+"), "")
end

function rgb2hex(r,g,b)
	return string.format("#%02X%02X%02X", r,g,b)
end

local a_window

function createAdminGUI()
	if isElement(a_window) then
		destroyElement(a_window)
	end
	a_window = guiCreateWindow(screenW/2-150, screenH/2-75, 405, 320, 'Clan War Management', false)
	guiWindowSetSizable(a_window, false)
	close_button = guiCreateButton(9, 285, 381, 25, 'Close', false, a_window)
	addEventHandler("onClientGUIClick", close_button, function() guiSetVisible(a_window, false) showCursor(false) end, false)
	tab_panel = guiCreateTabPanel(0.02, 0.08, 0.94, 0.78, true, a_window)
	guiSetInputMode('no_binds_when_editing')
		tab_general = guiCreateTab('General', tab_panel)
		local t1 = guiCreateLabel(59, 5, 68, 28, "Team Name", false, tab_general)
		guiLabelSetHorizontalAlign(t1, "center", false)
		local t2 = guiCreateLabel(260, 5, 68, 28, "Team Name", false, tab_general)
		guiLabelSetHorizontalAlign(t2, "center", false)
		local t1t = guiCreateLabel(59, 45, 68, 28, "Team Tag", false, tab_general)
		guiLabelSetHorizontalAlign(t1t, "center", false)
		local t2t = guiCreateLabel(260, 45, 68, 28, "Team Tag", false, tab_general)
		guiLabelSetHorizontalAlign(t2t, "center", false)
		local t1c = guiCreateLabel(39, 85, 100, 28, "Team Color [hex]", false, tab_general)
		guiLabelSetHorizontalAlign(t1c, "center", false)
		local t2c = guiCreateLabel(240, 85, 100, 28, "Team Color [hex]", false, tab_general)
		guiLabelSetHorizontalAlign(t2c, "center", false)

		if isElement(teams[1]) then
			t1name = getTeamName(teams[1])
		else
			t1name = 'Not Even Trying'
		end
		t1_field = guiCreateEdit(15, 23, 154, 22, t1name, false, tab_general)
		if isElement(teams[2]) then
			t2name = getTeamName(teams[2])
		else
			t2name = 'Speed is King'
		end
		t2_field = guiCreateEdit(217, 23, 154, 22, t2name, false, tab_general)
		if(isElement(tags[1])) then
			t1tag = tags[1]
		else
			t1tag = 'NET'
		end
		t1t_field = guiCreateEdit(15, 63, 154, 22, t1tag, false, tab_general)
		if(isElement(tags[2])) then
			t2tag = tags[2]
		else
			t2tag = 'SiK'
		end
		t2t_field = guiCreateEdit(217, 63, 154, 22, t2tag, false, tab_general)

		if isElement(teams[1]) then
			t1r, t1g, t1b = getTeamColor(teams[1])
			t1color = rgb2hex(t1r,t1g,t1b)
		else
			t1color = '#bababa'
		end
		t1c_field = guiCreateEdit(15, 103, 154, 22, t1color, false, tab_general)
		if isElement(teams[2]) then
			t2r, t2g, t2b = getTeamColor(teams[2])
			t2color = rgb2hex(t2r,t2g,t2b)
		else
			t2color = '#00ff00'
		end
		t2c_field = guiCreateEdit(217, 103, 154, 22, t2color, false, tab_general)
		zadat_button = guiCreateButton(132, 143, 114, 29, "Apply", false, tab_general)
		guiSetProperty(zadat_button, "NormalTextColour", "FFFFFEFE")
		addEventHandler("onClientGUIClick", zadat_button, zadatTeams, false)

		carbon_button = guiCreateButton(10, 143, 112, 29, "Carbon Mode", false, tab_general)
		guiSetProperty(carbon_button, "NormalTextColour", "FFBA55D3")
		addEventHandler("onClientGUIClick", carbon_button, function()
			if warActive then
				outputChatBox('[CW] #ff0000Mode is already active. Please press Stop CW first.', 255, 255, 255, true)
				return
			end
			modeMessagesEnabled = true
			warActive = true
			serverCall('startCarbonMode', localPlayer)
		end, false)

		start_button = guiCreateButton(10, 188, 112, 29, "Start CW", false, tab_general)
		guiSetProperty(start_button, "NormalTextColour", "FF30FE00")
		addEventHandler("onClientGUIClick", start_button, function()
			if warActive then
				outputChatBox('[CW] #ff0000War is already active. Please press Stop CW first.', 255, 255, 255, true)
				return
			end
			modeMessagesEnabled = true
			warActive = true
			startWar()
		end, false)
		stop_button = guiCreateButton(132, 188, 114, 29, "Stop CW", false, tab_general)
		guiSetProperty(stop_button, "NormalTextColour", "FFFE0000")
		addEventHandler("onClientGUIClick", stop_button, function()
			serverCall('destroyTeams', localPlayer)
			modeMessagesEnabled = false
			warActive = false
			-- Ensure cursor stays visible for admin panel
			if guiGetVisible(a_window) then
				showCursor(true)
				-- Added: timer enforcing cursor visibility if the system hid it when closing c_window
				setTimer(function()
					if isElement(a_window) and guiGetVisible(a_window) then
						showCursor(true)
					end
				end, 100, 1)
			end
			createAdminGUI()
			guiSetVisible(a_window, true)
		end, false)
		fun_button = guiCreateButton(257, 188, 114, 29, "Fun Round", false, tab_general)
		guiSetProperty(fun_button, "NormalTextColour", "FFFD7D00")
		addEventHandler("onClientGUIClick", fun_button, function() serverCall('funRound', localPlayer) end, false)

		ffa_button = guiCreateButton(257, 143, 114, 29, "Free For All", false, tab_general)
		guiSetProperty(ffa_button, "NormalTextColour", "FF00BFFF")
		addEventHandler("onClientGUIClick", ffa_button, function()
			if warActive then
				outputChatBox('[CW] #ff0000Mode is already active. Please press Stop CW first.', 255, 255, 255, true)
				return
			end
			modeMessagesEnabled = true
			warActive = true
			-- Call the function name directly, not the event name
			serverCall('startFreeForAll', localPlayer)
		end, false)

		if ffaActive then
			if carbonActive then
				guiSetText(t1_field, "Carbon Mode")
			else
				guiSetText(t1_field, "Free-For-All")
			end
			guiSetEnabled(t1_field, false)
			guiSetText(t1c_field, "#C0C0C0")
			guiSetText(t2_field, "")
			guiSetEnabled(t2_field, false)

			-- Do not disable mode buttons here
		end

		tab_rounds = guiCreateTab('Rounds & Score', tab_panel)
		tt1_name = guiCreateLabel(29, 33, 120, 20, "Team 1 Score", false, tab_rounds)
		tt2_name = guiCreateLabel(29, 110, 120, 20, "Team 2 Score", false, tab_rounds)
		local t1_score
		local t2_score
		if isElement(teams[1]) then t1_score = getElementData(teams[1], 'Score') else t1_score = '0' end
		if isElement(teams[2]) then t2_score = getElementData(teams[2], 'Score') else t2_score = '0' end
		t1cur_field = guiCreateEdit(29, 53, 120, 27, tostring(t1_score), false, tab_rounds)
		t2cur_field = guiCreateEdit(29, 129, 120, 27, tostring(t2_score), false, tab_rounds)
		guiCreateLabel(238, 33, 80, 20, "Current Round", false, tab_rounds)
		guiCreateLabel(238, 109, 80, 20, "Total Rounds", false, tab_rounds)
		cr_field = guiCreateEdit(238, 53, 80, 27, tostring(c_round), false, tab_rounds)
		ct_field = guiCreateEdit(238, 129, 80, 27, tostring(m_round), false, tab_rounds)
		zadat_button2 = guiCreateButton(128, 172, 100, 27, 'Apply', false, tab_rounds)
		guiSetProperty(zadat_button2, "NormalTextColour", "FFFFFEFE")
		addEventHandler("onClientGUIClick", zadat_button2, zadatScoreRounds, false)

		-- tab 3
		tab_caps = guiCreateTab('Captains', tab_panel)
		tt1_cap_label = guiCreateLabel(29, 33, 120, 20, "Team 1 Captain:", false, tab_caps)
		t1_playersList = guiCreateComboBox(29, 53, 120, 123, "", false, tab_caps)
		tt2_cap_label = guiCreateLabel(29, 110, 120, 20, "Team 2 Captain:", false, tab_caps)
		t2_playersList = guiCreateComboBox(29, 129, 120, 123, "", false, tab_caps)

		-- Populate player lists
		for key, player in ipairs(getElementsByType('player')) do
			guiComboBoxAddItem(t1_playersList, removeHex(getPlayerName(player), 6))
			guiComboBoxAddItem(t2_playersList, removeHex(getPlayerName(player), 6))
		end

		zadat_button3 = guiCreateButton(238, 90, 100, 27, 'Apply', false, tab_caps)
		guiSetProperty(zadat_button3, "NormalTextColour", "FFFFFEFE")
		addEventHandler("onClientGUIClick", zadat_button3, zadatCaptains, false)

		-- Captains tab is now always enabled, even in FFA/Carbon modes
	guiSetVisible(a_window, false)
end

function hex2rgb(hex)
	hex = hex:gsub("#","")
	return tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6))
end

function toogleGUI()
	-- Only allow opening the CW panel via F3 when Start CW was pressed.
	-- Hiding the panel is always allowed (so it can be closed by rounds/end).
	if isElement(c_window) then
		local vis = guiGetVisible(c_window)

		if not warActive then
			if vis then
				guiSetVisible(c_window, false)
				if not guiGetVisible(a_window) then
					showCursor(false)
				end
			end
			-- Don't allow opening if war is not active
			return
		end

		if vis then
			guiSetVisible(c_window, false)
			if not guiGetVisible(a_window) then
				showCursor(false)
			end
		else
			-- Recreate the GUI on open to ensure tags are updated
			if isElement(teams[1]) then
				local t1 = getTeamName(teams[1])
				local t2 = (isElement(teams[2]) and getTeamName(teams[2]) or "")
				createGUI(t1,t2)
			end

			-- Allow opening F3 normally even in FFA/Carbon modes
			guiSetVisible(c_window, true)
			showCursor(true)
		end
	end
end

function toogleAdminGUI()
	if isAdmin then
		if isElement(a_window) then
			if guiGetVisible(a_window) then
				guiSetVisible(a_window, false)
				if isElement(c_window) then
					if not guiGetVisible(c_window) then
						showCursor(false)
					end
				else
					showCursor(false)
				end
			elseif not guiGetVisible(a_window) then
				updateAdminPanelText()
				guiSetVisible(a_window, true)
				guiSetInputMode('no_binds_when_editing')
				showCursor(true)
			end
		end
	end
end

function toggleMode()
	-- Debug: log attempt to change mode
	local panelVisible = isElement(c_window) and guiGetVisible(c_window)
	local prevMode = mode

	-- Allow changing display mode when the team selection panel is visible
	-- or when a clan war is active (Start CW was pressed).
	if not (panelVisible or warActive) then

		return
	end
	if mode == "main" then
		mode = "compact"
		if modeMessagesEnabled then
			outputChatBox('[CW] #ffffffCompact mode', 155, 155, 255, true)
		end
	elseif mode == "compact" then
		mode = "hidden"
		if modeMessagesEnabled then
			outputChatBox('[CW] #ffffffHidden mode', 155, 155, 255, true)
		end
	else
		mode = "main"
		if modeMessagesEnabled then
			outputChatBox('[CW] #ffffffFull mode', 155, 155, 255, true)
		end
	end
	-- Debug: show resulting mode and whether the chat message was shown
	local changed = tostring(prevMode ~= mode)

end

function updateAdminPanelText()
	local function guiSetTextSafe(el, text)
		if el and isElement(el) then guiSetText(el, tostring(text or '')) end
	end
	if isElement(teams[1]) then
		local team1name = getTeamName(teams[1]) or 'No Team'
		local team2name = (isElement(teams[2]) and getTeamName(teams[2])) or 'No Team'
		guiSetTextSafe(t1_field, team1name)
		guiSetTextSafe(t2_field, team2name)
		local r1, g1, b1 = isElement(teams[1]) and getTeamColor(teams[1]) or 0,0,0
		local r2, g2, b2 = isElement(teams[2]) and getTeamColor(teams[2]) or 0,0,0
		local t1c = rgb2hex(r1,g1,b1)
		local t2c = rgb2hex(r2,g2,b2)
		-- guiSetTextSafe(t1c_field, t1c) -- Disabled auto-correcting color field
		-- guiSetTextSafe(t2c_field, t2c) -- Disabled auto-correcting color field
		local team1tag = tags[1] or ''
		local team2tag = tags[2] or ''
		-- guiSetTextSafe(t1t_field, team1tag) -- Disabled auto-correcting tag field
		-- guiSetTextSafe(t2t_field, team2tag) -- Disabled auto-correcting tag field
		local t1score = tostring(getElementData(teams[1], 'Score') or 0)
		local t2score = "0"
		if isElement(teams[2]) then
			t2score = tostring(getElementData(teams[2], 'Score') or 0)
		end
		guiSetTextSafe(tt1_name, tostring(team1name).. ':')
		guiSetTextSafe(tt2_name, tostring(team2name).. ':')
		guiSetTextSafe(t1cur_field, t1score)
		guiSetTextSafe(t2cur_field, t2score)
		guiSetTextSafe(cr_field, tostring(c_round))
		guiSetTextSafe(ct_field, tostring(m_round))
	end
end

function team1Choosen()
	triggerServerEvent('switchPlayerTeam', resourceRoot, localPlayer, teams[1])
	if not guiGetVisible(a_window) then
		showCursor(false)
	end
	guiSetVisible(c_window, false)
end

function team2Choosen()
	triggerServerEvent('switchPlayerTeam', resourceRoot, localPlayer, teams[2])
	if not guiGetVisible(a_window) then
		showCursor(false)
	end
	guiSetVisible(c_window, false)
end

function team3Choosen()
	triggerServerEvent('switchPlayerTeam', resourceRoot, localPlayer, teams[3])
	if not guiGetVisible(a_window) then
		showCursor(false)
	end
	guiSetVisible(c_window, false)
end

function zadatScoreRounds()
	local t1score = guiGetText(t1cur_field)
	local t2score = guiGetText(t2cur_field)
	local cur_round = guiGetText(cr_field)
	local ma_round = guiGetText(ct_field)

	if isElement(teams[1]) then
		setElementData(teams[1], 'Score', t1score)
	end
	if isElement(teams[2]) then
		setElementData(teams[2], 'Score', t2score)
	end

	serverCall('updateRounds', cur_round, ma_round)
end

function zadatTeams()
	local t1name = guiGetText(t1_field)
	local t2name = guiGetText(t2_field)
	local t1color = guiGetText(t1c_field)
	local t2color = guiGetText(t2c_field)
	local t1tag = guiGetText(t1t_field)
	local t2tag = guiGetText(t2t_field)
	if isElement(teams[1]) and isElement(teams[2]) then
		local r1,g1,b1 = hex2rgb(t1color)
		local r2,g2,b2 = hex2rgb(t2color)
		serverCall('setTeamNameCustom', teams[1], t1name)
		serverCall('setTeamColorCustom', teams[1], r1, g1, b1)
		serverCall('setTeamNameCustom', teams[2], t2name)
		serverCall('setTeamColorCustom', teams[2], r2, g2, b2)
		serverCall('setTags', t1tag, t2tag)
		serverCall('sincAP')
	end
end

function zadatCaptains()
	local t1_item = guiComboBoxGetSelected(t1_playersList)
	local t1_text = tostring(guiComboBoxGetItemText(t1_playersList, t1_item))
	local t2_item = guiComboBoxGetSelected(t2_playersList)
	local t2_text = tostring(guiComboBoxGetItemText(t2_playersList, t2_item))
	triggerServerEvent ('onCaptainsChosen', localPlayer, t1_text, t2_text)
end

function startWar()
	-- Ensure GUI opens in Full mode and F3/panel reopening is allowed when a war starts
	mode = "main"
	modeMessagesEnabled = true
	warActive = true
	local t1name = guiGetText(t1_field)
	local t2name = guiGetText(t2_field)
	local t1tag = guiGetText(t1t_field)
	local t2tag = guiGetText(t2t_field)
	local t1color = guiGetText(t1c_field)
	local t2color = guiGetText(t2c_field)
	local r1,g1,b1 = hex2rgb(t1color)
	local r2,g2,b2 = hex2rgb(t2color)
	serverCall('startWar', t1name, t2name, t1tag, t2tag, r1, g1, b1, r2, g2, b2)
	outputChatBox('[CW] #ffffffPress #9b9bffF1 #ffffffto switch display mode', 155, 155, 255, true)
	outputChatBox('[CW] #ffffffPress #9b9bffF3 #ffffffto select team', 155, 155, 255, true)
end


function updateTeamData(team1, team2, team3)
	teams[1] = team1
	teams[2] = team2
	teams[3] = team3
	if isElement(teams[1]) then
		local r, g, b = getTeamColor(teams[1])
		cachedT1c = rgb2hex(r, g, b)
	end
	if isElement(teams[2]) then
		local r, g, b = getTeamColor(teams[2])
		cachedT2c = rgb2hex(r, g, b)
	end
	updateAdminPanelText()
	repopulateAndSortCache()
end

function updateTagData(tag1, tag2)
	tags[1] = tag1
	tags[2] = tag2
	updateAdminPanelText()
end

function updateRoundData(c_r, max_r, f_r)

	if c_r == 0 then
		f_round = true
	else
		f_round = f_r
	end
	c_round = c_r
	m_round = max_r
	roundStringCache = "Round " .. tostring(c_round) .. "/" .. tostring(m_round)
	-- If we've reached the final round (e.g. 10/10) disable mode messages
	-- so the CW panel cannot be reopened with F3 until Start CW is pressed again.
	if tonumber(c_r) and tonumber(max_r) then
		if tonumber(c_r) > tonumber(max_r) then
			modeMessagesEnabled = false
			warActive = false
		elseif tonumber(c_r) == tonumber(max_r) then

		end
	end
	updateAdminPanelText()
end

function updateAdminInfo(obj)
	isAdmin = obj
	if isAdmin then
		createAdminGUI()
		outputChatBox('[CW] #ffffffPress #9b9bffF2 #ffffffto open management panel', 155, 155, 255, true)
	end
end

function onResStart()
	serverCall('isClientAdmin', localPlayer)
	createAdminGUI()
end

function stringToNumber(colorsString)
	local r = gettok(colorsString, 1, string.byte(','))
	local g = gettok(colorsString, 2, string.byte(','))
	local b = gettok(colorsString, 3, string.byte(','))
	if r == false or g == false or b == false then
		outputChatBox('[Race League]: use - [0-255], [0-255], [0-255]', 255, 155, 155, true)
		return 0, 255, 0
	else
		return r, g, b
	end
end

createAdminGUI()
setTimer(function()
	if isElement(teams[1]) then
		local t2name = ''
		if isElement(teams[2]) then t2name = getTeamName(teams[2]) end
		createGUI(getTeamName(teams[1]), t2name)
	end
end, 2000, 1)
bindKey('F3', 'down', toogleGUI)
bindKey('F2', 'down', toogleAdminGUI)
bindKey('F1', 'down', toggleMode)
serverCall('playerJoin', localPlayer)

function math.round(number, decimals, method)
	decimals = decimals or 0
	local factor = 10 ^ decimals
	if (method == "ceil" or method == "floor") then return math[method](number * factor) / factor
	else return tonumber(("%."..decimals.."f"):format(number)) end
end

addEventHandler('onClientRender', getRootElement(),
function()
	if isElement(teams[1]) and isElement(teams[2]) and isElement(teams[3]) then
		-- Removed clientside 'Pts per map' calculation to prevent overwriting server values and network spam
	end
end
)

addEventHandler('onClientRender', getRootElement(), updateDisplay)
addEventHandler('onClientResourceStart', getResourceRootElement(), onResStart)
addEventHandler('onClientMapStarting', root, function()
	-- Only disable panel on map start if we're already at (or beyond) the final round.
	-- This avoids disabling the panel when a map restarts earlier in the match.
	local cr = tonumber(c_round) or 0
	local mr = tonumber(m_round) or 0
	if mr > 0 and cr >= mr then
		modeMessagesEnabled = false
		warActive = false
	end
end)

addEventHandler('onClientPlayerJoin', getRootElement(),
function()
	if t1_playersList and t2_playersList then
		guiComboBoxAddItem(t1_playersList, removeHex(getPlayerName(source), 6))
		guiComboBoxAddItem(t2_playersList, removeHex(getPlayerName(source), 6))
	end
end)

addEventHandler('onClientPlayerQuit', getRootElement(),
function()
	if t1_playersList and t2_playersList then
		for row = 0, guiComboBoxGetItemCount(t1_playersList) - 1 do
			if (guiComboBoxGetItemText(t1_playersList, row) == removeHex(getPlayerName(source),6)) then
				guiComboBoxRemoveItem(t1_playersList, row)
			end
		end
		for row = 0, guiComboBoxGetItemCount(t2_playersList) - 1 do
			if (guiComboBoxGetItemText(t2_playersList, row) == removeHex(getPlayerName(source),6)) then
				guiComboBoxRemoveItem(t2_playersList, row)
			end
		end
	end
end)

addEventHandler('onClientPlayerChangeNick', getRootElement(),
function(old_nick, new_nick)
	if t1_playersList and t2_playersList then
		for row = 0, guiComboBoxGetItemCount(t1_playersList) - 1 do
			if (guiComboBoxGetItemText(t1_playersList, row) == removeHex(old_nick,6)) then
				guiComboBoxSetItemText(t1_playersList, row, removeHex(new_nick,6))
			end
		end
		for row = 0, guiComboBoxGetItemCount(t2_playersList) - 1 do
			if (guiComboBoxGetItemText(t2_playersList, row) == removeHex(old_nick,6)) then
				guiComboBoxSetItemText(t2_playersList, row, removeHex(new_nick,6))
			end
		end
	end
end)
