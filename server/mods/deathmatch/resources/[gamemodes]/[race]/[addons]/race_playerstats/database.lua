
dbSchemaPlayers = {
	Name = "PlayerStats_Players",
	Columns = {
		{ Name="nick", Type="VARCHAR", Constraint="NOT NULL COLLATE NOCASE" },
		{ Name="serial", Type="VARCHAR", Constraint="COLLATE NOCASE" }
	},
	Indices = {
		{ Name = "PlayerStats_PlayerNick", Constraint="UNIQUE", Column='"nick"' }
	}
}

dbSchemaStats = {
	Name = "PlayerStats_Stats",
	Columns = {
		{ Name="id_player", Type="INTEGER" },
		{ Name="key", Type="INTEGER" },
		{ Name="val", Type="INTEGER" }
	},
	Indices = {
		{ Name = "PlayerStats_PlayerIdKey", Constraint="UNIQUE", Column='"id_player", "key"' }
	}
}

function safestring(s)
	-- escape '
	return s:gsub("(['])", "''")
end

function qsafestring(s)
	-- ensure is wrapped in '
	return "'" .. safestring(s) .. "'"
end


function createTable(dbschema)
	local sql = "CREATE TABLE IF NOT EXISTS " .. qsafestring(dbschema.Name) .. " ("
	for i,col in ipairs(dbschema.Columns) do
		if i > 1 then
			sql = sql .. ", "
		end
		sql = sql .. qsafestring(col.Name) .. " " .. col.Type
		if col.Constraint then
			sql = sql .. " " .. col.Constraint
		end
	end
	sql = sql .. ")"
	executeSQLQuery(sql)
	if dbschema.Indices then
		for _,index in ipairs(dbschema.Indices) do
			sql = "CREATE "
			if index.Constraint then
				sql = sql .. index.Constraint .. " "
			end
			sql = sql .. string.format("INDEX IF NOT EXISTS %s ON %s (%s)", index.Name, dbschema.Name, index.Column)
			executeSQLQuery(sql)
		end
	end
end


function GetPlayerList(sortKey, sortOrder, limit, offset, ...)
	local sql = nil

	if not tonumber(sortKey) then
		sql = string.format("SELECT rowid, nick FROM %s", dbSchemaPlayers.Name)
	else
		local extraJoins = ""
		local extraCols = ""
		if #{...} > 0 then
			for i,key in ipairs({...}) do
				extraJoins = extraJoins .. string.format(" LEFT JOIN %s AS t%u ON t%u.id_player=%s.rowid AND t%u.key=%u", dbSchemaStats.Name, i, i, dbSchemaPlayers.Name, i, tonumber(key))
				extraCols = extraCols .. string.format(", t%u.val AS [%u] ", i, key)
			end
		end
		sql = string.format("SELECT %s.rowid, %s.nick, t0.val ", dbSchemaPlayers.Name, dbSchemaPlayers.Name)
		sql = sql .. extraCols
		sql = sql .. string.format("FROM %s JOIN %s AS t0 ", dbSchemaPlayers.Name, dbSchemaStats.Name)
		sql = sql .. string.format("ON %s.rowid = t0.id_player ", dbSchemaPlayers.Name)
		sql = sql .. string.format("AND t0.key = %u ", tonumber(sortKey))
		sql = sql .. extraJoins
		if sortOrder then
			sql = sql .. string.format(" ORDER BY t0.val %s", tostring(sortOrder))
		end
	end
	if tonumber(limit) then
		sql = sql ..  string.format(" LIMIT %u", limit)
		if tonumber(offset) then
			sql = sql ..  string.format(" OFFSET %u", offset)
		end
	end
	executeSQLQuery("BEGIN TRANSACTION");
	local rows = executeSQLQuery(sql)
	executeSQLQuery("END TRANSACTION");
	if rows and #rows > 0 then
		alert("GetPlayerList: SortBy=%s; OrderBy=%s; Limit=%s; Offset=%s; Returned %u rows", tostring(sortKey), tostring(sortOrder), tostring(limit), tostring(offset), #rows)
		return rows
	end
	return {}
end


function GetPlayerId(player)
	local playerName = player
	if type(player) ~= "string" then
		playerName = getPlayerKey(player)
	else
		playerName = removeColorCoding(player)
	end
	if not playerName then
		return 0
	end
	--executeSQLQuery("BEGIN TRANSACTION");
	local cmd = string.format("SELECT rowid FROM %s WHERE nick=?", dbSchemaPlayers.Name)
	local rows = executeSQLQuery(cmd, playerName)
	--executeSQLQuery("END TRANSACTION");
	if rows and #rows > 0 then
		local result = tonumber(rows[1].rowid)
		return result
	else
		alert("GetPlayerId: Nick %s not in database", playerName)
	end
	return 0
end


function InsertPlayer(player)
	local playerName = getPlayerKey(player)
	if not playerName then return 0 end
	local serial = isElement(player) and getPlayerSerial(player) or ""
	executeSQLQuery("BEGIN TRANSACTION");
	local cmd = string.format("INSERT INTO %s (nick, serial) VALUES (?, ?)", dbSchemaPlayers.Name)
	local rows = executeSQLQuery(cmd, playerName, serial)
	if rows then
		rows = executeSQLQuery("SELECT last_insert_rowid() AS [id]")
	end
	executeSQLQuery("END TRANSACTION");

	if rows and #rows > 0 then
		alert("InsertPlayer: Nick=%s; New Id=%s", playerName, tostring(rows[1].id))
		return tonumber(rows[1].id)
	else
		alert("InsertPlayer: Nick=%s; FAILED!", playerName)
	end
	return 0
end


function DeletePlayer(player)
	if isElement(player) and getElementType(player) == "player" then
		player = getPlayerKey(player)
	end
	local playerId = GetPlayerId(player)
	if playerId > 0 then
		if DeletePlayerStats(player) then
			local sql = string.format("DELETE FROM %s WHERE rowid=%u", dbSchemaPlayers.Name, playerId)
			local result = executeSQLQuery(sql)
			if not result then
				alert("DeletePlayer: Error deleting player "..player)
			else
				return true
			end
		end
	else
		alert("DeletePlayer: player %s not found.", player)
	end
	return false
end


function RenamePlayer(oldNick, newNick)
	oldNick = getPlayerKey(oldNick)
	newNick = getPlayerKey(newNick)
	local playerId = GetPlayerId(oldNick)
	if playerId > 0 then
		local sql = string.format("UPDATE %s SET nick=? WHERE rowid=?", dbSchemaPlayers.Name)
		local result = executeSQLQuery(sql, newNick, playerId)
		return not not result
	end
	return false
end


function CreatePlayer(player)
	local playerId = InsertPlayer(player)
	if playerId == 0 then
		playerId = GetPlayerId(player)
	end
	--local stats = CreateDefaultStats()
	--SavePlayerStats(player, stats)
	return playerId
end


function CreateDefaultStats()
	local ret = {}
	for key,value in pairs(Stat) do
		if DefaultStats[key] then
			ret[value] = DefaultStats[key]
		end
	end
	return ret
end


function LoadPlayerStats(player, noAutoCreate)
	if not player then return nil end
	local playerId = GetPlayerId(player)
	--[[
	if playerId == 0 and not noAutoCreate then
		playerId = CreatePlayer(player)
	end
	--]]
	if playerId == 0 then
		return nil
	end
	local cmd = string.format("SELECT key, val FROM %s WHERE id_player=%u", dbSchemaStats.Name, playerId)
	--executeSQLQuery("BEGIN TRANSACTION");
	local rows = executeSQLQuery(cmd)
	--executeSQLQuery("END TRANSACTION");
	local ret = {}
	if rows and #rows > 0 then
		for i,row in ipairs(rows) do
			ret[rows[i].key] = rows[i].val
		end
	end
	return ret
end


function SavePlayerStats(playerName, stats, noAutoCreate)
	local ret = false
	alert("Saving player %s stats...", tostring(playerName))
	local playerId = GetPlayerId(playerName)
	if playerId == 0 and not noAutoCreate then
		playerId = CreatePlayer(playerName)
	end
	if playerId == 0 then
		alert("SavePlayerStats: Player %s not found.", playerName)
		return
	end
	executeSQLQuery("BEGIN TRANSACTION");
	for k,v in pairs(stats) do
		local cmd = string.format("INSERT OR REPLACE INTO %s (id_player, key, val) VALUES (%u, %u, %u)", dbSchemaStats.Name, playerId, k, v)
		local result = executeSQLQuery(cmd)
		if not result then
			alert("SavePlayerStats: Error updating stat %u for player %s", k, playerName)
		else
			ret = true
		end
	end
	executeSQLQuery("END TRANSACTION");
	return ret
end


function DeletePlayerStats(playerName)
	local ret = false
	local playerId = GetPlayerId(playerName)
	if playerId == 0 then
		alert("DeletePlayerStats: Player %s not found.", playerName)
		return ret
	end
	local cmd = string.format("DELETE FROM %s WHERE id_player=%u", dbSchemaStats.Name, playerId)
	executeSQLQuery("BEGIN TRANSACTION");
	local result = executeSQLQuery(cmd)
	executeSQLQuery("END TRANSACTION");
	if not result then
		alert("DeletePlayerStats: Error deleting stats for player %s", playerName)
	else
		ret = true
	end
	return ret
end


function DeleteAllStats()
	local ret = false
	local cmd = string.format("DELETE FROM %s", dbSchemaStats.Name)
	executeSQLQuery("BEGIN TRANSACTION");
	local result = executeSQLQuery(cmd)
	executeSQLQuery("END TRANSACTION");
	if not result then
		alert("DeleteAllStats: Error deleting stats")
	else
		ret = true
	end

	return ret
end


function DeleteStats(statKey)
	local ret = false
	if not(tonumber(statKey)) then
		alert("DeleteStats: Invalid stat key '%s'.", tostring(statKey))
		return ret
	end
	local cmd = string.format("DELETE FROM %s WHERE key=%u", dbSchemaStats.Name, tonumber(statKey))
	executeSQLQuery("BEGIN TRANSACTION");
	local result = executeSQLQuery(cmd)
	executeSQLQuery("END TRANSACTION");
	if not result then
		alert("DeleteStats: Error deleting stats for key %u", statKey)
	else
		ret = true
	end
	return ret
end


function FixStatValues()
	local sql = string.format("UPDATE %s SET val=val-4294967295 WHERE val>4000000000", dbSchemaStats.Name)
	executeSQLQuery(sql)
end


addEventHandler("onResourceStart", resourceRoot,
	function()
		createTable(dbSchemaPlayers)
		createTable(dbSchemaStats)
		FixStatValues()
	end
)
