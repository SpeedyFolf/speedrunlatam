-- player_style / color.lua
-- Ventana simple de /color: solo color primario y secundario del vehiculo.
-- Misma paleta y estetica que el resto de player_style. No toca skin ni otras cosas.

local PALETTE = {
	{ 53, 225, 255 },
	{ 255, 72, 214 },
	{ 163, 110, 255 },
	{ 130, 255, 120 },
	{ 255, 214, 74 },
	{ 255, 96, 112 },
	{ 96, 164, 255 },
	{ 255, 146, 66 },
	{ 232, 240, 248 },
	{ 70, 76, 94 },
}

local open = false
local alpha = 0
local lastTick = getTickCount()

local canSave = false
local raceMode = false
local previewLocked = false

local state = { primary = 1, secondary = 2 }
local originalColors = nil
local dirty = true

local hits = {}
local note = nil
local noteAt = 0
local savedPulse = 0

addEvent("player_style:openColor", true)
addEvent("player_style:colorSaved", true)

local function paletteIndexOf(color)
	if type(color) ~= "table" then
		return nil
	end
	for i, c in ipairs(PALETTE) do
		if c[1] == color[1] and c[2] == color[2] and c[3] == color[3] then
			return i
		end
	end
	return nil
end

local function text(str, x, y, w, h, color, scale, font, alignX, alignY)
	dxDrawText(str, x, y, x + w, y + h, color, scale * StyleUI.scale,
		font or "default", alignX or "left", alignY or "center", true, false, false)
end

local function currentVehicle()
	local vehicle = getPedOccupiedVehicle(localPlayer)
	if vehicle and isElement(vehicle) then
		return vehicle
	end
	return nil
end

local function applyColorPreview()
	if not isElement(localPlayer) or previewLocked then
		return
	end

	local vehicle = currentVehicle()
	if not vehicle then
		return
	end

	local p, s = PALETTE[state.primary], PALETTE[state.secondary]
	setVehicleColor(vehicle, p[1], p[2], p[3], s[1], s[2], s[3])
end

local keyFuncs = {}

local function bindKeys()
	keyFuncs.cancel = function() closeColorPanel(false) end
	bindKey("backspace", "down", keyFuncs.cancel)
end

local function unbindKeys()
	if keyFuncs.cancel then
		unbindKey("backspace", "down", keyFuncs.cancel)
	end
	keyFuncs = {}
end

function isColorOpen()
	return open
end

function closeColorPanel(saved)
	if not open then
		return
	end

	open = false
	alpha = 0
	unbindKeys()
	showCursor(false)
	showChat(true)
	toggleAllControls(true, true, false)
	setCameraTarget(localPlayer)

	-- Si cancela, se devuelven los colores que tenia el vehiculo.
	if not saved and isElement(localPlayer) then
		local vehicle = currentVehicle()
		if vehicle and originalColors then
			setVehicleColor(vehicle,
				originalColors[1], originalColors[2], originalColors[3],
				originalColors[4], originalColors[5], originalColors[6])
		end
	end
end

function openColorPanel(primary, secondary, canSaveFlag, isRace, locked)
	canSave = canSaveFlag and true or false
	raceMode = isRace and true or false
	previewLocked = locked and true or false

	state.primary = paletteIndexOf(primary) or 1
	state.secondary = paletteIndexOf(secondary) or 2

	originalColors = nil
	local vehicle = currentVehicle()
	if vehicle then
		local colors = { getVehicleColor(vehicle, true) }
		if #colors >= 6 then
			originalColors = colors
		end
	end

	dirty = true
	note = nil
	open = true
	lastTick = getTickCount()

	toggleAllControls(false, true, false)
	showCursor(true)
	showChat(false)
	bindKeys()
end

local function saveColors()
	if not canSave then
		note = "Necesitas una cuenta (usa /login)"
		noteAt = getTickCount()
		return
	end

	local p, s = PALETTE[state.primary], PALETTE[state.secondary]
	triggerServerEvent("player_style:saveColor", localPlayer,
		p[1], p[2], p[3], s[1], s[2], s[3])
end

local function drawCamera()
	local vehicle = currentVehicle()
	local subject = vehicle or localPlayer
	if not isElement(subject) then
		return
	end

	local px, py, pz = getElementPosition(subject)
	local _, _, rz = getElementRotation(subject)
	local rad = math.rad(rz)
	local fx, fy = -math.sin(rad), math.cos(rad)

	local distance = vehicle and 7.0 or 2.6
	local camZ = pz + (vehicle and 1.7 or 0.35)
	local lookZ = pz + (vehicle and 0.85 or 0.55)

	setCameraMatrix(px + fx * distance, py + fy * distance, camZ, px, py, lookZ)
end

local function addHit(kind, value, x, y, w, h)
	hits[#hits + 1] = { kind = kind, value = value, x = x, y = y, w = w, h = h }
end

local function inside(hit, mx, my)
	return mx >= hit.x and mx <= hit.x + hit.w and my >= hit.y and my <= hit.y + hit.h
end

local function render()
	if not open then
		if alpha > 0 then
			alpha = 0
		end
		return
	end

	local now = getTickCount()
	local dt = (now - lastTick) / 1000
	lastTick = now
	if dt > 0.25 then
		dt = 0.25
	end

	alpha = alpha + (1 - alpha) * math.min(1, dt * 12)
	if dirty then
		applyColorPreview()
		dirty = false
	end

	drawCamera()

	local a = alpha
	hits = {}

	local w = math.min(StyleUI.i(820), math.floor(StyleUI.screenW * 0.86))
	local pad = StyleUI.i(26)
	local headerH = StyleUI.i(64)
	local rowH = StyleUI.i(88)
	local footerH = StyleUI.i(62)
	local h = headerH + rowH * 2 + footerH

	local x = math.floor((StyleUI.screenW - w) / 2)
	local y = math.floor((StyleUI.screenH - h) / 2) - StyleUI.i(24)

	dxDrawRectangle(0, 0, StyleUI.screenW, StyleUI.screenH,
		tocolor(4, 6, 12, math.floor(155 * a)), false)

	StyleUI.card(x, y, w, h, a)
	dxDrawRectangle(x, y, math.max(2, StyleUI.i(2)), h,
		StyleUI.tcol(StyleUI.colors.accent, a), false)

	-- Cabecera
	text("COLORES", x + pad, y, w - pad * 2, headerH,
		StyleUI.tcol(StyleUI.colors.accent, a), 1.3, "default-bold", "left", "center")

	text("PRIMARIO Y SECUNDARIO", x + pad, y, w - pad * 2 - StyleUI.i(50), headerH,
		StyleUI.tcol(StyleUI.colors.dim, a), 0.85, "default-bold", "right", "center")

	local closeSize = StyleUI.i(34)
	local closeX = math.floor(x + w - pad - closeSize)
	local closeY = math.floor(y + (headerH - closeSize) / 2)
	dxDrawRectangle(closeX, closeY, closeSize, closeSize,
		StyleUI.tcol(StyleUI.colors.track, a * 1.6), false)
	text("X", closeX, closeY, closeSize, closeSize,
		StyleUI.tcol(StyleUI.colors.dim, a), 1.1, "default-bold", "center", "center")
	addHit("close", true, closeX, closeY, closeSize, closeSize)

	dxDrawRectangle(x + pad, y + headerH - 1, w - pad * 2, 1,
		StyleUI.tcol(StyleUI.colors.track, a), false)

	-- Paletas: etiqueta a la izquierda y muestras centradas en el resto.
	local labelW = StyleUI.i(200)
	local areaX = x + pad + labelW
	local areaW = w - pad * 2 - labelW
	local gap = StyleUI.i(12)
	local swatch = math.min(StyleUI.i(44),
		math.floor((areaW - gap * (#PALETTE - 1)) / #PALETTE))
	local totalSwatch = #PALETTE * swatch + (#PALETTE - 1) * gap
	local swatchX = math.floor(areaX + (areaW - totalSwatch) / 2)

	local function drawPalette(rowIndex, label, selected, kind)
		local top = y + headerH + (rowIndex - 1) * rowH

		text(label, x + pad, top, labelW, rowH,
			StyleUI.tcol(StyleUI.colors.dim, a), 0.9, "default-bold", "left", "center")

		local swatchY = math.floor(top + (rowH - swatch) / 2)
		for i, color in ipairs(PALETTE) do
			local sx = swatchX + (i - 1) * (swatch + gap)
			local isSelected = (i == selected)

			if isSelected then
				local glow = 0.55 + 0.45 * math.abs(math.sin(now / 420))
				dxDrawRectangle(sx - 4, swatchY - 4, swatch + 8, swatch + 8,
					StyleUI.tcol(StyleUI.colors.accent, a * glow), false)
			end

			dxDrawRectangle(sx, swatchY, swatch, swatch,
				tocolor(color[1], color[2], color[3], math.floor(235 * a)), false)

			if isSelected then
				local border = StyleUI.tcol(StyleUI.colors.accent, a)
				dxDrawRectangle(sx - 2, swatchY - 2, swatch + 4, 2, border, false)
				dxDrawRectangle(sx - 2, swatchY + swatch, swatch + 4, 2, border, false)
				dxDrawRectangle(sx - 2, swatchY, 2, swatch, border, false)
				dxDrawRectangle(sx + swatch, swatchY, 2, swatch, border, false)
			else
				dxDrawRectangle(sx, swatchY, swatch, 1,
					StyleUI.tcol(StyleUI.colors.border, a), false)
			end

			addHit(kind, i, sx, swatchY, swatch, swatch)
		end
	end

	drawPalette(1, "COLOR PRIMARIO", state.primary, "primary")
	drawPalette(2, "COLOR SECUNDARIO", state.secondary, "secondary")

	-- Pie
	local footTop = y + h - footerH
	dxDrawRectangle(x + pad, footTop, w - pad * 2, 1,
		StyleUI.tcol(StyleUI.colors.track, a), false)

	if note and (now - noteAt) < 2600 then
		text(note, x + pad, footTop, w - pad * 2 - StyleUI.i(170), footerH,
			StyleUI.tcol(StyleUI.colors.warn, a), 0.9, "default-bold", "left", "center")
	elseif not canSave then
		text("Inicia sesion con /login para guardar",
			x + pad, footTop, w - pad * 2 - StyleUI.i(170), footerH,
			StyleUI.tcol(StyleUI.colors.dim, a), 0.85, "default", "left", "center")
	elseif previewLocked then
		text("El mapa fija los colores de este vehiculo",
			x + pad, footTop, w - pad * 2 - StyleUI.i(170), footerH,
			StyleUI.tcol(StyleUI.colors.warn, a), 0.85, "default", "left", "center")
	elseif raceMode then
		text("En carrera el mapa puede fijar los colores",
			x + pad, footTop, w - pad * 2 - StyleUI.i(170), footerH,
			StyleUI.tcol(StyleUI.colors.dim, a), 0.85, "default", "left", "center")
	else
		text("Click GUARDAR    X cerrar",
			x + pad, footTop, w - pad * 2 - StyleUI.i(170), footerH,
			StyleUI.tcol(StyleUI.colors.dim, a), 0.85, "default", "left", "center")
	end

	local buttonW = StyleUI.i(140)
	local buttonH = StyleUI.i(36)
	local buttonX = math.floor(x + w - pad - buttonW)
	local buttonY = math.floor(footTop + (footerH - buttonH) / 2)

	local pulse = 0
	local elapsed = (now - savedPulse) / 500
	if elapsed >= 0 and elapsed < 1 then
		pulse = (1 - elapsed) * 0.5
	end

	dxDrawRectangle(buttonX, buttonY, buttonW, buttonH,
		StyleUI.tcol(StyleUI.colors.accent, a * (0.16 + pulse)), false)
	dxDrawRectangle(buttonX, buttonY, buttonW, 1,
		StyleUI.tcol(StyleUI.colors.accent, a), false)
	dxDrawRectangle(buttonX, buttonY + buttonH - 1, buttonW, 1,
		StyleUI.tcol(StyleUI.colors.accent, a), false)
	dxDrawRectangle(buttonX, buttonY, 1, buttonH,
		StyleUI.tcol(StyleUI.colors.accent, a), false)
	dxDrawRectangle(buttonX + buttonW - 1, buttonY, 1, buttonH,
		StyleUI.tcol(StyleUI.colors.accent, a), false)

	text("GUARDAR", buttonX, buttonY, buttonW, buttonH,
		StyleUI.tcol(StyleUI.colors.accent, a), 1.0, "default-bold", "center", "center")

	addHit("save", true, buttonX, buttonY, buttonW, buttonH)
end

addEventHandler("onClientRender", root, render)

addEventHandler("player_style:openColor", root, function(primary, secondary, canSaveFlag, isRace, locked)
	openColorPanel(primary, secondary, canSaveFlag, isRace, locked)
end)

addEventHandler("player_style:colorSaved", root, function(ok)
	if not open then
		return
	end

	if ok then
		savedPulse = getTickCount()
		closeColorPanel(true)
		outputChatBox("Colores guardados.", 53, 225, 255)
	else
		note = "No se pudo guardar (necesitas cuenta)"
		noteAt = getTickCount()
		showCursor(true)
	end
end)

addEventHandler("onClientClick", root, function(button, clickState, mx, my)
	if not open or button ~= "left" or clickState ~= "up" then
		return
	end

	for _, hit in ipairs(hits) do
		if inside(hit, mx, my) then
			if hit.kind == "primary" then
				state.primary = hit.value
				dirty = true
			elseif hit.kind == "secondary" then
				state.secondary = hit.value
				dirty = true
			elseif hit.kind == "save" then
				saveColors()
			elseif hit.kind == "close" then
				closeColorPanel(false)
			end
			return
		end
	end
end)

addCommandHandler("color", function()
	if open then
		return
	end
	-- Si la ventana de /estilo esta abierta, se cierra para no superponer.
	if isStyleOpen and isStyleOpen() then
		closePanel(false)
	end
	triggerServerEvent("player_style:requestColor", localPlayer)
end)

addEventHandler("onClientKey", root, function(button, press)
	if not open or button ~= "escape" then
		return
	end
	if press then
		cancelEvent()
		closeColorPanel(false)
	end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
	if open then
		closeColorPanel(false)
	end
end)
