function getRandomColor()
	local index = 1
	local random = math.random(1690)
	for i, v in pairs(COLORS) do
		if index == random then
			return v
		end
		index = index + 1
	end
end

function getCarColorsFromColorName(hex)
	-- local hex = COLORS[name] or nil
	if not hex then
		return false
	end
	r1,g1,b1 = getColorFromString(hex)
	r3 = math.floor(r1 / 2)
	g3 = math.floor(g1 / 2)
	b3 = math.floor(b1 / 2)
	r2 = r1 + math.floor((255 - r1)/2)
	g2 = g1 + math.floor((255 - g1)/2)
	b2 = b1 + math.floor((255 - b1)/2)
	return {r1,g1,b1,r2,g2,b2,r3,g3,b3,0,0,0}
end

function changeColor (playerSource, commandName, playerToPaint, targetColor)
	if (not playerToPaint and not targetColor) then
		local randomSelfPaintColor = getRandomColor()
		paintPlayer(playerSource, getCarColorsFromColorName(randomSelfPaintColor))
		return
	end

	local playerUnit = findPlayer(playerToPaint)
	if not playerUnit then
		targetColor = playerToPaint
		playerToPaint = playerSource
		playerUnit = playerSource
	end
	if (targetColor) then
		targetColor = string.lower(targetColor)
		local random = math.random(1690)
		local success = false
		for i, v in pairs(COLORS) do
			if i == targetColor then
				targetColor = v
				success = true
				break
			end
		end
		if (not success) then
			outputChatBox("Not found: " .. targetColor, playerSource)
			return
		end
		paintPlayer(playerUnit, getCarColorsFromColorName(targetColor))
		return
	else
		local randomSelfPaintColor = getRandomColor()
		paintPlayer(playerUnit, getCarColorsFromColorName(randomSelfPaintColor))
		return
	end
end
addCommandHandler("colorify", changeColor)

function findPlayer(player_input)
	alivePlayers = getAlivePlayers ()
	if (alivePlayers) then
		for playerKey, playerValue in ipairs(alivePlayers) do
			-- Find first occurrence matching input
			if string.find(removeHEXColorCode(getPlayerName(playerValue)), player_input) then
				return playerValue
			end
		end
	end
end

function paintPlayer(player, color)
	if not player then
		return
	end
	if getPlayerTeam(player) then
		return
	end
	local vehicleToPaint = getPedOccupiedVehicle(player)
	if vehicleToPaint then
		setVehicleColor(vehicleToPaint, unpack(color))
	end
end

function removeHEXColorCode(name)
	return name:gsub('#%x%x%x%x%x%x', '') or name
end

addEventHandler("onResourceStart", resourceRoot, function()
	setTimer(randomColor, 10000, 0)
end )

function randomColor()
	if getPlayerCount() > 0 then
		if math.random(100) == 50 then
			local randomSelfPaintColor = getRandomColor()
			paintPlayer(getRandomPlayer(), getCarColorsFromColorName(randomSelfPaintColor))
		end
	end
end
