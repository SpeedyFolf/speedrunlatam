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

-- Timer function that increments player time every second
setTimer(function()
	for _, player in pairs(getElementsByType("player")) do
		if not timeData[player] then
			timeData[player] = { hours = 0, min = 0, sec = 0 }
		end

		timeData[player]['sec'] = (tonumber(timeData[player]['sec'] or 0) + 1)

		local minutes, seconds = checkValues(player, timeData[player]['min'] or 0, timeData[player]['sec'] or 0)
		local hours = tonumber(timeData[player]['hours'] or 0)

		-- Format minutes for display
		local formattedMin = string.format("%02d", minutes)

		-- Update the player's time played data
		setElementData(player, "Time Played", string.format("%dh %dm", hours, minutes))
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
				setElementData(player, "Time Played", storedTime)
				timeData[player]["hours"] = tonumber(storedHours)
				timeData[player]["min"] = tonumber(storedMinutes)
				timeData[player]["sec"] = tonumber(storedSeconds)
			else
				setElementData(player, "Time Played", 0)
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
			setElementData(source, "Time Played", storedTime)
			timeData[source] = {
				hours = tonumber(storedHours),
				min = tonumber(storedMinutes),
				sec = tonumber(storedSeconds)
			}
		else
			setElementData(source, "Time Played", 0)
			setAccountData(playerAccount, "Time Played", 0)
		end
	end
end

-- Event handlers
addEventHandler("onPlayerQuit", root, onPlayerQuit)
addEventHandler("onPlayerLogin", root, onPlayerLogin)
addEventHandler("onResourceStop", root, onResourceStop)
addEventHandler("onResourceStart", root, onResourceStart)
