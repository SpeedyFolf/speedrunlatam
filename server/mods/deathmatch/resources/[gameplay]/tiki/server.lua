local db
local serverMapTotals = {}
local mapLookup = {}
local serverTotalTiki = 0

-- Helpers
local function trim(s)
	return s and tostring(s):gsub("^%s*(.-)%s*$", "%1") or nil
end

function table.size(t) local c = 0; for _ in pairs(t) do c = c + 1 end; return c end

addEventHandler("onResourceStart", resourceRoot, function()
	db = dbConnect("sqlite", ":/tikis.db")
	dbExec(db, [[
		CREATE TABLE IF NOT EXISTS tiki_collected (
			account TEXT,
			tiki_id TEXT,
			collected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
			UNIQUE(account, tiki_id)
		)
	]])

	-- Parse the XML once on startup
	local xml = xmlLoadFile("tikis.map")
	if xml then
		for _, node in ipairs(xmlNodeGetChildren(xml)) do
			if xmlNodeGetName(node) == "tiki" then
				local id = xmlNodeGetAttribute(node, "id")
				local mapStr = xmlNodeGetAttribute(node, "map")
				if id and mapStr then
					serverTotalTiki = serverTotalTiki + 1
					mapLookup[id] = {}
					-- Support multiple comma-separated maps
					for m in string.gmatch(mapStr, '([^,]+)') do
						local cleanMap = trim(m)
						serverMapTotals[cleanMap] = (serverMapTotals[cleanMap] or 0) + 1
						mapLookup[id][cleanMap] = true
					end
				end
			end
		end
		xmlUnloadFile(xml)
	end
end)

local function getAcc(p)
	if not isElement(p) then return nil end
	local acc = getPlayerAccount(p)
	if not acc or isGuestAccount(acc) then return nil end
	return getAccountName(acc)
end

local function syncPlayer(p)
	local acc = getAcc(p)
	local collected = {}
	local isLoggedIn = false

	-- If the player is logged in, pull data. Otherwise, it sends an empty table and 'false' for login status
	if acc then
		isLoggedIn = true
		-- Select ordered by date to create an accurate chronological sequence number
		local qh = dbQuery(db, "SELECT tiki_id, collected_at FROM tiki_collected WHERE account=? ORDER BY collected_at ASC", acc)
		local res = dbPoll(qh, -1)

		if res then
			for i, row in ipairs(res) do
				-- Pass back both the time and the row index (sequence)
				collected[row.tiki_id] = { time = row.collected_at, seq = i }
			end
		end
	end

	triggerClientEvent(p, "tiki:sync", resourceRoot, collected, isLoggedIn)
end

addEvent("tiki:requestSync", true)
addEventHandler("tiki:requestSync", root, function()
	-- Mark the client as fully loaded and ready to receive syncs
	setElementData(client, "playerLoaded", true, false)
	syncPlayer(client)
end)

addEventHandler("onPlayerLogin", root, function(_, account)
	if account then
		setAccountData(account, "tiki:lastNick", getPlayerName(source))
	end

	-- Only sync if the client script has finished loading
	if getElementData(source, "playerLoaded") then
		syncPlayer(source)
	end
end)

-- Handle logout so tiki respawn instantly
addEventHandler("onPlayerLogout", root, function()
	if isElement(source) then
		triggerClientEvent(source, "tiki:sync", resourceRoot, {}, false)

		-- Force close menu
		triggerClientEvent(source, "tiki:forceClose", resourceRoot)
	end
end)

-- Leaderboard Data Provider
addEvent("tiki:requestLeaderboard", true)
addEventHandler("tiki:requestLeaderboard", resourceRoot, function()
	if not client then return end

	-- Cache the client element because 'client' becomes nil inside async DB callbacks
	local thePlayer = client
	local myAccount = getAcc(thePlayer)

	dbQuery(function(qh)
		local res = dbPoll(qh, 0)
		if res and isElement(thePlayer) then
			-- Assign the stored nickname directly, falling back to the account name if none exists
			for _, row in ipairs(res) do
				local accObj = getAccount(row.account)
				local rawNick = accObj and getAccountData(accObj, "tiki:lastNick") or row.account

				-- Strip hexcodes
				row.nickname = rawNick:gsub("#%x%x%x%x%x%x", "")
			end

			triggerClientEvent(thePlayer, "tiki:receiveLeaderboard", resourceRoot, res, myAccount)
		end
	end, db, "SELECT account, COUNT(tiki_id) as total FROM tiki_collected GROUP BY account ORDER BY total DESC LIMIT 50")
end)

addEvent("tiki:collect", true)
addEventHandler("tiki:collect", root, function(tikiId, mapName)
	if not client then return end
	local acc = getAcc(client)
	if not acc or not tikiId or not mapName then return end

	-- Save current nickname to account data
	local accountObj = getPlayerAccount(client)
	if accountObj then
		setAccountData(accountObj, "tiki:lastNick", getPlayerName(client))
	end

	dbExec(db, "INSERT OR IGNORE INTO tiki_collected (account, tiki_id, collected_at) VALUES (?, ?, datetime('now', 'localtime'))", acc, tikiId)

	-- Calculate the sequence number for this new pickup
	local seqQuery = dbQuery(db, "SELECT COUNT(*) as total FROM tiki_collected WHERE account=?", acc)
	local seqRes = dbPoll(seqQuery, 500)
	local seqNum = (seqRes and seqRes[1]) and seqRes[1].total or 1

	local timeQuery = dbQuery(db, "SELECT collected_at FROM tiki_collected WHERE account=? AND tiki_id=?", acc, tikiId)
	local timeRes = dbPoll(timeQuery, 500)
	local timeStr = (timeRes and timeRes[1]) and timeRes[1].collected_at or "Just now"

	triggerClientEvent(client, "tiki:updateSingle", resourceRoot, tikiId, timeStr, seqNum)

	if getResourceFromName("killmessages") then
		exports.killmessages:outputMessage({{"image", path="tiki.png", resource=getThisResource(), width=18, height=20}, getPlayerName(client)}, root, 255, 150, 255)
	end

	local totalOnMap = serverMapTotals[mapName] or 0
	if totalOnMap > 0 then
		local userQuery = dbQuery(db, "SELECT tiki_id FROM tiki_collected WHERE account=?", acc)
		local userRows = dbPoll(userQuery, 500)

		if userRows then
			local countOnMap = 0
			for _, row in ipairs(userRows) do
				-- Check against the multi-map lookup structure
				if mapLookup[row.tiki_id] and mapLookup[row.tiki_id][mapName] then
					countOnMap = countOnMap + 1
				end
			end

			if countOnMap >= totalOnMap then
				outputChatBox("[Tiki] #FFEA66" .. getPlayerName(client) .. " #FF96FFhas collected all #FFEA66" .. totalOnMap .. " #FF96FFtiki on #FFEA66" .. mapName .. "#FF96FF!", root, 255, 150, 255, true)
			end

			if #userRows >= serverTotalTiki then
				local quip = {"A true collector of tiki.", "A passionate tiki tickler.", "All our tiki are belong to them.", "No tiki left behind!", "Type gg in chat, please."}
				local addendum = quip[math.random(#quip)]
				outputChatBox("[Tiki] #FFEA66" .. getPlayerName(client) .. " #FF96FFhas collected all #FFEA66" .. serverTotalTiki .. " #FF96FFtiki on the server. " .. addendum, root, 255, 150, 255, true)

				-- "Tikitician" Achievement
				if exports["achievements"] then
					exports.achievements:triggerAchievement(client, "tikiAll")
				end
			end
		end
	end
end)

-- Admin command: /tikidelete <id>
-- Both "/tikidelete 1" and "/tikidelete tiki (1)" will work
addCommandHandler("tikidelete", function(player, commandName, ...)
	-- Capture all arguments passed after the command as a single string
	local args = { ... }
	local inputId = table.concat(args, " ")

	if not inputId or inputId == "" then
		outputChatBox("[Tiki] Usage: #FFEA66/tikidelete [id]", player, 255, 150, 255, true)
		return
	end

	local acc = getPlayerAccount(player)
	if not acc or isGuestAccount(acc) or not isObjectInACLGroup("user." .. getAccountName(acc), aclGetGroup("Admin")) then
		outputChatBox("[Tiki] You do not have permission to use this command.", player, 255, 150, 255)
		return
	end

	local targetId = inputId
	local numericPart = string.match(inputId, "%d+")

	if numericPart then
		-- Leader zeroes are fake
		targetId = "tiki (" .. tonumber(numericPart) .. ")"
	elseif not string.match(inputId, "^tiki %(.+%)$") then
		-- No zeroes
		targetId = "tiki (" .. inputId .. ")"
	end

	local rowsAffected = dbExec(db, "DELETE FROM tiki_collected WHERE tiki_id = ?", targetId)

	if rowsAffected then
		local adminName = getPlayerName(player)
		outputChatBox("[Tiki] #FFEA66" .. adminName .. " #FF96FFhas uncollected #FFEA66" .. targetId .. "#FF96FF from all players.", root, 255, 150, 255, true)

		triggerClientEvent(root, "tiki:forceClose", resourceRoot)

		for _, p in ipairs(getElementsByType("player")) do
			syncPlayer(p)
		end
	else
		outputChatBox("[Tiki] Failed to delete #FFEA66" .. targetId .. "#FF96FF. Something went wrong or something.", player, 255, 150, 255, true)
	end
end)

-- User command: /tikireset <map>
addCommandHandler("tikireset", function(player, commandName, mapName)
	if not mapName then
		outputChatBox("[Tiki] Usage: #FFEA66/tikireset [mapname]", player, 255, 150, 255, true)
		return
	end

	local acc = getAcc(player)
	if not acc then
		outputChatBox("[Tiki] You must be logged in to reset progress.", player, 255, 150, 255)
		return
	end

	local targetMap = string.lower(mapName)
	-- Find IDs to delete using case-insensitive comparison
	local idsToDelete = {}
	for id, maps in pairs(mapLookup) do
		for mapKey, _ in pairs(maps) do
			-- Normalize the lookup key to lowercase for comparison
			if string.lower(mapKey) == targetMap then
				idsToDelete[#idsToDelete + 1] = id
				break -- Found a match for this tiki, move to next tiki
			end
		end
	end

	if #idsToDelete == 0 then
		outputChatBox("[Tiki] No tiki found for map: #FFEA66" .. mapName .. "#FF96FF.", player, 255, 150, 255, true)
		return
	end

	-- Build the SQL query manually without any table functions
	local query = "DELETE FROM tiki_collected WHERE account=? AND tiki_id IN ("
	for i = 1, #idsToDelete do
		query = query .. (i == 1 and "?" or ", ?")
	end
	query = query .. ")"

	-- Build the arguments table manually
	local params = {}
	params[1] = acc
	for i = 1, #idsToDelete do
		params[#params + 1] = idsToDelete[i]
	end

	-- Execute query
	local success = dbExec(db, query, unpack(params))

	if success then
		outputChatBox("[Tiki] Reset progress for map: #FFEA66" .. mapName, player, 255, 150, 255, true)
		syncPlayer(player)
		triggerClientEvent(player, "tiki:forceClose", resourceRoot)
	else
		outputChatBox("[Tiki] Failed to reset progress.", player, 255, 150, 255)
	end
end)
