-- player_style / style_server.lua
-- Persistencia y aplicacion del estilo del jugador: skin y colores del vehiculo.
-- Se guarda en la cuenta (setAccountData), asi que requiere cuenta registrada.
-- Los colores se aplican en freeroam y en carrera solo si el mapa no los fija.

local STYLE_KEY = "player:style"

local cache = {}
local lastVehicle = {}

local function isRaceMode()
	local race = getResourceFromName("race")
	return race and getResourceState(race) == "running" or false
end

local function defaultStyle()
	return {
		skin = 0,
		primary = { 53, 225, 255 },
		secondary = { 255, 72, 214 },
	}
end

local function validColor(r, g, b)
	r, g, b = tonumber(r), tonumber(g), tonumber(b)
	if not r or not g or not b then
		return nil
	end
	return math.max(0, math.min(255, math.floor(r))),
		math.max(0, math.min(255, math.floor(g))),
		math.max(0, math.min(255, math.floor(b)))
end

local function sanitize(data)
	if type(data) ~= "table" then
		return defaultStyle()
	end

	local style = defaultStyle()

	local skin = math.floor(tonumber(data.skin) or 0)
	if skin >= 0 and skin <= 312 then
		style.skin = skin
	end

	if type(data.primary) == "table" then
		local r, g, b = validColor(data.primary[1], data.primary[2], data.primary[3])
		if r then
			style.primary = { r, g, b }
		end
	end

	if type(data.secondary) == "table" then
		local r, g, b = validColor(data.secondary[1], data.secondary[2], data.secondary[3])
		if r then
			style.secondary = { r, g, b }
		end
	end

	return style
end

local function getStyle(player)
	if cache[player] then
		return cache[player]
	end

	local style = defaultStyle()

	local account = getPlayerAccount(player)
	if account and not isGuestAccount(account) then
		local raw = getAccountData(account, STYLE_KEY)
		if type(raw) == "string" and raw ~= "" then
			local ok, data = pcall(fromJSON, raw)
			if ok then
				style = sanitize(data)
			end
		end
	end

	cache[player] = style
	return style
end

local function hasSavedStyle(player)
	local account = getPlayerAccount(player)
	if not account or isGuestAccount(account) then
		return false
	end
	local raw = getAccountData(account, STYLE_KEY)
	return type(raw) == "string" and raw ~= ""
end

local function saveStyle(player, style)
	local account = getPlayerAccount(player)
	if not account or isGuestAccount(account) then
		return false
	end

	if not setAccountData(account, STYLE_KEY, toJSON(style)) then
		return false
	end

	cache[player] = style
	return true
end

local function canSave(player)
	local account = getPlayerAccount(player)
	return account and not isGuestAccount(account) and true or false
end

-- En carrera algunos mapas fijan los colores del vehiculo: respetarlos.
local function colorFixedByRace(vehicle)
	local race = getResourceFromName("race")
	if not race or getResourceState(race) ~= "running" then
		return false
	end

	local ok, fixed = pcall(function()
		return exports.race:isVehicleColorFixed(getElementModel(vehicle))
	end)
	return ok and fixed and true or false
end

local function applySkin(player)
	if not isElement(player) or not hasSavedStyle(player) then
		return
	end
	setElementModel(player, getStyle(player).skin)
end

local function applyColors(player, vehicle)
	if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then
		return
	end
	if not hasSavedStyle(player) then
		return
	end

	if isRaceMode() and colorFixedByRace(vehicle) then
		return
	end

	local style = getStyle(player)
	setVehicleColor(vehicle,
		style.primary[1], style.primary[2], style.primary[3],
		style.secondary[1], style.secondary[2], style.secondary[3])
end

-- Aplicar la skin al respawnear. Tambien pisa la skin del mapa en race.
addEventHandler("onPlayerSpawn", root, function()
	local player = source
	if not isElement(player) then
		return
	end

	setTimer(applySkin, 250, 1, player)
	setTimer(applySkin, 1500, 1, player)
end)

-- Los vehiculos de play son compartidos y se crean al entrar: se vigila el
-- cambio de vehiculo en vez de depender de onVehicleEnter (race usa warp).
setTimer(function()
	for _, player in ipairs(getElementsByType("player")) do
		local vehicle = getPedOccupiedVehicle(player)
		if vehicle and getPedOccupiedVehicleSeat(player) == 0 then
			if lastVehicle[player] ~= vehicle then
				lastVehicle[player] = vehicle
				applyColors(player, vehicle)
			end
		elseif lastVehicle[player] then
			lastVehicle[player] = nil
		end
	end
end, 800, 0)

-- La ventana de estilo ya no se abre sola al entrar: ahora el jugador la pide
-- con /estilo (skin) o /color (solo colores del vehiculo).
addEventHandler("onPlayerQuit", root, function()
	cache[source] = nil
	lastVehicle[source] = nil
end)

addEventHandler("onPlayerLogin", root, function()
	cache[source] = nil
	setTimer(applySkin, 500, 1, source)
end)

addEvent("player_style:requestStyle", true)
addEventHandler("player_style:requestStyle", root, function()
	local player = client
	if not isElement(player) then
		return
	end
	triggerClientEvent(player, "player_style:openStyle", player, getStyle(player), canSave(player), isRaceMode())
end)

addEvent("player_style:saveStyle", true)
addEventHandler("player_style:saveStyle", root, function(skin, pr, pg, pb, sr, sg, sb)
	local player = client
	if not isElement(player) then
		return
	end

	local style = getStyle(player)

	skin = math.floor(tonumber(skin) or -1)
	if skin < 0 or skin > 312 then
		triggerClientEvent(player, "player_style:styleSaved", player, false)
		return
	end

	local r1, g1, b1 = validColor(pr, pg, pb)
	local r2, g2, b2 = validColor(sr, sg, sb)
	if not r1 or not r2 then
		triggerClientEvent(player, "player_style:styleSaved", player, false)
		return
	end

	local newStyle = {
		skin = skin,
		primary = { r1, g1, b1 },
		secondary = { r2, g2, b2 },
	}

	if not saveStyle(player, newStyle) then
		triggerClientEvent(player, "player_style:styleSaved", player, false)
		return
	end

	setElementModel(player, newStyle.skin)

	local vehicle = getPedOccupiedVehicle(player)
	if vehicle then
		applyColors(player, vehicle)
	end

	triggerClientEvent(player, "player_style:styleSaved", player, true)
end)

-- /color: ventana simple que solo cambia color primario y secundario.
addEvent("player_style:requestColor", true)
addEventHandler("player_style:requestColor", root, function()
	local player = client
	if not isElement(player) then
		return
	end

	local style = getStyle(player)
	local vehicle = getPedOccupiedVehicle(player)
	local locked = vehicle and colorFixedByRace(vehicle) or false

	triggerClientEvent(player, "player_style:openColor", player,
		style.primary, style.secondary, canSave(player), isRaceMode(), locked)
end)

addEvent("player_style:saveColor", true)
addEventHandler("player_style:saveColor", root, function(pr, pg, pb, sr, sg, sb)
	local player = client
	if not isElement(player) then
		return
	end

	local r1, g1, b1 = validColor(pr, pg, pb)
	local r2, g2, b2 = validColor(sr, sg, sb)
	if not r1 or not r2 then
		triggerClientEvent(player, "player_style:colorSaved", player, false)
		return
	end

	-- Se conserva la skin actual; /color solo toca los dos colores.
	local style = getStyle(player)
	local newStyle = {
		skin = style.skin,
		primary = { r1, g1, b1 },
		secondary = { r2, g2, b2 },
	}

	if not saveStyle(player, newStyle) then
		triggerClientEvent(player, "player_style:colorSaved", player, false)
		return
	end

	local vehicle = getPedOccupiedVehicle(player)
	if vehicle then
		applyColors(player, vehicle)
	end

	triggerClientEvent(player, "player_style:colorSaved", player, true)
end)

addEventHandler("onResourceStart", resourceRoot, function()
	outputServerLog("[player_style] estilos iniciados")
	for _, player in ipairs(getElementsByType("player")) do
		setTimer(applySkin, 500, 1, player)
		setTimer(applySkin, 1500, 1, player)
	end
end)
