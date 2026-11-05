local g_MapResName

addEventHandler('onGamemodeMapStart', root,
	function(mapres)
		g_MapResName = getResourceName(mapres)

		for index,thePlayer in ipairs (getElementsByType("player")) do -- display rating for every player
			local playername = getPlayerName(thePlayer)
			local sql = executeSQLQuery("SELECT rating FROM mapratings WHERE mapname=? AND playername=?", g_MapResName, playername)
			if #sql > 0 then -- check to see if the player has rated
				outputChatBox("You've rated this map " .. getRatingColorAsHex(sql[1].rating) .. sql[1].rating .. "/10#E1AA5A.",thePlayer,225, 170, 90, true)
			else
				outputChatBox("You've not yet rated this map, use /rate to rate!",thePlayer,225, 170, 90, true)
			end
		end
	end
)

addEventHandler('onResourceStart', resourceRoot,
	function()
		-- outputDebugString("delete mapratings "..tostring(executeSQLQuery("DROP TABLE mapratings")))
		-- Add table if required
		executeSQLQuery("CREATE TABLE IF NOT EXISTS mapratings (mapname TEXT, playername TEXT, rating INTEGER)")

		-- Create unique index to speed up WHERE when using [mapname] or [mapname+playername]
		if not executeSQLQuery("CREATE UNIQUE INDEX IF NOT EXISTS IDX_MAPRATINGS_MAPNAME_PLAYERNAME on mapRatings(mapname, playername)") then
			-- If create unique index has failed, remove duplicates before retrying

			-- Create a temp non-unique index to speed up deletion of duplicates
			executeSQLQuery("CREATE INDEX IF NOT EXISTS IDX_MAPRATINGS_MAPNAME_PLAYERNAME_temp on mapRatings(mapname, playername)")
			-- Delete duplicates
			executeSQLQuery("DELETE FROM mapRatings WHERE rowid in "
								.. " (SELECT A.rowid"
								.. " FROM mapRatings A, mapRatings B"
								.. " WHERE A.rowid > B.rowid AND A.mapname = B.mapname AND A.playername = B.playername)")
			-- Remove temp index
			executeSQLQuery("DROP INDEX IDX_MAPRATINGS_MAPNAME_PLAYERNAME_temp")
			-- Now this should work
			executeSQLQuery("CREATE UNIQUE INDEX IF NOT EXISTS IDX_MAPRATINGS_MAPNAME_PLAYERNAME on mapRatings(mapname, playername)")
		end

		-- Create non-unique index to speed up WHERE when using [playername]
		executeSQLQuery("CREATE INDEX IF NOT EXISTS IDX_MAPRATINGS_PLAYERNAME on mapRatings(playername)")

		-- Perform upgrade from an old version if necessary
		updateMapNames()

		local currentGamemodeMap = exports.mapmanager:getRunningGamemodeMap()
		if currentGamemodeMap then
			g_MapResName = getResourceName(currentGamemodeMap)
		end
	end
)

function updateMapRating(player, mapresname, rating)
	local playername = getPlayerName(player)
	local sql = executeSQLQuery("SELECT rating FROM mapratings WHERE mapname=? AND playername=?", mapresname, playername)
	if #sql > 0 then
		local success = executeSQLQuery("UPDATE mapratings SET rating=? WHERE mapname=? AND playername=?", rating, mapresname, playername)
		-- outputDebugString("mapratings: update mapratings "..playername.." "..rating.." "..tostring(success))
		if not success then return end
		if sql[1].rating == rating then
			outputChatBox("You already rated this map "..getRatingColorAsHex(rating)..rating.."/10#FF0000.", player, 255, 0, 0, true)
		else
			outputChatBox("Changed rating from "..getRatingColorAsHex(sql[1].rating)..sql[1].rating.."/10 #E1AA5Ato "..getRatingColorAsHex(rating)..rating.."/10#E1AA5A.", player, 225, 170, 90, true)
		end
	else
		local success = executeSQLQuery("INSERT INTO mapratings VALUES (?,?,?)", mapresname, playername, rating)
		-- outputDebugString("mapratings: insert mapratings "..playername.." "..rating.." "..tostring(success))
		if not success then return end
		outputChatBox("Rated '"..(getResourceInfo(getResourceFromName(mapresname), "name") or mapresname).."' "..getRatingColorAsHex(rating)..rating.."/10#E1AA5A.", player, 225, 170, 90, true)
		triggerEvent("onPlayerRateMap", player, mapresname, rating, getMapRating(mapresname))
	end
	triggerEvent("onMapRatingChange", player, getMapRating(mapresname), rating)
end

addEvent('onPollStarting')
addEventHandler('onPollStarting', root,
	function(poll)
		for index, item in ipairs(poll) do
			local mapname = item[1]
			local map = item[4]
			local filename = getResourceName(map)

			if map then
				-- Get the average rating
				local rating = getMapRating(getResourceName(map))
				rating = rating and rating.average or "N/A"

				-- Get the race type to add as a tag. eg: [R], [DD], [MG], [SR], [TW]
				local racetype = getResourceInfo(map, "racetype")
				if (not racetype) then
					racetype = "???"
					local meta = xmlLoadFile(":"..filename.."/meta.xml")
					local settingsNode = xmlFindChild(meta, "settings", 0)
					if (settingsNode) then
						local settings = xmlNodeGetChildren(settingsNode)
						for _, setting in ipairs(settings) do
							local attribute = xmlNodeGetAttribute(setting, "name")
							if (attribute == "#racetype") then
								racetype = xmlNodeGetAttribute(setting, "value")
								break
							end
						end
					end
				xmlUnloadFile(meta)
				end

				-- Get play count
				local playCount = getMapTimesPlayed(filename)
				playCount = playCount.outputstring

				-- Get the last start time
				local lastStart = getMapLastTimePlayed(filename)

				--mapname = "["..racetype.."] "..mapname.." —— "..rating..", "..lastStart.." ("..playCount..")"
				if (index == 9) then
					mapname = mapname.." ("..rating..")"
					--mapname = mapname.." —— "..rating -- For use with the old system of hard baked tags
				else
					mapname = "["..racetype.."] "..mapname.." ("..rating..") — "..lastStart
					--mapname = mapname.." —— "..rating..", "..lastStart -- For use with the old system of hard baked tags
				end
				item[1] = mapname
			end
		end
		triggerEvent('onPollModified', source, poll )
	end
)

function getMapTimesPlayed(mapresname)
	local playCount = 0
	local sqlPlayCount = executeSQLQuery("SELECT playedCount FROM race_mapmanager_maps WHERE resName=?", mapresname)
	if (#sqlPlayCount > 0) then
		playCount = sqlPlayCount[1].playedCount
	end
	local outputstring = tostring(playCount).." play"..(playCount~=1 and "s" or "")

	return {["formattedString"] = outputstring, ["playCount"] = playCount}
end

function getMapLastTimePlayed(mapresname)
	-- Get the last start time
	local lastStart
	local sqlLastTimePlayed = executeSQLQuery("SELECT lastTimePlayed FROM race_mapmanager_maps WHERE resName=?", mapresname)
	if (#sqlLastTimePlayed > 0) then
		lastStart = sqlLastTimePlayed[1].lastTimePlayed
		local currentT = getRealTime(false)
		local s = currentT.timestamp - lastStart
		local m = s/60
		local h = m/60
		-- local d = h/24
		-- local w = d/7
		-- if (w > 2) then
		-- 	lastStart = math.floor(w) .. " weeks ago"
		-- elseif (d > 2) then
		-- 	lastStart = math.floor(d) .. " days ago"
		-- elseif (h > 2) then
		-- 	lastStart = math.floor(h) .. " hours ago"
		-- elseif (m > 2) then
		-- 	lastStart = math.floor(m) .. " minutes ago"
		-- elseif (s < 0) then
		-- 	lastStart = "Recently"
		-- else
		-- 	lastStart = math.floor(s) .. " seconds ago"
		-- end
		if (h > 10) then
			lastStart = math.floor(h) .. " hours ago"
		elseif (h < 0) then
			lastStart = "Recently"
		else
			local hh = math.floor(h*10)/10
			lastStart = hh .. " hour"..(hh==1 and "" or "s").." ago"
		end

		return lastStart
	else return "Never" end
end

function getMapRating(mapresname)
	local sql = executeSQLQuery("SELECT AVG(rating) AS avg , COUNT(rating) AS count FROM mapratings WHERE mapname=?", mapresname)
	if sql[1].count > 0 then
		local avg = math.floor(sql[1].avg*100+0.5)/100
		return {average = avg, count = sql[1].count}
	end
	return false
end

function getPlayerRating(playername, mapresname)
	if mapresname then
		local sql = executeSQLQuery("SELECT rating FROM mapratings WHERE playername=? AND mapname=?", playername, mapresname)
		if #sql > 0 then
			return sql[1].rating
		end
	else
		local sql = executeSQLQuery("SELECT AVG(rating) AS avg , COUNT(rating) AS count FROM mapratings WHERE playername=?", playername)
		if sql[1].count > 0 then
			local avg = math.floor(sql[1].avg*100+0.5)/100
			return {average = avg, count = sql[1].count}
		end
	end
	return false
end

function getRatingColor(rating)
	local r, g = -5.1*(rating^2) + 25.5*rating + 255, -5.1*(rating^2) + 76.5*rating
	r, g = r > 255 and 255 or math.floor(r+0.5), g > 255 and 255 or math.floor(g+0.5)
	-- outputDebugString("mapratings: rating = "..rating.." r = "..r.." g = "..g)
	return {r,g,0}--"#"..string.format("%02X", r)..string.format("%02X", g).."00"
end

function getRatingColorAsHex(rating)
	local r, g = unpack(getRatingColor(rating))
	return "#"..string.format("%02X", r)..string.format("%02X", g).."00"
end

addCommandHandler('rate',
	function(player, cmd, rating)
		rating = tonumber(rating)
		if rating then
			if rating >= 0 and rating <= 10 then
				updateMapRating(player, g_MapResName, math.floor(rating*100+0.5)/100)
			else
				outputChatBox("Choose a rating between 0 and 10.", player, 255, 0, 0)
			end
		else
			outputChatBox("Choose a rating between 0 and 10.", player, 255, 0, 0)
		end
	end, false, false
)

function updateMapNames()
	-- local sql = executeSQLQuery("SELECT * FROM mapratings")
	-- local needUpdate
	-- if sql and #sql > 0 then
	-- 	for i=1,math.min(5,#sql) do
	-- 		if not getResourceFromName(sql[math.random(1,#sql)].mapname) then
	-- 			needUpdate = true
	-- 			break
	-- 		end
	-- 	end
	-- end
	-- if not needUpdate then return end
	-- outputChatBox( "Please wait while the map ratings are assimulated" )
	-- local maps = exports.mapmanager:getMaps()
	-- local infoMaps = {}
	-- for _,map in ipairs(exports.mapmanager:getMaps()) do
	-- 	infoMaps[getResourceInfo(map, "name") or getResourceName(map)] = getResourceName(map)
	-- end
	-- local reportTime = getTickCount()
	-- for i,row in ipairs(sql) do
	-- 	if getTickCount() - reportTime > 5000 then
	-- 		reportTime = getTickCount()
	-- 		outputChatBox( string.format("%2.2f%% done", i * 100 / #sql ) )
	-- 	end
	-- 	if infoMaps[row.mapname] then
	-- 		executeSQLQuery("UPDATE mapratings SET mapname=? WHERE mapname=?", infoMaps[row.mapname], row.mapname)
	-- 		--outputDebugString("mapratings: changed "..tostring(row.mapname).." to "..tostring(infoMaps[row.mapname]))
	-- 	elseif not getResourceFromName(row.mapname) then
	-- 		executeSQLQuery("DELETE FROM mapratings WHERE mapname=?", row.mapname)
	-- 		--outputDebugString("mapratings: deleted "..tostring(row.mapname))
	-- 	end
	-- end
end

function getMapRatingForPoll(mapresname)
	return getMapRating(mapresname)
end
function getMapLastTimePlayedForPoll(mapresname)
	return getMapLastTimePlayed(mapresname)
end
