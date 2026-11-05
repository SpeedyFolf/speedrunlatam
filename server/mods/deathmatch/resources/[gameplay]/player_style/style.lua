-- player_style / style.lua
-- Ventana de estilo: skin del personaje y colores primario/secundario del vehiculo.
-- Se abre con /estilo (el color del auto tambien con /color).
-- La eleccion se guarda en la cuenta (style_server.lua).

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

local SKINS = {
	0, 7, 12, 20, 23, 28, 29, 36, 44, 55, 60, 63, 68, 73,
	90, 97, 105, 110, 118, 122, 128, 133, 140, 148, 155, 163,
	170, 178, 186, 193, 200, 207, 214, 219, 224, 230, 236, 240,
	245, 250, 258, 262, 264,
}

local open = false
local alpha = 0
local lastTick = getTickCount()

local canSave = false
local raceMode = false

local state = { skin = SKINS[1], primary = 1, secondary = 2 }
local originalSkin = nil
local originalColors = nil
local dirty = true

local hits = {}
local note = nil
local noteAt = 0
local savedPulse = 0

addEvent("player_style:openStyle", true)
addEvent("player_style:styleSaved", true)

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

local function skinIndexOf(id)
	for i, skin in ipairs(SKINS) do
		if skin == id then
			return i
		end
	end
	return nil
end

local function text(str, x, y, w, h, color, scale, font, alignX, alignY)
	dxDrawText(str, x, y, x + w, y + h, color, scale * StyleUI.scale,
		font or "default", alignX or "left", alignY or "center", true, false, false)
end

local function applyPreview()
	if not isElement(localPlayer) then
		return
	end
	if getElementModel(localPlayer) ~= state.skin then
		setElementModel(localPlayer, state.skin)
	end
end

local function applyColorPreview()
	-- En carrera el servidor decide si puede pintar el vehiculo.
	if raceMode or not isElement(localPlayer) then
		return
	end
	local vehicle = getPedOccupiedVehicle(localPlayer)
	if not vehicle then
		return
	end
	local p, s = PALETTE[state.primary], PALETTE[state.secondary]
	setVehicleColor(vehicle, p[1], p[2], p[3], s[1], s[2], s[3])
end

local keyFuncs = {}

local shiftSkin
local saveStyle
local closePanel
local openPanel

function shiftSkin(delta)
	local index = skinIndexOf(state.skin) or 1
	index = ((index - 1 + delta) % #SKINS) + 1
	state.skin = SKINS[index]
	dirty = true
end

function saveStyle()
	if not canSave then
		note = "Necesitas una cuenta para guardar"
		noteAt = getTickCount()
		return
	end
	local p, s = PALETTE[state.primary], PALETTE[state.secondary]
	triggerServerEvent("player_style:saveStyle", localPlayer,
		state.skin, p[1], p[2], p[3], s[1], s[2], s[3])
end

local function bindKeys()
	keyFuncs.left = function() shiftSkin(-1) end
	keyFuncs.right = function() shiftSkin(1) end
	keyFuncs.cancel = function() closePanel(false) end

	bindKey("arrow_left", "down", keyFuncs.left)
	bindKey("arrow_right", "down", keyFuncs.right)
	bindKey("backspace", "down", keyFuncs.cancel)
end

local function unbindKeys()
	if keyFuncs.left then
		unbindKey("arrow_left", "down", keyFuncs.left)
		unbindKey("arrow_right", "down", keyFuncs.right)
		unbindKey("backspace", "down", keyFuncs.cancel)
	end
	keyFuncs = {}
end

function isStyleOpen()
	return open
end

function closePanel(saved)
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

	if isElement(localPlayer) then
		if saved then
			setElementModel(localPlayer, state.skin)
		elseif originalSkin and getElementModel(localPlayer) ~= originalSkin then
			setElementModel(localPlayer, originalSkin)
		end

		local vehicle = getPedOccupiedVehicle(localPlayer)
		if vehicle and not saved and originalColors then
			setVehicleColor(vehicle,
				originalColors[1], originalColors[2], originalColors[3],
				originalColors[4], originalColors[5], originalColors[6])
		end
	end
end

function openPanel(style, canSaveFlag, isRace)
	canSave = canSaveFlag and true or false
	raceMode = isRace and true or false

	state.skin = math.floor(tonumber(style and style.skin) or SKINS[1])
	state.primary = paletteIndexOf(style and style.primary) or 1
	state.secondary = paletteIndexOf(style and style.secondary) or 2

	originalSkin = isElement(localPlayer) and getElementModel(localPlayer) or nil
	originalColors = nil

	local vehicle = getPedOccupiedVehicle(localPlayer)
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

local function drawCamera()
	local vehicle = getPedOccupiedVehicle(localPlayer)
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
		applyPreview()
		applyColorPreview()
		dirty = false
	end

	drawCamera()

	local a = alpha
	hits = {}

	local w = math.min(StyleUI.i(820), math.floor(StyleUI.screenW * 0.86))
	local pad = StyleUI.i(26)
	local headerH = StyleUI.i(64)
	local skinH = StyleUI.i(88)
	local rowH = StyleUI.i(74)
	local footerH = StyleUI.i(62)
	local h = headerH + skinH + rowH * 2 + footerH

	local x = math.floor((StyleUI.screenW - w) / 2)
	local y = math.floor((StyleUI.screenH - h) / 2) - StyleUI.i(24)

	dxDrawRectangle(0, 0, StyleUI.screenW, StyleUI.screenH,
		tocolor(4, 6, 12, math.floor(155 * a)), false)

	StyleUI.card(x, y, w, h, a)
	dxDrawRectangle(x, y, math.max(2, StyleUI.i(2)), h,
		StyleUI.tcol(StyleUI.colors.accent, a), false)

	-- Cabecera
	text("ESTILO", x + pad, y, w - pad * 2, headerH,
		StyleUI.tcol(StyleUI.colors.accent, a), 1.3, "default-bold", "left", "center")

	local subtitle = "SKIN Y COLORES DEL VEHICULO"
	text(subtitle, x + pad, y, w - pad * 2 - StyleUI.i(50), headerH,
		StyleUI.tcol(StyleUI.colors.dim, a), 0.85, "default-bold", "right", "center")

	-- Cerrar (X): el ESC del juego abre el menu de pausa, asi que la X manda.
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

	-- Skin
	local skinTop = y + headerH
	local skinLabelW = StyleUI.i(110)
	text("SKIN", x + pad, skinTop, skinLabelW, skinH,
		StyleUI.tcol(StyleUI.colors.dim, a), 0.9, "default-bold", "left", "center")

	local arrow = StyleUI.i(40)
	local skinAreaX = x + pad + skinLabelW
	local skinAreaW = w - pad * 2 - skinLabelW
	local leftX = math.floor(skinAreaX)
	local rightX = math.floor(skinAreaX + skinAreaW - arrow)
	local arrowY = math.floor(skinTop + (skinH - arrow) / 2)
	local labelX = leftX + arrow + StyleUI.i(12)
	local labelW = math.max(0, rightX - labelX - StyleUI.i(12))

	for _, data in ipairs({
		{ x = leftX, label = "<", delta = -1 },
		{ x = rightX, label = ">", delta = 1 },
	}) do
		dxDrawRectangle(data.x, arrowY, arrow, arrow,
			StyleUI.tcol(StyleUI.colors.track, a * 1.6), false)
		dxDrawRectangle(data.x, arrowY, arrow, 1,
			StyleUI.tcol(StyleUI.colors.accentSoft, a), false)
		text(data.label, data.x, arrowY, arrow, arrow,
			StyleUI.tcol(StyleUI.colors.accent, a), 1.2, "default-bold", "center", "center")
		addHit("skin", data.delta, data.x, arrowY, arrow, arrow)
	end

	local index = skinIndexOf(state.skin)
	local label
	if index then
		label = string.format("SKIN %d  -  %d / %d", state.skin, index, #SKINS)
	else
		label = "SKIN " .. state.skin
	end
	text(label, labelX, skinTop, labelW, skinH,
		StyleUI.tcol(StyleUI.colors.text, a), 1.05, "default-bold", "center", "center")

	-- Paletas
	local labelW = StyleUI.i(180)
	local areaX = x + pad + labelW
	local areaW = w - pad * 2 - labelW
	local swatchGap = StyleUI.i(12)
	local swatch = math.min(StyleUI.i(40),
		math.floor((areaW - swatchGap * (#PALETTE - 1)) / #PALETTE))
	local totalSwatch = #PALETTE * swatch + (#PALETTE - 1) * swatchGap
	local swatchX = math.floor(areaX + (areaW - totalSwatch) / 2)

	local function drawPalette(rowIndex, label, selected)
		local top = y + headerH + skinH + (rowIndex - 1) * rowH

		text(label, x + pad, top, labelW, rowH,
			StyleUI.tcol(StyleUI.colors.dim, a), 0.9, "default-bold", "left", "center")

		local swatchY = math.floor(top + (rowH - swatch) / 2)
		for i, color in ipairs(PALETTE) do
			local sx = swatchX + (i - 1) * (swatch + swatchGap)
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

			addHit(rowIndex == 1 and "primary" or "secondary", i, sx, swatchY, swatch, swatch)
		end
	end

	drawPalette(1, "COLOR PRIMARIO", state.primary)
	drawPalette(2, "COLOR SECUNDARIO", state.secondary)

	-- Pie
	local footTop = y + h - footerH
	dxDrawRectangle(x + pad, footTop, w - pad * 2, 1,
		StyleUI.tcol(StyleUI.colors.track, a), false)

	if note and (now - noteAt) < 2600 then
		text(note, x + pad, footTop, w - pad * 2, footerH,
			StyleUI.tcol(StyleUI.colors.warn, a), 0.9, "default-bold", "left", "center")
	else
		text("Click GUARDAR    X cerrar    Flechas cambian la skin",
			x + pad, footTop, w - pad * 2 - StyleUI.i(160), footerH,
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

addEventHandler("player_style:openStyle", root, function(style, canSaveFlag, isRace)
	openPanel(style, canSaveFlag, isRace)
end)

addEventHandler("player_style:styleSaved", root, function(ok)
	if not open then
		return
	end

	if ok then
		savedPulse = getTickCount()
		closePanel(true)
		outputChatBox("Estilo guardado.", 53, 225, 255)
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
			if hit.kind == "skin" then
				shiftSkin(hit.value)
			elseif hit.kind == "primary" then
				state.primary = hit.value
				dirty = true
			elseif hit.kind == "secondary" then
				state.secondary = hit.value
				dirty = true
			elseif hit.kind == "save" then
				saveStyle()
			elseif hit.kind == "close" then
				closePanel(false)
			end
			return
		end
	end
end)

addCommandHandler("estilo", function()
	if open then
		return
	end
	-- Si la ventana de /color esta abierta, se cierra para no superponer.
	if isColorOpen and isColorOpen() then
		closeColorPanel(false)
	end
	triggerServerEvent("player_style:requestStyle", localPlayer)
end)

-- El ESC de GTA abre el menu de pausa: se cancela solo mientras la ventana
-- esta abierta (MTA solo permite cancelarlo en la pulsacion).
addEventHandler("onClientKey", root, function(button, press)
	if not open or button ~= "escape" then
		return
	end
	if press then
		cancelEvent()
		closePanel(false)
	end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
	if open then
		closePanel(false)
	end
end)
