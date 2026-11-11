--
-- util_tt_server.lua
--

function clientCall(player, fnName, ...)
	triggerClientEvent(onlyJoined(player), 'onClientCall_tt', player, fnName, ...)
end

function onlyJoined(player)
	return player
end


g_AllowedRPCFunctions = {}

function allowRPC(...)
	for i,name in ipairs({...}) do
		g_AllowedRPCFunctions[name] = true
	end
end

addEvent('onServerCall_tt', true)
addEventHandler('onServerCall_tt', root,
	function(fnName, ...)
		if g_AllowedRPCFunctions[fnName] then
			local fn = _G
			for i,pathpart in ipairs(fnName:split('.')) do
				fn = fn[pathpart]
			end
			fn(...)
		end
	end
)



function isPlayerInACLGroup(player, groupName)
	local account = getPlayerAccount(player)
	if not account then
		return false
	end
	local accountName = getAccountName(account)
	for _,name in ipairs(string.split(groupName,',')) do
		local group = aclGetGroup(name)
		if group then
			for i,obj in ipairs(aclGroupListObjects(group)) do
				if obj == 'user.' .. accountName or obj == 'user.*' then
					return true
				end
			end
		end
	end
	return false
end


---------------------------------------------------------------------------
-- Version
---------------------------------------------------------------------------
function getBuildString()
	return getResourceInfo(getThisResource(), 'build') or 'n/a'
end

-----------------------------
-- Debug

function outputDebug( chan, msg )
	if _DEBUG_LOG then
		if not msg then
			msg = chan
			chan = 'UNDEF'
		end
		if table.find(_DEBUG_LOG,chan) then
			outputDebugString( getTickTimeStr() .. ' DEBUG_tt: ' .. msg )
		end
	end
	if g_PipeDebugTo then
		if not table.find(getElementsByType('player'), g_PipeDebugTo) then
			outputWarning( 'cleared g_PipeDebugTo' )
			g_PipeDebugTo = nil
		else
			outputConsole( getTickTimeStr() .. ' DEBUG_tt: ' .. (msg or chan), g_PipeDebugTo )
		end
	end
end


-- Always send to server window
-- and all client consoles
function outputWarning( msg )
	outputDebugString( getTickTimeStr() .. ' WARNING_tt: ' .. msg )
	outputConsole( getTickTimeStr() .. ' WARNING_tt: ' .. msg )
end

-- Always send to server window
-- and chat box window
function outputError( msg )
	outputDebugString( getTickTimeStr() .. ' ERROR_tt: ' .. msg )
	outputChatBox( getTickTimeStr() .. ' ERROR_tt: ' .. msg )
end


---------------------------------------------------------------------------
--
-- gets
--
---------------------------------------------------------------------------

-- get string or default
function getString(var,default)
	local result = get(var)
	if not result then
		return default
	end
	return tostring(result)
end

-- get number or default
function getNumber(var,default)
	local result = get(var)
	if not result then
		return default
	end
	return tonumber(result)
end

-- get true or false or default
function getBool(var,default)
	local result = get(var)
	if not result then
		return default
	end
	return result == 'true'
end


---------------------------------------------------------------------------
--
-- Misc
--
---------------------------------------------------------------------------
-- Returns "name" or "name(accountname)" if they differ
function getAdminNameForLog(player)
	local name = getPlayerName( player )
	if not isGuestAccount( getPlayerAccount( player ) ) then
		local accountName = getAccountName( getPlayerAccount( player ) )
		if name ~= accountName then
			return name.."("..accountName..")"
		end
	end
	return name
end


---------------------------------------------------------------------------
-- Paises (ip2c)
---------------------------------------------------------------------------

-- Codigo ISO de 2 letras en minusculas, o "" si ip2c no esta disponible.
function getPlayerCountry(player)
	local ip2c = getResourceFromName("ip2c")
	if ip2c and getResourceState(ip2c) == "running" and isElement(player) then
		local code = exports.ip2c:getPlayerCountry(player)
		if type(code) == "string" and code ~= "" then
			return string.lower(code)
		end
	end
	return ""
end

-- Rellena el pais de los records existentes de este jugador que aun no lo
-- tengan (backfill), en la DB y en la copia en memoria del mapa actual.
function backfillPlayerCountry(player)
	if not isElement(player) then return end
	local country = getPlayerCountry(player)
	if country == "" then return end

	local serial = getPlayerSerial(player)
	if not serial or serial == "" then return end

	executeSQLQuery("UPDATE maptimes SET playerCountry=? WHERE (playerCountry IS NULL OR playerCountry='') AND playerSerial=?", country, serial)

	local account = getPlayerAccount(player)
	if account and not isGuestAccount(account) then
		local accountName = getAccountName(account)
		if accountName and accountName ~= "" then
			executeSQLQuery("UPDATE maptimes SET playerCountry=? WHERE (playerCountry IS NULL OR playerCountry='') AND playerAccount=?", country, accountName)
		end
	end

	local mgr = g_SToptimesManager
	if mgr and mgr.mapTimes and mgr.mapTimes.dbTable and mgr.mapTimes.dbTable.rows then
		local changed = false
		for _, row in ipairs(mgr.mapTimes.dbTable.rows) do
			if (row.playerCountry == nil or row.playerCountry == "") and row.playerSerial == serial then
				row.playerCountry = country
				changed = true
			end
		end
		if changed then
			mgr:updateTopText()
		end
	end
end

