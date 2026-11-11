--[[
RegarDs Robin [SGC] Social Gaming CommuniTy :D Enjoy The Script
Code made more readable by GPT-4o mini
]]

-- Add a scoreboard column to track "Time Played"
exports.scoreboard:addScoreboardColumn('Time Played')

local timeData = {}

-- Function to check and update time values
local function checkValues(source, minutes, seconds)
	if seconds >= 60 then
		timeData[source]['min'] = (tonumber(timeData[source]['min'] or 0) + 1)
		timeData[source]['sec'] = 0
	end
	if minutes >= 60 then
		timeData[source]['hours'] = (tonumber(timeData[source]['hours'] or 0) + 1)
		timeData[source]['min'] = 0
	end
	return minutes, seconds
end

-- True si el jugador esta logueado con una cuenta real (no invitado).
local function hasAccount(player)
	local account = getPlayerAccount(player)
	return account and not isGuestAccount(account) or false
end

-- Timer function that increments player time every second.
-- Solo se registra tiempo para cuentas: los invitados no acumulan.
setTimer(function()
	for _, player in pairs(getElementsByType("player")) do
		if hasAccount(player) then
			if not timeData[player] then
				timeData[player] = { hours = 0, min = 0, sec = 0 }
			end

			timeData[player]['sec'] = (tonumber(timeData[player]['sec'] or 0) + 1)

			checkValues(player, timeData[player]['min'] or 0, timeData[player]['sec'] or 0)

			local hours = tonumber(timeData[player]['hours'] or 0)
			local minutes = tonumber(timeData[player]['min'] or 0)
			local seconds = tonumber(timeData[player]['sec'] or 0)

			-- Update the player's time played data
			setElementData(player, "Time Played", string.format("%dh %dm", hours, minutes))
			setElementData(player, "Time Played Seconds", hours * 3600 + minutes * 60 + seconds)
		end
	end
end, 1000, 0)

-- Function to handle saving player time data when the resource stops
local function onResourceStop()
	if source ~= resourceRoot then return end
	for _, player in pairs(getElementsByType("player")) do
		local playerAccount = getPlayerAccount(player)
		if playerAccount and not isGuestAccount(playerAccount) then
			local timeValue = getElementData(player, 'Time Played')
			local hours = tonumber(timeData[player]['hours'] or 0)
			local minutes = tonumber(timeData[player]['min'] or 0)
			local seconds = tonumber(timeData[player]['sec'] or 0)
			setAccountData(playerAccount, "Time Played-hours", tostring(hours))
			setAccountData(playerAccount, "Time Played-min", tostring(minutes))
			setAccountData(playerAccount, "Time Played-sec", tostring(seconds))
			setAccountData(playerAccount, "Time Played", tostring(timeValue))
		end
	end
end

-- Function to load player time data when the resource starts
local function onResourceStart()
	if source ~= resourceRoot then return end
	for _, player in pairs(getElementsByType("player")) do
		local playerAccount = getPlayerAccount(player)
		if playerAccount and not isGuestAccount(playerAccount) then
			local storedTime = getAccountData(playerAccount, "Time Played")
			local storedHours = getAccountData(playerAccount, "Time Played-hours")
			local storedMinutes = getAccountData(playerAccount, "Time Played-min")
			local storedSeconds = getAccountData(playerAccount, "Time Played-sec")
			if not timeData[player] then
				timeData[player] = { hours = 0, min = 0, sec = 0 }
			end

			if storedTime then
				local h = tonumber(storedHours) or 0
				local m = tonumber(storedMinutes) or 0
				local s = tonumber(storedSeconds) or 0
				setElementData(player, "Time Played", storedTime)
				setElementData(player, "Time Played Seconds", h * 3600 + m * 60 + s)
				timeData[player]["hours"] = h
				timeData[player]["min"] = m
				timeData[player]["sec"] = s
			else
				setElementData(player, "Time Played", 0)
				setElementData(player, "Time Played Seconds", 0)
				setAccountData(playerAccount, "Time Played", 0)
			end
		end
	end
end

-- Function to handle when a player quits
local function onPlayerQuit()
	local playerAccount = getPlayerAccount(source)
	if playerAccount and not isGuestAccount(playerAccount) then
		local timeValue = getElementData(source, 'Time Played')
		local hours = tonumber(timeData[source]['hours'] or 0)
		local minutes = tonumber(timeData[source]['min'] or 0)
		local seconds = tonumber(timeData[source]['sec'] or 0)
		setAccountData(playerAccount, "Time Played-hours", tostring(hours))
		setAccountData(playerAccount, "Time Played-min", tostring(minutes))
		setAccountData(playerAccount, "Time Played-sec", tostring(seconds))
		setAccountData(playerAccount, "Time Played", tostring(timeValue))
	end
	timeData[source] = nil
end

-- Function to handle logging in players
local function onPlayerLogin(_, playerAccount)
	if playerAccount then
		local storedTime = getAccountData(playerAccount, "Time Played")
		local storedHours = getAccountData(playerAccount, "Time Played-hours")
		local storedMinutes = getAccountData(playerAccount, "Time Played-min")
		local storedSeconds = getAccountData(playerAccount, "Time Played-sec")
		if storedTime then
			local h = tonumber(storedHours) or 0
			local m = tonumber(storedMinutes) or 0
			local s = tonumber(storedSeconds) or 0
			setElementData(source, "Time Played", storedTime)
			setElementData(source, "Time Played Seconds", h * 3600 + m * 60 + s)
			timeData[source] = { hours = h, min = m, sec = s }
		else
			setElementData(source, "Time Played", 0)
			setElementData(source, "Time Played Seconds", 0)
			setAccountData(playerAccount, "Time Played", 0)
		end
	end
end

-- Function to handle logout: guarda el tiempo en la cuenta y limpia el
-- jugador (pasa a invitado, ya no registra tiempo).
local function onPlayerLogout(previousAccount)
	local player = source
	if previousAccount and not isGuestAccount(previousAccount) then
		local data = timeData[player] or { hours = 0, min = 0, sec = 0 }
		local hours = tonumber(data['hours'] or 0)
		local minutes = tonumber(data['min'] or 0)
		local seconds = tonumber(data['sec'] or 0)
		setAccountData(previousAccount, "Time Played-hours", tostring(hours))
		setAccountData(previousAccount, "Time Played-min", tostring(minutes))
		setAccountData(previousAccount, "Time Played-sec", tostring(seconds))
		setAccountData(previousAccount, "Time Played", string.format("%dh %dm", hours, minutes))
	end
	timeData[player] = nil
	setElementData(player, "Time Played", nil)
	setElementData(player, "Time Played Seconds", nil)
end

-- Event handlers
addEventHandler("onPlayerQuit", root, onPlayerQuit)
addEventHandler("onPlayerLogin", root, onPlayerLogin)
addEventHandler("onPlayerLogout", root, onPlayerLogout)
addEventHandler("onResourceStop", root, onResourceStop)
addEventHandler("onResourceStart", root, onResourceStart)
