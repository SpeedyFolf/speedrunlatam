local db = dbConnect('sqlite', ':/tuning.db')
dbExec(db, 'CREATE TABLE IF NOT EXISTS tuning (owner TEXT NOT NULL, model INTEGER NOT NULL, data TEXT NOT NULL, PRIMARY KEY(owner, model))')
dbExec(db, 'CREATE TABLE IF NOT EXISTS tuning_global (owner TEXT PRIMARY KEY, data TEXT NOT NULL)')
local globalCache = {}
local currentMap = nil
local function blockedName(name)
	if not name then
		return false
	end
	name = tostring(name):lower()
	for entry, enabled in pairs(VC_BLACKLIST or {}) do
		if enabled and tostring(entry):lower() == name then
			return true
		end
	end
	return false
end

local function getActiveMap()
	if currentMap and getResourceState(currentMap) == 'running' then
		return currentMap
	end

	currentMap = nil
	local mapManager = getResourceFromName('mapmanager')
	if mapManager and getResourceState(mapManager) == 'running' then
		currentMap = exports.mapmanager:getRunningGamemodeMap()
	end
	return currentMap
end

local function isBlocked()
	local r = getActiveMap()
	return r and (blockedName(getResourceName(r)) or blockedName(getResourceInfo(r, 'name'))) or false
end

local function syncBlocked()
	triggerClientEvent(root, 'vc:mapBlocked', resourceRoot, isBlocked())
end

addEventHandler('onGamemodeMapStart', root, function(mapResource)
	currentMap = mapResource
	setTimer(syncBlocked, 100, 1)
end)

addEventHandler('onGamemodeMapStop', root, function(mapResource)
	if currentMap == mapResource then
		currentMap = nil
		setTimer(syncBlocked, 100, 1)
	end
end)

local cache = {}
local last = {}
local function owner(p)
	local account = getPlayerAccount(p)
	if account and not isGuestAccount(account) then
		return 'account:' .. getAccountName(account)
	end
	return 'serial:' .. getPlayerSerial(p)
end

local function validModel(model)
	model = tonumber(model)
	return model and model >= 400 and model <= 611 and getVehicleNameFromModel(model) ~= false
end

local function clean(p, model, data)
	if type(data) ~= 'table' or not validModel(model) then
		return nil
	end
	local result = {
		colors = {},
		upgrades = {},
		paintjob = 3
	}

	for i = 1, 12 do
		local n = tonumber(data.colors and data.colors[i])
		result.colors[i] = math.max(0, math.min(255, math.floor(n or 255)))
	end

	local pj = tonumber(data.paintjob)
	if pj and pj >= 0 and pj <= 3 then
		result.paintjob = math.floor(pj)
	end
	local probe = createVehicle(tonumber(model), 0, 0, -1000)
	if not probe then
		return nil
	end
	local compatible = {}
	for slot = 0, 16 do
		for _, id in ipairs(getVehicleCompatibleUpgrades(probe, slot) or {}) do
			compatible[id] = slot
		end
	end

	destroyElement(probe)
	local used = {}
	for _, id in ipairs(data.upgrades or {}) do
		id = tonumber(id)
		if id and compatible[id] and compatible[id] ~= 8 and compatible[id] ~= 9 and not used[compatible[id]] then
			table.insert(result.upgrades, id)
			used[compatible[id]] = true
		end
	end
	return result
end

local function load(p)
	if not isElement(p) then
		return
	end
	local rows = dbPoll(dbQuery(db, 'SELECT model,data FROM tuning WHERE owner=?', owner(p)), -1) or {}
	cache[p] = {}
	local grow = dbPoll(dbQuery(db, 'SELECT data FROM tuning_global WHERE owner=?', owner(p)), -1) or {}
	globalCache[p] = grow[1] and fromJSON(grow[1].data) or nil
	for _, row in ipairs(rows) do
		local decoded = fromJSON(row.data)
		if type(decoded) == 'table' then
			cache[p][tonumber(row.model)] = decoded
		end
	end
end

local function apply(p, v)
	if not isElement(p) or not isElement(v) or getElementType(v) ~= 'vehicle' or getVehicleOccupant(v, 0) ~= p then
		return
	end
	if isBlocked() then
		return
	end
	local data = cache[p] and cache[p][getElementModel(v)]
	if not data and not globalCache[p] then
		return
	end
	-- Remove only visual upgrades; leave nitro and hydraulics controlled by the map.
	if data then
		for slot = 0, 16 do
			if slot ~= 8 and slot ~= 9 then
				local id = getVehicleUpgradeOnSlot(v, slot)
				if id and id ~= 0 then
					removeVehicleUpgrade(v, id)
				end
			end
		end

		setVehicleColor(v, unpack(data.colors))
		setVehiclePaintjob(v, data.paintjob or 3)
		for _, id in ipairs(data.upgrades or {}) do
			addVehicleUpgrade(v, id)
		end
	end

	local g = globalCache[p]
	if g then
		if g.useColors and type(g.colors) == 'table' then
			setVehicleColor(v, unpack(g.colors))
		end
		if g.useWheels and g.wheel and g.wheel ~= 0 then
			-- Slot 7 is wheels in MTA. GTA SA standard wheel upgrades can be applied to many vehicles even when the compatible upgrades query doesn't enumerate them consistently.
			local old = getVehicleUpgradeOnSlot(v, 7)
			if old ~= g.wheel then
				if old and old ~= 0 then
					removeVehicleUpgrade(v, old)
				end
				addVehicleUpgrade(v, g.wheel)
			end
		end
	end
end

addEventHandler('onPlayerJoin', root, function()
	load(source)
	setTimer(function(p)
		if isElement(p) then
			triggerClientEvent(p, 'vc:mapBlocked', resourceRoot, isBlocked())
		end
	end, 750, 1, source)
end)

addEventHandler('onResourceStart', resourceRoot, function()
	for _, p in ipairs(getElementsByType('player')) do
		load(p)
	end

	setTimer(syncBlocked, 500, 1)
	setTimer(function()
		for _, p in ipairs(getElementsByType('player')) do
			local v = getPedOccupiedVehicle(p)
			if v and getVehicleOccupant(v, 0) == p then
				apply(p, v)
			end
		end
	end, 1200, 1)
end)

addEventHandler('onPlayerQuit', root, function()
	cache[source] = nil
	globalCache[source] = nil
	last[source] = nil
end)

addEventHandler('onVehicleEnter', root, function(p, seat)
	if seat == 0 then
		local v = source
		setTimer(function()
			apply(p, v)
		end, 150, 1)
	end
end)

-- Race can warp the player into a new vehicle without onVehicleEnter; detect changes.
setTimer(function()
	for _, p in ipairs(getElementsByType('player')) do
		local v = getPedOccupiedVehicle(p)
		local model = v and getElementModel(v)
		if last[p] ~= v or (v and getElementData(v, 'vc_last_model') ~= model) then
			last[p] = v
			if v then
				setElementData(v, 'vc_last_model', model, false)
				setTimer(function()
					apply(p, v)
				end, 250, 1)
			end
		end
	end
end, 500, 0)

addEvent('vc:request', true)
addEventHandler('vc:request', resourceRoot, function(model)
	local p = client
	if not isElement(p) or not validModel(model) or isBlocked() then
		return
	end
	triggerClientEvent(p, 'vc:loaded', resourceRoot, tonumber(model), cache[p] and cache[p][tonumber(model)] or false)
end)

addEvent('vc:save', true)
addEventHandler('vc:save', resourceRoot, function(model, data)
	local p = client
	if not isElement(p) or isBlocked() then
		return
	end
	model = tonumber(model)
	local safe = clean(p, model, data)
	if not safe then
		return
	end
	cache[p] = cache[p] or {}
	cache[p][model] = safe
	dbExec(db, 'INSERT OR REPLACE INTO tuning (owner,model,data) VALUES (?,?,?)', owner(p), model, toJSON(safe, true))
	local v = getPedOccupiedVehicle(p)
	if v and getElementModel(v) == model then
		apply(p, v)
	end
	triggerClientEvent(p, 'vc:saved', resourceRoot, model)
end)

local allowedWheels = {
	[1073] = true,
	[1074] = true,
	[1075] = true,
	[1076] = true,
	[1077] = true,
	[1078] = true,
	[1079] = true,
	[1080] = true,
	[1081] = true,
	[1082] = true,
	[1083] = true,
	[1084] = true,
	[1085] = true,
	[1096] = true,
	[1097] = true,
	[1098] = true
}

addEvent('vc:requestGlobal', true)
addEventHandler('vc:requestGlobal', resourceRoot, function()
	if not client or isBlocked() then
		return
	end
	triggerClientEvent(client, 'vc:globalLoaded', resourceRoot, globalCache[client] or {})
end)

addEvent('vc:saveGlobal', true)
addEventHandler('vc:saveGlobal', resourceRoot, function(d)
	local p = client
	if not isElement(p) or isBlocked() or type(d) ~= 'table' then
		return
	end
	local safe = {
		colors = {},
		useColors = d.useColors == true,
		useWheels = d.useWheels == true,
		wheel = 0
	}

	for i = 1, 12 do
		local n = tonumber(d.colors and d.colors[i]) or 255
		safe.colors[i] = math.max(0, math.min(255, math.floor(n)))
	end

	local wheel = tonumber(d.wheel)
	if wheel and allowedWheels[wheel] then
		safe.wheel = wheel
	end
	globalCache[p] = safe
	dbExec(db, 'INSERT OR REPLACE INTO tuning_global (owner,data) VALUES (?,?)', owner(p), toJSON(safe, true))
	local v = getPedOccupiedVehicle(p)
	if v then
		apply(p, v)
	end
	triggerClientEvent(p, 'vc:globalSaved', resourceRoot)
end)

-- Race maps may apply their own upgrades after the player's vehicle has spawned.
-- Reassert the player's chosen global wheel if another resource overwrites it.
setTimer(function()
	if isBlocked() then
		return
	end

	for _, p in ipairs(getElementsByType('player')) do
		local g = globalCache[p]
		if g and g.useWheels and tonumber(g.wheel) and tonumber(g.wheel) ~= 0 then
			local v = getPedOccupiedVehicle(p)
			if v and getVehicleOccupant(v, 0) == p and getVehicleUpgradeOnSlot(v, 7) ~= tonumber(g.wheel) then
				addVehicleUpgrade(v, tonumber(g.wheel))
			end
		end
	end
end, 2000, 0)
