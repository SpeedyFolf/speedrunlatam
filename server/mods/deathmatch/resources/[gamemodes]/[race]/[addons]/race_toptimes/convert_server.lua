addEventHandler('onResourceStart', resourceRoot,
	function()
		createTableIfNotExist()
		convertOldFormat()
		for _, player in ipairs(getElementsByType("player")) do
			backfillPlayerCountry(player)
		end
	end
)

function createTableIfNotExist()
    local cmd
    cmd = 'CREATE TABLE IF NOT EXISTS maptimes (mapName STRING, playerName STRING, playerSerial STRING, time INTEGER, dateRecorded INTEGER, playerAccount STRING, playerCountry STRING)'
    executeSQLQuery( cmd )
    ensureCountryColumn()
end

-- Migracion: agrega playerCountry a bases viejas (idempotente).
function ensureCountryColumn()
    local hasCountry = false
    local info = executeSQLQuery("PRAGMA table_info(maptimes)")
    if type(info) == "table" then
        for _, col in ipairs(info) do
            if col.name == "playerCountry" then
                hasCountry = true
                break
            end
        end
    end
    if not hasCountry then
        pcall(executeSQLQuery, "ALTER TABLE maptimes ADD COLUMN playerCountry STRING")
    end
end

function convertOldFormat()
	if (not g_Settings.convertoldtimes) then return end
	outputServerLog("[Race Top Times Converter] Working... Consider disabling in settings if this already happened.")
	-- Get maps
	local output = executeSQLQuery( "SELECT * FROM sqlite_master WHERE type='table'" )
	local tableCount = #output
	local ignoredTables = ""
	local apostropheMaps = ""
	local tablesConverted = 0
	local timesConverted = 0
	local timesTossed = 0

	-- ------------------------------------------------
	-- ------------------------------------------------
	-- ------------------------------------------------
	local h1,h2,h3 = debug.gethook()
	debug.sethook() -- Yeah, I dont like it either, especially since the ability to restore it is broken. But for a one time use, fine.
	for i, v in pairs(output) do
		local mapName = getMapName(v.name)
		if (not mapName) then
			ignoredTables = ignoredTables..v.name.."; "
		else
			local oldTable = readOldTable(v.name)
			for j, entry in pairs(oldTable) do
				local newEntry = {
					mapName = mapName,
					playerName = entry.playerName,
					playerSerial = entry.playerSerial,
					time = entry.timeMs,
					dateRecorded = dateTextToDateCode(entry.dateRecorded),
					playerAccount = entry.playerAccount,
				}
				if tonumber(entry.timeMs) then
					writeIntoNewTable(newEntry)
					timesConverted = timesConverted + 1
				else
					timesTossed = timesTossed + 1
				end
			end
			tablesConverted = tablesConverted + 1
			dropOldTable(v.name)
			if string.match(mapName, "'") then
				apostropheMaps = apostropheMaps..mapName.."; "
			end
		end
	end
	--debug.sethook(h1,h2,h3) -- Broken, just throws a warning.
	-- ------------------------------------------------
	-- ------------------------------------------------
	-- ------------------------------------------------

	if tablesConverted == 0 then
		return
	end
	outputServerLog("[Race Top Times Converter] Found "..tableCount.." tables total.")
	outputServerLog("[Race Top Times Converter] Converted "..timesConverted.." times from "..tablesConverted.." tables.")
	outputServerLog("[Race Top Times Converter] "..timesTossed.." times were corrupt.")
	outputServerLog("[Race Top Times Converter] The following tables were ignored, as they are not toptime tables: ".. ignoredTables)
	outputServerLog("[Race Top Times Converter] The following maps have apostrophes in them. Please double check their entries: ".. apostropheMaps)
	outputServerLog("[Race Top Times Converter] Done")
end

function dropOldTable(tableName)
	executeSQLQuery( "DROP TABLE " .. dealWithApostrophes(tableName) )
end

function writeIntoNewTable(newEntry)
	local cmd1 = 'INSERT INTO maptimes ('
	local cmd2 = 'VALUES ('
	local addComma = false
	for c,v in pairs(newEntry) do
		if addComma then
			cmd1 = cmd1 .. ', '
			cmd2 = cmd2 .. ', '
		else
			addComma = true
		end
		cmd1 = cmd1 .. c
		if type(v) == 'number' then
			cmd2 = cmd2 .. v or 0
		else
			cmd2 = cmd2 .. dealWithApostrophes(v) or ''
		end
	end
	cmd1 = cmd1 .. ') '
	cmd2 = cmd2 .. ')'
	executeSQLQuery( cmd1 .. cmd2 )
end

function getMapName(tableName)
	if string.match(tableName, "^race maptimes Sprint ") then
		return string.sub(tableName, 22)
	elseif string.match(tableName, "^race maptimes Freeroam ") then
		return string.sub(tableName, 24)
	elseif string.match(tableName, "^race maptimes Destruction derby ") then
		return string.sub(tableName, 33)
	else
		return false
	end
end

function readOldTable(tableName)
	cmd = "SELECT * FROM "..dealWithApostrophes(tableName)
	return executeSQLQuery( cmd )
end

function dealWithApostrophes(tableName)
	return "'" .. string.gsub(tableName, "'", "''") .. "'"
end
