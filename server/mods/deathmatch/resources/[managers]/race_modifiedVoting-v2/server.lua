maxPlayAgain = 2 -- number of times the play again option can be picked

playAgainCounter = 0

function modifyPoll(poll)
	local currentMap = exports.mapmanager:getRunningGamemodeMap() -- get the current map
	table.remove(poll,table.maxn(poll)) -- remove the last option of the poll

	if (playAgainCounter < maxPlayAgain) then
		table.insert(poll, {"Play again (" .. playAgainCounter+1 .. "/" .. maxPlayAgain .. ")", 'nextMapVoteResult', root, currentMap})
	end

	for index, item in ipairs(poll) do
			if item[1] == "Yes" then return end

			local mapname = item[1]
			local map = item[4]

			if (index ~= 8) then
				if map then
					local rating = getMapRating(getResourceName(map))
					if rating then
						mapname = mapname.." ("..(rating.average or "?")..")"
					end
					item[1] = mapname
				end
			else
				item[1] = "Random Map"
			end
	end

	for i=1,2,1 do
	table.remove(poll,1) -- remove extra options
	end

	triggerEvent('onPollModified', root, poll ) -- send the modified poll back
end
addEvent ("onPollStarting", true )
addEventHandler ("onPollStarting", root, modifyPoll)

-- function to reset the play again counter and to display the rating of the map that was started to every player.
function resetCounterCheck (resource)
	gamemode = getResourceInfo(resource, "gamemodes" )
	gamemodetype = getResourceInfo(resource, "type" )

	if (gamemode == "race" and gamemodetype == "map" ) then -- if a new map on the race gamemode is started
		if (resource == currentMap) then -- does not happen the first cycle because currentmap is undefined
			playAgainCounter = playAgainCounter + 1  -- add one to the counter if it's the same map
		else
			playAgainCounter = 0 -- else reset the counter
		end
		currentMap = resource -- the resource that was started becomes the map to compare with next time

		local mapresname = getResourceName(currentMap)
		for index,thePlayer in ipairs (getElementsByType("player")) do -- display rating for every player
			local playername = getPlayerName(thePlayer)
			local sql = executeSQLQuery("SELECT rating FROM mapratings WHERE mapname=? AND playername=?", mapresname, playername)
			if #sql > 0 then -- check to see if the player has rated
				outputChatBox("You've rated this map " .. getRatingColorAsHex(sql[1].rating) .. sql[1].rating .. "/10#E1AA5A.",thePlayer,225, 170, 90, true)
			else
				outputChatBox("You've not yet rated this map, use /rate to rate!",thePlayer,225, 170, 90, true)
			end
		end
	end
end
addEventHandler ( "onResourceStart", root, resetCounterCheck )

-- function to get the rating of a map
function getMapRating(mapresname)
	local sql = executeSQLQuery("SELECT AVG(rating) AS avg , COUNT(rating) AS count FROM mapratings WHERE mapname=?", mapresname)
	if sql[1].count > 0 then
		local avg = math.floor(sql[1].avg*100+0.5)/100
		return {average = avg, count = sql[1].count}
	end
	return false
end

-- functions to change the color of the rating (taken from the mapratings script)
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
