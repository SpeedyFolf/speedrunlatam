--
-- maptimes_server.lua
--

SMaptimes = {}
SMaptimes.__index = SMaptimes
SMaptimes.instances = {}


---------------------------------------------------------------------------
--
-- SMaptimes:create()
--
-- Create a SMaptimes instance
--
---------------------------------------------------------------------------
function SMaptimes:create( mapName, statskey )
	local id = #SMaptimes.instances + 1
	SMaptimes.instances[id] = setmetatable(
		{
			id 				= id,
			mapName			= mapName,
			statskey		= statskey,
			dbTable			= nil,
		},
		self
	)
	SMaptimes.instances[id]:postCreate()
	return SMaptimes.instances[id]
end


---------------------------------------------------------------------------
--
-- SMaptimes:destroy()
--
-- Destroy a SMaptimes instance
--
---------------------------------------------------------------------------
function SMaptimes:destroy()
	self.dbTable:destroy()
	SMaptimes.instances[self.id] = nil
	self.id = 0
end


---------------------------------------------------------------------------
--
-- SMaptimes:postCreate()
--
--
--
---------------------------------------------------------------------------
function SMaptimes:postCreate()
	local mapName = self.mapName
	local statskey = self.statskey
	local columns = { 		'mapName', 	'playerName', 	'playerSerial', 	'time', 	'dateRecorded',		'playerAccount' }
	local columnTypes = { 	'TEXT', 	'TEXT', 		'TEXT', 			'INTEGER', 	'INTEGER',			'TEXT' }
	self.dbTable = SDatabaseTable:create( mapName, statskey, columns, columnTypes )
end


---------------------------------------------------------------------------
--
-- SMaptimes:validateDbTableRow()
--
-- Make sure each cell in the row contains a valid value
--
---------------------------------------------------------------------------
function SMaptimes:validateDbTableRow( index )
	local row = self.dbTable.rows[index]
	row.mapName					= tostring(row.mapName) or 'mapName'
	row.playerName				= tostring(row.playerName) or 'playerName'
	row.playerSerial			= tostring(row.playerSerial) or 'playerSerial'
	row.time					= tonumber(row.time) or 0
	row.dateRecorded			= tonumber(row.dateRecorded) or 0
	row.playerAccount			= tostring(row.playerAccount) or 'playerAccount'
end

---------------------------------------------------------------------------
--
-- SMaptimes:load()
--
--
--
---------------------------------------------------------------------------
function SMaptimes:load()
	self.dbTable:load()

	-- Make sure each cell in the table contains a valid value - saves lots of checks later
	for i,row in ipairs(self.dbTable.rows) do
		self:validateDbTableRow( i )
	end
end

---------------------------------------------------------------------------
--
-- SMaptimes:getToptimes()
--
-- Return a table of the top 'n' toptimes
--
---------------------------------------------------------------------------
function SMaptimes:getToptimes( howMany )

	local result = {}

	for i=1,howMany do
		if i <= #self.dbTable.rows then
			result[i] = {
							time			= self.dbTable.rows[i].time,
							playerName		= self.dbTable.rows[i].playerName,
							dateRecorded 	= self.dbTable.rows[i].dateRecorded,
						}
		else
			result[i] = {
							time			= 0,
							playerName		= '-- Empty --',
							dateRecorded 	= 0,
						}
		end
	end

	return result
end


---------------------------------------------------------------------------
--
-- SMaptimes:getValidEntryCount()
--
-- Return a count of the number of toptimes
--
---------------------------------------------------------------------------
function SMaptimes:getValidEntryCount()
	return #self.dbTable.rows
end

---------------------------------------------------------------------------
--
-- SMaptimes:addPlayer()
--
--
--
---------------------------------------------------------------------------
function SMaptimes:addPlayer( player )

	table.insert( self.dbTable.rows, {
									mapName					= self.mapName,
									playerName				= getPlayerNameColored(player),
									playerSerial			= getPlayerSerial(player),
									time					= 0,
									dateRecorded			= 0,
									playerAccount			= getAccountName(getPlayerAccount(player)),
								} )

	-- Make sure new row has valid values
	self:validateDbTableRow( #self.dbTable.rows )

	return #self.dbTable.rows
end

---------------------------------------------------------------------------
--
-- SMaptimes:getIndexForPlayer()
--
-- Can return false if player has no entry
--
---------------------------------------------------------------------------
function SMaptimes:getIndexForPlayer( player )

	if self.statskey == 'serial' then
		-- Find player by serial
		local serial = getPlayerSerial(player)
		for i,row in ipairs(self.dbTable.rows) do
			if serial == row.playerSerial then
				return i
			end
		end
	elseif self.statskey == 'account' then
		-- Find player by account name
		local account = getAccountName(getPlayerAccount(player))
		for i, row in ipairs(self.dbTable.rows) do
			if account == row.playerAccount then
				return i
			end
		end
	else
		-- Find player by name
		local name = removeColorCoding(getPlayerNameColored(player))
		for i,row in ipairs(self.dbTable.rows) do
			if name == removeColorCoding(row.playerName) then
				return i
			end
		end
	end

	return false
end



---------------------------------------------------------------------------
--
-- SMaptimes:getPositionForTime()
--
-- Always succeeds
--
---------------------------------------------------------------------------
function SMaptimes:getPositionForTime( time, dateRecorded )

	for i,row in ipairs(self.dbTable.rows) do
		if time < row.time then
			return i
		end
		if time == row.time and dateRecorded < row.dateRecorded then
			return i
		end
	end

	return #self.dbTable.rows + 1
end


---------------------------------------------------------------------------
--
-- SMaptimes:getTimeForPlayer()
--
-- Can return false if player has no entry
--
---------------------------------------------------------------------------
function SMaptimes:getTimeForPlayer( player )

	local i = self:getIndexForPlayer( player )

	if not i then
		return false
	end

	return self.dbTable.rows[i].time

end


---------------------------------------------------------------------------
--
-- SMaptimes:getTextForPlayer()
--
-- Can return false if player has no entry
--
---------------------------------------------------------------------------
function SMaptimes:getTextForPlayer( player )

	local i = self:getIndexForPlayer( player )

	if not i then
		return false
	end

	return self.dbTable.rows[i].time, self.dbTable.rows[i].playerName, self.dbTable.rows[i].dateRecorded

end

---------------------------------------------------------------------------
--
-- SMaptimes:setTimeForPlayer()
--
-- Update the time for this player
--
---------------------------------------------------------------------------
function SMaptimes:setTimeForPlayer( player, time, dateRecorded )

	-- Find current entry for player
	local oldIndex = self:getIndexForPlayer( player )

	if not oldIndex then
		-- No entry yet, so add it to the end
		oldIndex = self:addPlayer( player )
		if oldIndex ~= self:getIndexForPlayer( player ) then
			outputError( "oldIndex ~= self:getIndexForPlayer( player )" )
		end
	end

	-- Copy it out and then remove it from the table
	local row = self.dbTable.rows[oldIndex]
	table.remove( self.dbTable.rows, oldIndex )

	-- Update it
	row.playerName		= getPlayerNameColored(player)	 -- Refresh the name
	row.time			= time
	row.dateRecorded	= dateRecorded


	-- Put it back in at the correct position to maintain sort order
	local newIndex = self:getPositionForTime( row.time, row.dateRecorded )
	self.dbTable:saveTime(newIndex, row)
end

---------------------------------------------------------------------------
--
-- SMaptimes:deletefirst()
--
-- Remove the best time from this map
--
---------------------------------------------------------------------------
function SMaptimes:deletetime(place)

	place = tonumber(place) or 1

	-- Remove the first row
	if #self.dbTable.rows >= place then
		-- Copy it out and then remove it from the table
		local row = self.dbTable.rows[place]
		self.dbTable.rows[place].teamColorR = 255
		self.dbTable.rows[place].teamColorR = 255
		self.dbTable.rows[place].teamColorR = 255
		table.remove( self.dbTable.rows, place )
		self.dbTable:deleteTime(row)
		return row
	end

	return false
end
