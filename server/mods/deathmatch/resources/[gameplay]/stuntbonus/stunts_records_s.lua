-- This code is so bad, please don't read it.
-- You are warned.

local DATABASE = dbConnect("sqlite", ":/stuntsRecords.db")

local stuntsNames = {
	"Maximum Insane Jump Distance",
	"Maximum Insane Jump Height",
	"Maximum Insane Jump Flips",
	"Maximum Insane Jump Rotation",
	"Longest Stoppie Distance",
	"Longest Stoppie Time",
	"Longest Wheelie Distance",
	"Longest Wheelie Time",
	"Longest 2 Wheels Distance",
	"Longest 2 Wheels Time"
};

local stuntTables = {
	"InsaneDistance",
	"InsaneHeight",
	"InsaneFlips",
	"InsaneRotation",
	"StoppieDistance",
	"StoppieTime",
	"WheelieDistance",
	"WheelieTime",
	"WheelsDistance",
	"WheelsTime"
};

addEventHandler("onResourceStart", resourceRoot, function()
	for i = 1, #stuntTables do
		-- Creating the  tables
		dbExec(DATABASE, "CREATE TABLE IF NOT EXISTS " ..stuntTables[i].. "(playername TEXT, score DOUBLE)")
	end
end )

addEvent("checkStunt", true)
addEventHandler("checkStunt", root, function(stuntData)
	if not DATABASE then return end

	if exports.achievements then
		exports.achievements:triggerAchievement(source, "millionDollarsStunt", nil, stuntData.money or 0) -- 1mil$ stunts
	end

	if stuntData.type == 1 then
		-- Insane Stunt Bonus
		for i = 1, 4 do
			if stuntData[i] == 0 then return end
			local recordUpdated = false

			-- Select Data
			recordsResults = dbPoll(dbQuery(DATABASE, "SELECT * FROM " ..stuntTables[i].. " WHERE playername = ?", getPlayerName(source)), -1)

			-- Update Data
			if (recordsResults and #recordsResults > 0) then
				if recordsResults[1]["score"] < stuntData[i] then
					dbExec(DATABASE, "UPDATE " ..stuntTables[i].. " SET score = ? WHERE playername = ?", stuntData[i], getPlayerName(source))
					recordUpdated = true
				end
			else
				dbExec(DATABASE, "INSERT INTO " ..stuntTables[i].. "(playername, score) VALUES (?,?)", getPlayerName(source), stuntData[i])
				recordUpdated = true
			end

			-- WR check
			checkResults = dbPoll(dbQuery(DATABASE, "SELECT * FROM " ..stuntTables[i].. " ORDER BY score DESC LIMIT 1"), -1)
			if checkResults[1]["playername"] == getPlayerName(source) and recordUpdated then
				if i < 3 then
					outputChatBox("#00FF00New " ..stuntsNames[i].. ": " ..getPlayerName(source).. "#00FF00, " ..string.format("%.1f", stuntData[i]).. " meters", root, 255, 255, 255, true)
				elseif i == 3 then
					outputChatBox("#00FF00New " ..stuntsNames[i].. ": " ..getPlayerName(source).. "#00FF00, " ..string.format("%.1f", stuntData[i]).. " flips", root, 255, 255, 255, true)
				elseif i == 4 then
					outputChatBox("#00FF00New " ..stuntsNames[i].. ": " ..getPlayerName(source).. "#00FF00, " ..string.format("%.1f", stuntData[i]).. " degrees", root, 255, 255, 255, true)
				end
			end
		end
	else
		-- 2 - Bike Stoppie
		-- 3 - Bike Wheelie
		-- 4 - 2 wheels double

		local recordUpdated = false
		for i = 1, 2 do
			if stuntData[i] == 0 then return end
			local recordUpdated = false

			-- Select Data
			recordsResults = dbPoll(dbQuery(DATABASE, "SELECT * FROM " ..stuntTables[stuntData.type * 2 + i].. " WHERE playername = ?", getPlayerName(source)), -1)

			-- Update Data
			if (recordsResults and #recordsResults > 0) then
				if recordsResults[1]["score"] < stuntData[i] then
					dbExec(DATABASE, "UPDATE " ..stuntTables[stuntData.type * 2 + i].. " SET score = ? WHERE playername = ?", stuntData[i], getPlayerName(source))
					recordUpdated = true
				end
			else
				dbExec(DATABASE, "INSERT INTO " ..stuntTables[stuntData.type * 2 + i].. "(playername, score) VALUES (?,?)", getPlayerName(source), stuntData[i])
				recordUpdated = true
			end

			-- WR check
			checkResults = dbPoll(dbQuery(DATABASE, "SELECT * FROM " ..stuntTables[stuntData.type * 2 + i].. " ORDER BY score DESC LIMIT 1"), -1)
			if checkResults[1]["playername"] == getPlayerName(source) and recordUpdated then
				if i == 1 then outputChatBox("#00FF00New " ..stuntsNames[stuntData.type * 2 + i].. ": " ..getPlayerName(source).. "#00FF00, " ..string.format("%.1f", stuntData[i]).. " meters", root, 255, 255, 255, true)
				elseif i == 2 then outputChatBox("#00FF00New " ..stuntsNames[stuntData.type * 2 + i].. ": " ..getPlayerName(source).. "#00FF00, " ..string.format("%.1f", stuntData[i]).. " seconds", root, 255, 255, 255, true) end
			end
		end

		-- Achievements

		-- Two wheels bonus
		if exports.achievements then
			local vehicle = getPedOccupiedVehicle(source)
			local vehicleModel = isElement(vehicle) and getElementModel(vehicle)

			if vehicleModel then
				if stuntData.type == 4 then
					exports.achievements:updateObjective(source, "stuntSkiing100Cars", vehicleModel) -- Serial Skier
					if stuntData[2] >= 25 then exports.achievements:triggerAchievement(source, "stuntSkiing25Seconds", nil) end -- Two Is All I Need
				-- Stoppie
				elseif stuntData.type == 2 then
					-- 100 meters stoppie
					if stuntData[1] >= 100 then exports.achievements:triggerAchievement(source, "100metersStoppie") end
					exports.achievements:updateObjective(source, "everyBikeStoppie", vehicleModel) -- Every bike stoppie

					if vehicleModel == 463 then
						outputChatBox("#00FF00" ..getPlayerName(source).. "#00FF00 just got stoppie on the Freeway bike! GG!", root, 255, 255, 255, true)
					end
				-- Wheelie
				elseif stuntData.type == 3 then
					exports.achievements:updateObjective(source, "everyBikeWheelie", vehicleModel) -- Every bike wheelie
				end
			end

			exports.achievements:triggerAchievement(source, "millionDollarsStunt", nil, stuntData.money or 0) -- 1mil$ stunts
		end
	end
end )

addEvent("getStuntsStats", true)
addEventHandler("getStuntsStats", root, function()
	if DATABASE then
		-- Get data: WR, then PB
		local data = {}
		for i = 1, #stuntTables do
			data[i] = dbPoll(dbQuery(DATABASE, "SELECT * FROM " ..stuntTables[i].. " ORDER BY score DESC LIMIT 1"), -1)
			data[#stuntTables+i] = dbPoll(dbQuery(DATABASE, "SELECT * FROM " ..stuntTables[i].. " WHERE playername = ?", getPlayerName(source)), -1)
		end

		triggerClientEvent(source, "receiveStuntsStats", source, data)
	end
end )
