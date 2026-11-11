--
-- databasetable_server.lua
--
-- A Lua table which is loaded/saved from the sqlite database
-- Handled column types are TEXT and INTEGER
--

SDatabaseTable = {}
SDatabaseTable.__index = SDatabaseTable
SDatabaseTable.instances = {}


---------------------------------------------------------------------------
--
-- SDatabaseTable:create()
--
--
--
---------------------------------------------------------------------------
function SDatabaseTable:create(name,statskey,columns,columnTypes)
    local id = #SDatabaseTable.instances + 1
    SDatabaseTable.instances[id] = setmetatable(
        {
            id = id,
            name = name,
            statskey = statskey,
            columns = columns,
            columnTypes = columnTypes,
            rows = {},
        },
        self
    )
    SDatabaseTable.instances[id]:postCreate()
    return SDatabaseTable.instances[id]
end


---------------------------------------------------------------------------
--
-- SDatabaseTable:destroy()
--
--
--
---------------------------------------------------------------------------
function SDatabaseTable:destroy()
    SDatabaseTable.instances[self.id] = nil
    self.id = 0
    ped = nil
    vehicle = nil
end


---------------------------------------------------------------------------
--
-- SDatabaseTable:postCreate()
--
--
--
---------------------------------------------------------------------------
function SDatabaseTable:postCreate()
    -- Set column types as strings if not set
    while #self.columnTypes < #self.columns do
        table.insert( self.columnTypes, 'TEXT' )
    end
end


---------------------------------------------------------------------------
--
-- SDatabaseTable:safestring()
--
--
--
---------------------------------------------------------------------------
function safestring( s )
    -- escape '
    return s:gsub( "(['])", "''" )
end

function qsafestring( s )
    -- ensure is wrapped in '
    return "'" .. safestring(s) .. "'"
end


---------------------------------------------------------------------------
--
-- SDatabaseTable:load()
--
--
--
---------------------------------------------------------------------------
function SDatabaseTable:load()
	for i=1,10 do
        if self:tryLoad() then
            return
        end
    end
end

---------------------------------------------------------------------------
--
-- SDatabaseTable:tryLoad()
--
--
--
---------------------------------------------------------------------------
function SDatabaseTable:tryLoad()
    outputDebug( 'TOPTIMES', 'SDatabaseTable: Loading ' .. self.name )
    self.rows = {}

    local groupKey = "playerName"
    if self.statskey == "account" then
        groupKey = "playerAccount"
    elseif self.statskey == "serial" then
        groupKey = "playerSerial"
    end
    local cmd

    -- SELECT
    -- Build command
	cmd = "SELECT MIN(time) as time,playerName,playerSerial,mapName,dateRecorded,playerAccount,playerCountry from maptimes WHERE mapName = ? GROUP BY "..groupKey.." ORDER BY time"
    local sqlResults = executeSQLQuery( cmd, self.name )

    if not sqlResults then
        return false
    end

    -- Process into rows
    self.rows = {}
    for r,sqlRow in ipairs(sqlResults) do
        local row = {}
        for c,column in ipairs(self.columns) do
            row[column] = sqlRow[column]
        end
        table.insert( self.rows, row )
    end

    -- Make copy to detect changes
    self.rowsCopy = table.deepcopy(self.rows)

    return true
end


---------------------------------------------------------------------------
--
-- SDatabaseTable:saveTime()
--
--
--
---------------------------------------------------------------------------
function SDatabaseTable:saveTime(index, row)
	table.insert( self.rows, index, row )
	local cmd = 'INSERT INTO maptimes VALUES ('
	for c=1,#self.columns do
		if c > 1 then
			cmd = cmd .. ', '
		end
		local key = self.columns[c]
		if key == "mapName" then
			cmd = cmd .. "?"
		elseif type(row[key]) == 'number' then
			cmd = cmd .. row[key] or 0
		else
			cmd = cmd .. qsafestring( row[key] or '' )
		end
	end
	cmd = cmd .. ')'
	executeSQLQuery( cmd, row.mapName )
end

---------------------------------------------------------------------------
--
-- SDatabaseTable:deleteTime()
--
--
--
---------------------------------------------------------------------------
function SDatabaseTable:deleteTime(row)
	local cmd = 'DELETE FROM maptimes WHERE mapName == ? AND playerName == ? AND time == ?'
	executeSQLQuery( cmd, row.mapName, row.playerName, row.time )
end


-- addCommandHandler( "droptable",
--     function(player)
		-- cmd = 'DROP TABLE maptimes'
        -- executeSQLQuery( cmd )
		-- iprint(">:)")
--     end
-- )
