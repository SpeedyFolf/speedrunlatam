-- What it does:
-- 1: triggers achievement for player
-- 2: updates objective for the player
-- 3: calculates percentage of players that got this achievement
-- 4: provides leaderboard
-- 5: gets all achievements for the player
-- 6: gets data from specific achievement for player

-- Database organisation: achievements(id TEXT, accountname TEXT, timestamp INTEGER, stage INTEGER, data TEXT)

DATABASE = dbConnect("sqlite", ":/achievements.db")
local percentageCache
deathsTracker = {}

-- Chain Reaction
local lastTimeUnlocked = {}

function updatePercentageCache()
	if not DATABASE then
		return
	end

	percentageCache = {}
	dbExec(DATABASE, "CREATE TABLE IF NOT EXISTS leaderboards(accountname TEXT, playername TEXT, count INTEGER)")

	local outputResults = dbPoll(dbQuery(DATABASE, "SELECT COUNT(*) as count FROM leaderboards"), -1)
	local maximumPlayers = outputResults[1]["count"] or 0

	-- Find how many players got every achievement
	for i, achCategory in ipairs(achievementsList) do
		for _, ach in ipairs(achCategory) do
			local achievementPlayers = 0

			-- Count how many players got this achievement
			outputResults = dbPoll(dbQuery(DATABASE, "SELECT stage as stages FROM achievements WHERE id = ?", ach.ID), -1)
			for _, v in ipairs(outputResults) do
				if v["stages"] >= ach.stages then
					achievementPlayers = achievementPlayers + 1
				end
			end

			-- Add percentage to the cache
			percentageCache[ach.ID] = achievementPlayers / (maximumPlayers / 100)
		end
	end
end

function databaseManagement()
	dbExec(DATABASE, "CREATE TABLE IF NOT EXISTS achievements(id TEXT, accountname TEXT, timestamp INTEGER, stage INTEGER, data TEXT)")
end

function playerGotAchievement(player, achievementID)
	-- Message
	outputChatBox("#00FF00[Achievements] " .. getPlayerName(player) .. "#00FF00 got an achievement: '#E7D9B0" .. getAchievementByID(achievementID).name .. "#00FF00'.", root, 0, 0, 0, true)

	-- Update things
	updateLeaderboard(player)
	updatePercentageCache()

	-- Show popup for the player
	triggerClientEvent(player, "showPopup", player, achievementID, percentageCache[achievementID])

	-- Chain Reaction
	if lastTimeUnlocked[player] then
		if getTickCount() - lastTimeUnlocked[player] < 1000 then
			triggerAchievement(player, "chainReaction", nil)
		end
	end
	lastTimeUnlocked[player] = getTickCount()
end

function triggerAchievement(player, achievementID, data, increment)
	if not DATABASE then
		return
	end
	if player == nil or not player then
		return
	end
	if getElementType(player) ~= "player" then
		return
	end
	if isGuestAccount(getPlayerAccount(player)) then
		return
	end

	if data == nil then
		data = {}
	end
	if increment == nil then
		increment = 1
	end

	databaseManagement()

	-- Check if player already had this achievement
	local results = dbPoll(dbQuery(DATABASE, "SELECT * FROM achievements WHERE accountname = ? AND id = ?", getAccountName(getPlayerAccount(player)), achievementID), -1)
	if results and #results > 0 then
		-- Player already had this achievement or its ongoing
		if getAchievementByID(achievementID).stages > 1 then
			-- The achievement has more than 1 stages
			increment = math.min(increment, getAchievementByID(achievementID).stages - results[1]["stage"])
			if increment == 0 then
				return
			end
			if results[1]["stage"] + increment < getAchievementByID(achievementID).stages then
				-- Update the stage counter only (achievement objective not reached)
				dbExec(DATABASE, "UPDATE achievements SET stage = ?, data = ? WHERE accountname = ? AND id = ?", results[1]["stage"] + increment, toJSON(data), getAccountName(getPlayerAccount(player)), achievementID)
			elseif results[1]["stage"] + increment == getAchievementByID(achievementID).stages and increment > 0 then
				-- Show achievement popup (objective completed)
				dbExec(DATABASE, "UPDATE achievements SET stage = ?, data = ?, timestamp = ? WHERE accountname = ? AND id = ?", results[1]["stage"] + increment, toJSON(data), os.time(), getAccountName(getPlayerAccount(player)), achievementID)
				playerGotAchievement(player, achievementID)
			end
		end
	else
		-- Player did not start or have this achievement
		if getAchievementByID(achievementID).stages > 1 then
			-- The achievement has more than 1 stages
			increment = math.min(increment, getAchievementByID(achievementID).stages)
			if increment == getAchievementByID(achievementID).stages then
				-- Achievement objective reached instantly
				dbExec(DATABASE, "INSERT INTO achievements(id, accountname, timestamp, stage, data) VALUES (?,?,?,?,?)", achievementID, getAccountName(getPlayerAccount(player)), os.time(), increment, toJSON(data))
				playerGotAchievement(player, achievementID)
			elseif increment < getAchievementByID(achievementID).stages then
				-- Achievement objective not reached
				dbExec(DATABASE, "INSERT INTO achievements(id, accountname, timestamp, stage, data) VALUES (?,?,?,?,?)", achievementID, getAccountName(getPlayerAccount(player)), 0, increment, toJSON(data))
			end
		else
			-- Achievement with only one stage
			dbExec(DATABASE, "INSERT INTO achievements(id, accountname, timestamp, stage, data) VALUES (?,?,?,?,?)", achievementID, getAccountName(getPlayerAccount(player)), os.time(), 1, toJSON(data))
			playerGotAchievement(player, achievementID)
		end
	end
end

function updateLeaderboard(player)
	dbExec(DATABASE, "CREATE TABLE IF NOT EXISTS leaderboards(accountname TEXT, playername TEXT, count INTEGER)")
	local leaderboardResuls = dbPoll(dbQuery(DATABASE, "SELECT * FROM leaderboards WHERE accountname = ?", getAccountName(getPlayerAccount(player))), -1)

	if leaderboardResuls and #leaderboardResuls > 0 then
		-- Player alredy had record in leaderboards
		-- Check how many achs player done
		local doneAchs = 0
		local playerAchs = dbPoll(dbQuery(DATABASE, "SELECT stage as stages, id as achievementID FROM achievements WHERE accountname = ?", getAccountName(getPlayerAccount(player))), -1)
		if playerAchs and #playerAchs > 0 then
			for _, v in ipairs(playerAchs) do
				if getAchievementByID(v["achievementID"]) and v["stages"] >= getAchievementByID(v["achievementID"]).stages then -- renamed ach hotfix
					doneAchs = doneAchs + 1
				end
			end
		end

		-- Update his leaderboard count
		dbExec(DATABASE, "UPDATE leaderboards SET count = ?, playername = ? WHERE accountname = ?", doneAchs, getPlayerName(player), getAccountName(getPlayerAccount(player)))
	else
		-- First time in leaderboards (just inserts 1 as count)
		dbExec(DATABASE, "INSERT INTO leaderboards(accountname, playername, count) VALUES (?,?,?)", getAccountName(getPlayerAccount(player)), getPlayerName(player), 1)
	end
end

-- This function updates objective of achievement that have multiple objectives
-- It checks if insertedData already exists in data section in database in player record and if it doesn't
-- it will add insertedData into database and increment stage, if this insertedData already exists
-- code will do nothing. This is useful for "do these maps for achievement" or "drive these cars" and etc.
-- Returns achievement data and a boolean value indicating whether the database was actually updated.
function updateObjective(player, achievementID, insertedData)
	-- Register in database
	local data = getAchievementData(player, achievementID)
	local updatedDB = false
	if data then
		-- If player already made some progress
		data = fromJSON(data)
		if #data < getAchievementByID(achievementID).stages then
			-- Do not mess with data and DB, if player already got the cheevo
			local found = false
			for j = 1, #data do
				if data[j] == insertedData then
					found = true
				end
			end

			local updatedData = data
			if not found then
				-- Trigger next stage
				table.insert(updatedData, insertedData)
				triggerAchievement(player, achievementID, updatedData)
				updatedDB = true
			end
		end
	else
		-- First stage
		triggerAchievement(player, achievementID, {insertedData})
		updatedDB = true
	end

	return data, updatedDB
end

addEventHandler("onResourceStart", resourceRoot, function()
	-- Sort
	sortAchievements()

	-- Updates for triggers
	if isTimer(updateTimer) then
		killTimer(updateTimer)
	end
	updateTimer = setTimer(update, 5000, 0)

	-- Get data for percentages cache
	databaseManagement()
	updatePercentageCache()

	if not fileExists("deaths.json") then
		iprint("[Achievements] INFO: Death type tracker (deaths.json) doesn't exist, creating...")
		local file = fileCreate("deaths.json")
		if file then
			fileWrite(file, "[]")
			fileClose(file)
		else
			iprint("[Achievements] ERROR: Could not create deaths.json")
		end
	end

	local file = fileOpen("deaths.json")
	if file then
		deathsTracker = fromJSON(fileRead(file, fileGetSize(file))) or {}
		fileClose(file)
	else
		iprint("[Achievements] ERROR: Could not open deaths.json for reading")
	end
end )

addEvent("getAchievements", true)
addEventHandler("getAchievements", root, function()
	databaseManagement()

	-- Gets data for this player from database
	local data = {}
	local results = dbPoll(dbQuery(DATABASE, "SELECT id as id, stage as stages, timestamp as timestamp FROM achievements WHERE accountname = ?", getAccountName(getPlayerAccount(source))), -1)
	if not results or (results and #results == 0) then
		-- Error, can't happen that this player doesn't have any achievement as you get "In the Beginning" always as first
		-- Something gone horribly wrong or player just login't
		triggerClientEvent(source, "getAchievementsFromServer", source, nil, nil, nil, g_currentMap)
		return
	end

	for i, achCategories in ipairs(achievementsList) do
		data[i] = {}
		for _, ach in ipairs(achCategories) do
			local found = false
			for k, v in ipairs(results) do
				if ach.ID == v["id"] then
					if ach.stages > 1 and v["stages"] >= ach.stages then
						-- Achievement had more than 1 stage and player got it
						table.insert(data[i], {true, v["stages"], percentageCache[ach.ID], v["timestamp"]})
					elseif ach.stages > 1 and v["stages"] < ach.stages then
						-- Achievement had more than 1 stage and player still in progress
						table.insert(data[i], {false, v["stages"], percentageCache[ach.ID]})
					else
						-- Achievement had 1 stage and player got it
						table.insert(data[i], {true, 1, percentageCache[ach.ID], v["timestamp"]})
					end

					found = true
					break
				end
			end

			if not found then
				table.insert(data[i], {false, 0, percentageCache[ach.ID]})
			end
		end
	end

	-- Get leaderboards
	dbExec(DATABASE, "CREATE TABLE IF NOT EXISTS leaderboards(accountname TEXT, playername TEXT, count INTEGER)")
	local leaderboard = dbPoll(dbQuery(DATABASE, "SELECT * FROM leaderboards ORDER BY count DESC LIMIT 100"), -1)

	-- Get total number players on leaderboard
	local outputResults = dbPoll(dbQuery(DATABASE, "SELECT COUNT(*) as playerscount FROM leaderboards"), -1)
	triggerClientEvent(source, "getAchievementsFromServer", source, data, leaderboard, tonumber(outputResults[1]["playerscount"] or 0))

	-- The Checklist support
	local progress
	if g_currentMap == "ProcedurallyGeneratedRace" then
		progress = getAchievementData(source, "disco10")
	elseif g_currentMap == "SuperFleischbergAutos" or g_currentMap == "SuperFleischbergAutosCollisions" then
		progress = getAchievementData(source, "sssFleischAllVehicles")
	end

	-- The bridges data
	local bridgesProgress = {collected = nil, zones = bridgeZones}
	local bridgesData = getAchievementData(source, "flyUnderEveryBridge")
	if bridgesData then
		bridgesData = fromJSON(bridgesData)

		local collectedBridges = {}
		for _, bridgeID in ipairs(bridgesData) do -- scan player's progress
			for i, location in ipairs(bridgeLocations) do
				if i == bridgeID then
					table.insert(collectedBridges, {ID = bridgeID, [1] = location[1], [2] = location[2]})
					break
				end
			end
		end

		bridgesProgress.collected = collectedBridges
	end
	triggerClientEvent(source, "getAchievementsFromServer", source, data, leaderboard, tonumber(outputResults[1]["playerscount"] or 0), g_currentMap, progress, bridgesProgress)
end )

function getAchievementData(player, achievementID)
	if not DATABASE then
		return
	end
	if isGuestAccount(getPlayerAccount(player)) then
		return
	end

	databaseManagement()

	-- Check data
	local results = dbPoll(dbQuery(DATABASE, "SELECT data as data FROM achievements WHERE accountname = ? AND id = ?", getAccountName(getPlayerAccount(player)), achievementID), -1)
	if results and #results > 0 then
		return results[1]["data"]
	else
		return false
	end
end

addCommandHandler("achsdeaths", function()
	local str = ""
	for _, v in ipairs(deathsTracker) do
		str = tostring(v) .. ", " .. str
	end
	outputConsole("Registered death types:")
	outputConsole(str)
end )
