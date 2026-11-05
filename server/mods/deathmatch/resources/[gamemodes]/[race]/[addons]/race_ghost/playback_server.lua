addEvent"onMapStarting"

GhostPlayback = {}
GhostPlayback.__index = GhostPlayback

GhostFileNames = {}
GhostFileNamesCount = 0
UsedGhosts = {}
TopPlayback = nil

function GhostPlayback:create( map )
	local result = {
		map = map,
		bestTime = math.huge,
		racer = "",
		recording = {},
		hasGhost = false,
		ped = nil,
		vehicle = nil
		-- blip = nil
	}
	return setmetatable( result, self )
end

function GhostPlayback:destroy()
	if self.hasGhost then
		triggerClientEvent( "clearMapGhost", root )
	end
	self.ped = nil
	self.vehicle = nil
end

function GhostPlayback:deleteGhost()
	local mapName = getResourceName( self.map )
	-- if fileExists( "ghosts/" .. mapName .. ".ghost" ) then
	-- 	fileDelete( "ghosts/" .. mapName .. ".ghost" )
	-- 	self:destroy()
	-- 	playback = nil
	-- 	return true
	-- end
	return false
end

function getGhostsForMap(map)
	local runs = {}
	local mapName = getResourceName( map )
	local toc = xmlLoadFile("ghosts/" .. mapName .. ".toc")
	-- Look for a table of contents. If it doesn't exist, make it
	if not toc then
		-- Look for old file (backwards compatibility)
		local fileName = "ghosts/" .. mapName .. ".ghost"
		local old = xmlLoadFile( fileName )
		if not old then
			-- Look for .backup instead
			fileName = "ghosts/" .. mapName .. ".backup"
			local old = xmlLoadFile( fileName )
		end
		if old then
			-- Found old file, write it to a new table of contents
			xmlUnloadFile( old )

			toc = xmlCreateFile( "ghosts/" .. mapName .. ".toc", "toc")
			if toc then
				local top = xmlCreateChild( toc, "top" )
				if (top) then
					xmlNodeSetAttribute( top, "f", fileName)
				end
				xmlSaveFile( toc )
			end
			runs["top"] = fileName
			xmlUnloadFile( toc )
		end
		return runs
	end
	-- toc exists. Read it
	local nodes = xmlNodeGetChildren(toc)
	for i,v in ipairs(nodes) do
		runs[xmlNodeGetName(v)] = xmlNodeGetAttribute(v, "f")
	end
	xmlUnloadFile( toc )
	return runs
end

function GhostPlayback:validateGhost()
	-- Validate
	local bValidForMap = isBesttimeValidForMap( self.map, self.bestTime )
	local bValidForRecording = isBesttimeValidForRecording( self.recording, self.bestTime )
	if not bValidForMap or not bValidForRecording then

		-- TODO: Erase the time from the toc

		-- -- Use backup file if it exists
		-- local backup = xmlLoadFile( "ghosts/" .. mapName .. ".backup" )
		-- if backup then
		-- 	xmlUnloadFile( backup )
		-- 	copyFile( "ghosts/" .. mapName .. ".ghost", "ghosts/" .. mapName .. ".invalid" )
		-- 	copyFile( "ghosts/" .. mapName .. ".backup", "ghosts/" .. mapName .. ".ghost" )
		-- 	fileDelete( "ghosts/" .. mapName .. ".backup" )
		-- 	outputDebugServer( "Trying backup as found an invalid ghost file", mapName, nil, " (Besttime not valid for recording. Error: " .. getRecordingBesttimeError( self.recording, self.bestTime ) .. ")" )
		-- 	self.recording = {}
		-- 	return self:loadGhost()
		-- end
		if not bValidForMap then
			outputDebugServer( "Found an invalid ghost file", mapName, nil, " (Besttime not valid for map. Error: " .. getMapBesttimeError( self.map, self.bestTime ) .. ")" )
		end
		if not bValidForRecording then
			outputDebugServer( "Found an invalid ghost file", mapName, nil, " (Besttime not valid for recording. Error: " .. getRecordingBesttimeError( self.recording, self.bestTime ) .. ")" )
		end
		return false
	end
	return true
end

function GhostPlayback:createStartpoint ()
	for _, v in ipairs( self.recording ) do
		if v.ty == "st" then
			if g_GameOptions.validatespawn then
				-- Check start is near a spawnpoint
				local bestDist = math.huge
				for _,spawnpoint in ipairs(getElementsByType("spawnpoint")) do
					bestDist = math.min( bestDist, getDistanceBetweenPoints3D( v.x, v.y, v.z, getElementPosition(spawnpoint) ) )
				end
				-- if bestDist > 5 then
				-- 	for _,spawnpoint in ipairs(getElementsByType("spawnpoint_onfoot")) do
				-- 		bestDist = math.min( bestDist, getDistanceBetweenPoints3D( v.x, v.y, v.z, getElementPosition(spawnpoint) ) )
				-- 	end
				-- end
				if bestDist > 5 then
					outputDebugServer( "Found an invalid ghost file", mapName, nil, " (Spawn point too far away - " .. bestDist .. ")" )
					return false
				end
			end
			self.ped = { p = v.p, x = v.x, y = v.y, z = v.z }
			self.vehicle = { m = v.m, x = v.x, y = v.y, z = v.z, rx = v.rX, ry = v.rY, rz = v.rZ }
			outputDebugServer( "Found a valid ghost", self.racer, nil, " (Besttime dif: " .. getRecordingBesttimeError( self.recording, self.bestTime ) .. ")" )
			self.hasGhost = true
			self.recordingParsed = toJSON(self.recording, true)
			return true
		end
	end

	return false -- no spawn point??
end

local function fetchGhostFileContents (ghostResourceName, callbackFunction)
	if not ghostResourceName then
		return
	end

	local function fetchLocalGhostFile ()
		if not fileExists(ghostResourceName) then
			outputDebugServer( "No ghost file", mapName, nil )
			return
		end

		local ghostFile = readGhostFile(ghostResourceName)

		if not ghostFile then
			outputDebug( "Invalid ghost file", mapName, nil )
			return
		end

		local json
		if isLegacyGhost(ghostFile) then
			json = legacyConvert(ghostFile)

			-- Save legacy after converting
			saveGhostFile(ghostResourceName, json)
			ghostFile = toJSON (json, true)
		end

		callbackFunction (ghostFile)
	end

	if g_GameOptions.ghostserverurl == "" then
		fetchLocalGhostFile (ghostResourceName, callbackFunction)
		return
	end

	iprint(g_GameOptions.ghostserverurl)
	fetchRemote (
		g_GameOptions.ghostserverurl .. "/ghost?name=" .. ghostResourceName,
		function ( data, statusCode )
			if statusCode == 0 then
				callbackFunction (data)
			else
				iprint("Failed to fetch ghost from remote server with status code: " .. tostring(statusCode))
				fetchLocalGhostFile (ghostResourceName, callbackFunction)
			end
		end
	)
end

function GhostPlayback:fetchGhostFile(ghostResourceName, callbackFunction)
	if not ghostResourceName then
		return
	end

	fetchGhostFileContents (
		ghostResourceName,
		function (data)
			callbackFunction (fromJSON(data))
		end
	)
end

function GhostPlayback:loadGhost(ghostResourceName, mapName, callbackFunction, ...)
	self:fetchGhostFile (
		ghostResourceName,
		function (json)
			self.racer = json.racer
			self.bestTime = tonumber(json.bestTime) or math.huge
			self.recording = json.recording

			if self:validateGhost () and self:createStartpoint() then
				callbackFunction (unpack(arg))
				return true
			end
		end
	)

end

function GhostPlayback:sendGhostData( target, playbackID )
	if self.hasGhost then
		triggerClientEvent( target or root, "onClientGhostDataReceive", root, self.recordingParsed, self.bestTime, self.racer, self.ped, self.vehicle, playbackID )
	end
end

function GhostPlayback:broadcastGhostData (playbackID)
	-- iprint("Sending", playbackID)
	for i, v in pairs(getElementsByType("player")) do
		self:sendGhostData(v, playbackID)
	end
end

addEventHandler( "onMapStarting", root,
	function()
		GhostPlayers = 0
		ReportedPlayers = 0
		TotalPlayers = #getElementsByType("player")

		if TopPlayback then
			TopPlayback:destroy()
		end
		if (personalPlaybacks) then
			for _, v in pairs(personalPlaybacks) do
				v:destroy()
			end
		end
		if (extraPlaybacks) then
			for _, v in pairs (extraPlaybacks) do
				v:destroy()
			end
		end

		local mapName = exports.mapmanager:getRunningGamemodeMap()

		if (get("*" .. getResourceName( mapName ) .. ".disableraceghosts")) then
			triggerClientEvent( "disableGhostsForThisMap", root )
			return
		end

		GhostFileNames = getGhostsForMap(mapName)
		GhostFileNamesCount = 0
		for _,_ in pairs(GhostFileNames) do
			GhostFileNamesCount = GhostFileNamesCount + 1
		end
		UsedGhosts = {}

		tickCount = getTickCount()
		tickCount2 = tickCount
		tickCountDiff = 0

		local topFileName = GhostFileNames["top"]
		local topGhost = nil

		-- The original WR ghost
		TopPlayback = GhostPlayback:create( mapName )
		topFileName = GhostFileNames["top"]
		topGhost = TopPlayback:loadGhost(
			topFileName, getResourceName(mapName),
			function () TopPlayback:broadcastGhostData("Top") end
		)
		for i, v in pairs(GhostFileNames) do
			-- Remove duplicate entries (PBs)
			if i ~= "top" and v == GhostFileNames["top"] then
				UsedGhosts[i] = v
				GhostFileNames[i] = nil
				GhostFileNamesCount = GhostFileNamesCount - 1
			end
		end
		GhostFileNames["top"] = nil
		GhostFileNamesCount = GhostFileNamesCount - 1

		tickCount2 = getTickCount()
		tickCountDiff = tickCount2 - tickCount
		-- iprint(tickCountDiff .. " ms | Top ghost loaded")
		tickCount = tickCount2

		local extraPlaybacks = {}
		local extraPlaybackCount = g_GameOptions.fillplayerslots - #getElementsByType("player")
		local extraGhostNumber = 1
		while (extraPlaybackCount > 0 and GhostFileNamesCount > 0) do
			local xRandom = math.random(1, GhostFileNamesCount)
			local xCount = 0
			for i, v in pairs(GhostFileNames) do
				xCount = xCount + 1
				if (xCount == xRandom) then
					local xGhost = GhostPlayback:create( mapName )

					xGhost:loadGhost(v, getResourceName(mapName), function (extraGhostNumber)
								 -- iprint("Sending extra ghost " .. extraGhostNumber)
								 xGhost:broadcastGhostData (extraGhostNumber)
					end, extraGhostNumber)
					table.insert(extraPlaybacks, xGhost)
					extraGhostNumber = extraGhostNumber + 1

					extraPlaybackCount = extraPlaybackCount - 1
					UsedGhosts[i] = v
					GhostFileNames[i] = nil
					GhostFileNamesCount = GhostFileNamesCount - 1
					break
				end
			end
		end
	end
)

addEvent("onClientRequestPBGhost", true)
addEventHandler( "onClientRequestPBGhost", root,
	function(mapName)
		local pName = removeColorCoding(getPlayerName(source))
		local pIndex = "pb_" .. pName:gsub('[%p%c%s]', '')
		local pFile = GhostFileNames[pIndex] or UsedGhosts[pIndex]

		local sourceElement = source -- this is important because source is not available in the callback functions

		if (not pFile) then return end

		fetchGhostFileContents (
			pFile,
			function(data)
				-- iprint("PB ghost loaded and sent to " .. pName .. data)
				triggerClientEvent(sourceElement, "onServerSentPBGhost", resourceRoot, data, mapName)
			end
		)

		tickCount2 = getTickCount()
		tickCountDiff = tickCount2 - tickCount
		-- iprint(tickCountDiff .. " ms | PB ghost loaded and sent to " .. pName)
		tickCount = tickCount2
	end
)

-- 	-- Find PB ghosts for each player
-- 	local ghostsFound = {}
-- 	for i, v in pairs(getElementsByType("player")) do
-- 		local vName = removeColorCoding((getPlayerName(v)))
-- 		local vGhost = GhostPlayback:create( mapName )
-- 		local vFile = "pb_" .. vName:gsub('[%p%c%s]', '')
-- 		if (ghostFileNames[vFile]) then
-- 			-- vGhost:loadGhost(ghostFileNames[vFile])
-- 			ghostsFound[v] = vFile
-- 			-- ghostsCount = ghostsCount + 1
-- 			-- ghostFileNames[vFile] = nil
-- 		end
-- 	end
-- 	return ghostsFound

addEventHandler( "onPlayerJoin", root,
	function()
		triggerClientEvent( source, "race_ghost.updateOptions", resourceRoot, g_GameOptions ); -- We need to send server settings first or it's going to throw errors
		if TopPlayback then
			TopPlayback:sendGhostData( source )
		end
		if personalPlayback then
			vName = removeColorCoding((getPlayerName(source)))
			personalPlayback:loadGhost("pb_" .. vName:gsub('[%p%c%s]', ''))
			personalPlayback:sendGhostData(source, "pb")
		end
	end
)
