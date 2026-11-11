-- race_playerstatsgui / gui.lua
-- Panel de estadisticas con la estetica Neon (DirectX), centrado, con fade.
-- Dos vistas: "stats" (tus estadisticas) y "top" (ranking del servidor por XP).

local UI = {
	bg         = { 8, 12, 20, 205 },
	border     = { 120, 220, 255, 26 },
	accent     = { 53, 225, 255, 255 },
	accentSoft = { 53, 225, 255, 80 },
	text       = { 232, 240, 248, 255 },
	dim        = { 138, 156, 176, 255 },
	track      = { 255, 255, 255, 16 },
	online     = { 80, 220, 120, 255 },
}

local function color(c, mul)
	local a = math.floor((c[4] or 255) * (mul or 1) + 0.5)
	if a < 0 then
		a = 0
	elseif a > 255 then
		a = 255
	end
	return tocolor(c[1], c[2], c[3], a)
end

local function screenScale()
	local sw, sh = guiGetScreenSize()
	local s = sh / 1080
	s = math.max(0.9, math.min(2.2, s))
	return sw, sh, s
end

local function px(v, s)
	return v * s
end

local function ip(v, s)
	return math.floor(v * s + 0.5)
end

local function ip2cReady()
	local res = getResourceFromName("ip2c")
	return res and getResourceState(res) == "running"
end

-- Ruta a la bandera de ip2c, o nil si no hay/esta disponible.
local function flagPath(country)
	if type(country) ~= "string" or not ip2cReady() then return nil end
	country = string.lower(country)
	if not country:match("^%a%a$") or country == "zz" then return nil end
	return ":ip2c/client/images/flags/" .. country .. ".png"
end

local function safeFormat(fn, value)
	local ok, out = pcall(fn, value)
	if ok and out ~= nil then
		return tostring(out)
	end
	return tostring(value or 0)
end

local function rowValue(row, stats)
	local value = stats and stats[row.key]
	if value == nil then
		value = 0
	end
	return safeFormat(row.format or Convert.ToString, value)
end

-- Layout de estadisticas: dos columnas. Izq = CARRERAS + JUGADOR, der = LOGROS + CRIMENES.
local GROUPS = {
	carreras = {
		title = "CARRERAS",
		rows = {
			{ key = 2010, label = "Experiencia", format = Convert.ToString, highlight = true },
			{ key = 148,  label = "Carreras iniciadas", format = Convert.ToString },
			{ key = 1025, label = "Carreras terminadas", format = Convert.ToString },
			{ key = 1026, label = "Victorias", format = Convert.ToString },
			{ key = 1032, label = "2º puestos", format = Convert.ToString },
			{ key = 1033, label = "3º puestos", format = Convert.ToString },
			{ key = 1027, label = "Toptimes", format = Convert.ToString },
		},
	},
	jugador = {
		title = "JUGADOR",
		rows = {
			{ key = 1001, label = "Tiempo jugado (cuenta)", format = Convert.SecondsToTimeString },
			{ key = 135,  label = "Muertes", format = Convert.ToString },
			{ key = 1090, label = "Daño recibido", format = Convert.Health },
			{ key = 21,   label = "Gordura", format = Convert.PermilleToPercentage },
		},
	},
	logros = {
		title = "LOGROS",
		rows = {
			{ key = 4,  label = "Distancia en auto", format = Convert.MetersToKilometers },
			{ key = 5,  label = "Distancia en moto", format = Convert.MetersToKilometers },
			{ key = 6,  label = "Distancia en lancha", format = Convert.MetersToKilometers },
			{ key = 8,  label = "Distancia en avión", format = Convert.MetersToKilometers },
			{ key = 27, label = "Distancia en bici", format = Convert.MetersToKilometers },
		},
	},
	crimenes = {
		title = "CRÍMENES",
		rows = {
			{ key = 122,  label = "Autos destruidos", format = Convert.ToString },
			{ key = 1125, label = "Motos destruidas", format = Convert.ToString },
			{ key = 123,  label = "Lanchas destruidas", format = Convert.ToString },
			{ key = 124,  label = "Aviones/heli destruidos", format = Convert.ToString },
		},
	},
}

local LAYOUT = {
	{ GROUPS.carreras, GROUPS.jugador },
	{ GROUPS.logros, GROUPS.crimenes },
}

local TOP_VISIBLE_ROWS = 12

local state = {
	targetFade = 0,
	currentFade = 0,
	lastSeconds = 0,
	stats = nil,
	statsName = nil,
	pendingClear = false,
	view = "stats",   -- "stats" | "top"
	topList = nil,
	topScroll = 0,
}

local function requestStats()
	triggerServerEvent("onRequestPlayerStats", localPlayer)
end

local function requestTop()
	state.topList = nil
	state.topScroll = 0
	triggerServerEvent("onRequestTopPlayers", localPlayer)
end

local function setVisible(visible)
	state.targetFade = visible and 1 or 0
	showCursor(visible)
	if not visible then
		state.view = "stats"
	end
end

local function columnHeight(groups, s)
	local h = 0
	for i, group in ipairs(groups) do
		if i > 1 then
			h = h + ip(18, s)
		end
		h = h + ip(28, s) + #group.rows * ip(28, s)
	end
	return h
end

local function getStatsLayout(sw, sh, s)
	local pad = ip(22, s)
	local headerH = ip(56, s)
	local colGap = ip(30, s)
	local colW = ip(300, s)
	local sectionGap = ip(18, s)
	local sectionHeaderH = ip(28, s)
	local rowH = ip(28, s)
	local bottomPad = ip(18, s)
	local leftH = columnHeight(LAYOUT[1], s)
	local rightH = columnHeight(LAYOUT[2], s)
	local bodyH = math.max(leftH, rightH)
	local w = pad * 2 + colW * 2 + colGap
	local h = headerH + bodyH + bottomPad
	return {
		x = (sw - w) / 2, y = (sh - h) / 2, w = w, h = h,
		pad = pad, headerH = headerH, colGap = colGap, colW = colW,
		sectionGap = sectionGap, sectionHeaderH = sectionHeaderH, rowH = rowH,
	}
end

local function getTopLayout(sw, sh, s)
	local pad = ip(22, s)
	local headerH = ip(56, s)
	local rowH = ip(30, s)
	local bottomPad = ip(18, s)
	local colW = ip(300, s)
	local colGap = ip(30, s)
	local w = pad * 2 + colW * 2 + colGap
	local listH = rowH * TOP_VISIBLE_ROWS
	local h = headerH + listH + bottomPad
	return {
		x = (sw - w) / 2, y = (sh - h) / 2, w = w, h = h,
		pad = pad, headerH = headerH, rowH = rowH, listH = listH,
		visibleRows = TOP_VISIBLE_ROWS,
	}
end

local function getButtonRect(L, s)
	local bw = ip(90, s)
	local bh = ip(32, s)
	return L.x + L.w - L.pad - bw, L.y + (L.headerH - bh) / 2, bw, bh
end

local function drawViewButton(x, y, w, headerH, pad, s, a, label)
	local bw = ip(90, s)
	local bh = ip(32, s)
	local bx = x + w - pad - bw
	local by = y + (headerH - bh) / 2

	dxDrawRectangle(bx, by, bw, bh, color(UI.accentSoft, a * 0.16), false)
	local b = color(UI.border, a)
	dxDrawRectangle(bx, by, bw, 1, b, false)
	dxDrawRectangle(bx, by + bh - 1, bw, 1, b, false)
	dxDrawRectangle(bx, by, 1, bh, b, false)
	dxDrawRectangle(bx + bw - 1, by, 1, bh, b, false)
	dxDrawText(label, bx, by, bx + bw, by + bh,
		color(UI.accent, a), px(1.0, s), "default-bold", "center", "center", true, false, false)
end

local function drawCard(x, y, w, h, s, a)
	dxDrawRectangle(x, y, w, h, color(UI.bg, a), false)
	local border = color(UI.border, a)
	dxDrawRectangle(x, y, w, 1, border, false)
	dxDrawRectangle(x, y + h - 1, w, 1, border, false)
	dxDrawRectangle(x, y, 1, h, border, false)
	dxDrawRectangle(x + w - 1, y, 1, h, border, false)
	dxDrawRectangle(x, y, math.max(2, ip(2, s)), h, color(UI.accent, a), false)
end

local function drawStats(sw, sh, s, a)
	local L = getStatsLayout(sw, sh, s)
	local x = L.x
	local y = L.y + (1 - a) * ip(14, s)
	local w, h = L.w, L.h
	local pad, headerH = L.pad, L.headerH
	local colGap, colW = L.colGap, L.colW
	local sectionGap, sectionHeaderH, rowH = L.sectionGap, L.sectionHeaderH, L.rowH

	drawCard(x, y, w, h, s, a)

	-- Cabecera
	dxDrawText("ESTADÍSTICAS", x + pad, y, x + w - pad - ip(100, s), y + headerH,
		color(UI.accent, a), px(1.25, s), "default-bold",
		"left", "center", true, false, false)

	if state.statsName and state.statsName ~= "" then
		dxDrawText(state.statsName, x + pad, y, x + w - pad - ip(100, s), y + headerH,
			color(UI.dim, a), px(1.0, s), "default-bold",
			"right", "center", true, false, false)
	end

	drawViewButton(x, y, w, headerH, pad, s, a, "TOP")
	dxDrawRectangle(x + pad, y + headerH - 1, w - pad * 2, 1, color(UI.track, a), false)

	local stats = state.stats

	for ci, groups in ipairs(LAYOUT) do
		local cx = x + pad + (ci - 1) * (colW + colGap)
		local cy = y + headerH + ip(8, s)

		for gi, group in ipairs(groups) do
			if gi > 1 then
				cy = cy + sectionGap
			end

			dxDrawText(group.title, cx, cy, cx + colW, cy + sectionHeaderH,
				color(UI.accent, a), px(0.95, s), "default-bold",
				"left", "center", true, false, false)
			dxDrawRectangle(cx, cy + sectionHeaderH - 1, colW, 1, color(UI.track, a), false)

			cy = cy + sectionHeaderH

			for ri, row in ipairs(group.rows) do
				local ry = cy + (ri - 1) * rowH

				if row.highlight then
					dxDrawRectangle(cx, ry, colW, rowH, color(UI.accentSoft, a * 0.22), false)
					dxDrawRectangle(cx, ry, math.max(2, ip(2, s)), rowH, color(UI.accent, a), false)
				elseif ri % 2 == 0 then
					dxDrawRectangle(cx, ry, colW, rowH, color(UI.track, a), false)
				end

				dxDrawText(row.label, cx + ip(10, s), ry, cx + colW, ry + rowH,
					color(UI.dim, a), px(1.05, s), "default-bold",
					"left", "center", true, false, false)

				local valueColor = row.highlight and UI.accent or UI.text
				dxDrawText(rowValue(row, stats), cx, ry, cx + colW - ip(10, s), ry + rowH,
					color(valueColor, a), px(row.highlight and 1.15 or 1.05, s), "default-bold",
					"right", "center", true, false, false)
			end

			cy = cy + #group.rows * rowH
		end
	end
end

local function drawTop(sw, sh, s, a)
	local L = getTopLayout(sw, sh, s)
	local x = L.x
	local y = L.y + (1 - a) * ip(14, s)
	local w, h = L.w, L.h
	local pad, headerH = L.pad, L.headerH
	local rowH = L.rowH

	drawCard(x, y, w, h, s, a)

	-- Cabecera
	dxDrawText("TOP DEL SERVIDOR", x + pad, y, x + w - pad - ip(100, s), y + headerH,
		color(UI.accent, a), px(1.25, s), "default-bold",
		"left", "center", true, false, false)
	drawViewButton(x, y, w, headerH, pad, s, a, "VOLVER")
	dxDrawRectangle(x + pad, y + headerH - 1, w - pad * 2, 1, color(UI.track, a), false)

	local list = state.topList
	local listTop = y + headerH + ip(8, s)
	local listBottom = listTop + L.listH

	if not list then
		dxDrawText("Cargando...", x + pad, listTop, x + w - pad, listBottom,
			color(UI.dim, a), px(1.0, s), "default-bold",
			"center", "center", true, false, false)
		return
	end
	if #list == 0 then
		dxDrawText("Sin jugadores.", x + pad, listTop, x + w - pad, listBottom,
			color(UI.dim, a), px(1.0, s), "default-bold",
			"center", "center", true, false, false)
		return
	end

	local visibleRows = L.visibleRows
	local maxScroll = math.max(0, #list - visibleRows)
	if state.topScroll > maxScroll then state.topScroll = maxScroll end
	if state.topScroll < 0 then state.topScroll = 0 end

	local posX = x + pad
	local posW = ip(44, s)
	local flagX = posX + posW + ip(2, s)
	local flagW = ip(28, s)
	local flagH = ip(17, s)
	-- Gap entre la bandera y el nick para que no se vean pegados.
	local nameX = flagX + flagW + ip(12, s)
	local pointsRight = x + w - pad
	local onlineRight = pointsRight - ip(84, s)
	local onlineX = onlineRight - ip(108, s)
	local nameRight = onlineX - ip(10, s)

	for i = 1, visibleRows do
		local idx = i + state.topScroll
		local entry = list[idx]
		if not entry then
			break
		end
		local ry = listTop + (i - 1) * rowH

		if idx % 2 == 0 then
			dxDrawRectangle(x + pad, ry, w - pad * 2, rowH, color(UI.track, a), false)
		end

		-- Posicion
		dxDrawText(idx .. "º", posX, ry, posX + posW, ry + rowH,
			color(UI.accent, a), px(1.0, s), "default-bold",
			"left", "center", true, false, false)

		-- Bandera (placeholder gris si no hay pais)
		local flag = flagPath(entry.country)
		if flag then
			dxDrawImage(flagX, ry + (rowH - flagH) / 2, flagW, flagH, flag)
		else
			dxDrawRectangle(flagX, ry + (rowH - flagH) / 2, flagW, flagH, tocolor(255, 255, 255, 28), false)
		end

		-- Nick
		dxDrawText(tostring(entry.name or "?"), nameX, ry, nameRight, ry + rowH,
			color(UI.text, a), px(1.0, s), "default-bold",
			"left", "center", true, false, false)

		-- Online: punto verde + texto chico
		if entry.online then
			local dot = ip(6, s)
			dxDrawRectangle(onlineX, ry + (rowH - dot) / 2, dot, dot, color(UI.online, a), false)
			dxDrawText("EN LÍNEA", onlineX + ip(12, s), ry, onlineRight, ry + rowH,
				color(UI.online, a), px(0.82, s), "default-bold",
				"left", "center", true, false, false)
		end

		-- XP
		dxDrawText(tostring(entry.points or 0), onlineRight + ip(6, s), ry, pointsRight, ry + rowH,
			color(UI.accent, a), px(1.1, s), "default-bold",
			"right", "center", true, false, false)
	end

	-- Indicador de scroll
	if maxScroll > 0 then
		local trackX = x + w - ip(5, s)
		local trackW = ip(3, s)
		local trackH = L.listH
		dxDrawRectangle(trackX, listTop, trackW, trackH, color(UI.track, a), false)
		local thumbH = math.max(ip(20, s), trackH * visibleRows / #list)
		local thumbY = listTop + (trackH - thumbH) * (state.topScroll / maxScroll)
		dxDrawRectangle(trackX, thumbY, trackW, thumbH, color(UI.accentSoft, a * 0.8), false)
	end
end

local function draw(sw, sh, s, a)
	if state.view == "top" then
		drawTop(sw, sh, s, a)
	else
		drawStats(sw, sh, s, a)
	end
end

local function render()
	-- Limpia los datos una vez que el panel termino de ocultarse.
	if state.pendingClear and state.currentFade <= 0 then
		state.stats = nil
		state.statsName = nil
		state.pendingClear = false
	end

	if state.targetFade == state.currentFade and state.currentFade <= 0 then
		return
	end

	local now = getTickCount() / 1000
	local dt = now - state.lastSeconds
	state.lastSeconds = now
	if dt < 0 then
		dt = 0
	elseif dt > 1 / 25 then
		dt = 1 / 25
	end

	-- Fade out mas lento que el fade in (igual que race_toptimes).
	local fadeSpeed = state.targetFade < state.currentFade and 2 or 6
	local maxChange = dt * fadeSpeed
	local dif = state.targetFade - state.currentFade
	if dif > maxChange then
		dif = maxChange
	elseif dif < -maxChange then
		dif = -maxChange
	end

	state.currentFade = math.max(0, math.min(1, state.currentFade + dif))

	if state.currentFade > 0 then
		local sw, sh, s = screenScale()
		draw(sw, sh, s, state.currentFade)
	end
end

local function toggleStats()
	if state.targetFade < 0.5 then
		-- Si venia de un cierre limpio (ej. logout), no arrastrar datos viejos.
		if state.pendingClear then
			state.stats = nil
			state.statsName = nil
			state.pendingClear = false
		end
		state.view = "stats"
		-- F10 siempre muestra las stats propias (aunque antes hayas visto a otro).
		state.statsName = getPlayerName(localPlayer)
		requestStats()
		setVisible(true)
	else
		setVisible(false)
	end
end

local function toggleView()
	if state.view == "top" then
		state.view = "stats"
	else
		state.view = "top"
		requestTop()
	end
end

--
-- Eventos
--

addEvent("onClientStatsDisplay", true)
addEventHandler("onClientStatsDisplay", root,
	function(display)
		if display then
			state.pendingClear = false
			setVisible(true)
		else
			setVisible(false)
			-- Limpia los datos al terminar el fade-out (ver render).
			state.pendingClear = true
		end
	end
)

addEvent("onClientUpdateStats", true)
addEventHandler("onClientUpdateStats", root,
	function(playerName, stats)
		state.stats = stats or {}
		state.statsName = playerName
		state.pendingClear = false
	end
)

addEvent("onClientTopList", true)
addEventHandler("onClientTopList", root,
	function(list)
		state.topList = list or {}
		state.topScroll = 0
	end
)

-- Legacy export (deprecado): lo mantenemos como no-op para no romper llamadas viejas.
function AddStatColumn()
	outputDebugString("race_playerstatsgui: AddStatColumn is deprecated.")
end

addEventHandler("onClientClick", root,
	function(button, clickState, absX, absY)
		if button ~= "left" or clickState ~= "down" then
			return
		end
		if state.currentFade <= 0 then
			return
		end
		local sw, sh, s = screenScale()
		local L = (state.view == "top") and getTopLayout(sw, sh, s) or getStatsLayout(sw, sh, s)
		local bx, by, bw, bh = getButtonRect(L, s)
		if absX >= bx and absX <= bx + bw and absY >= by and absY <= by + bh then
			toggleView()
			return true
		end
	end
)

local function onWheel(delta)
	if state.view ~= "top" or state.targetFade < 0.5 then
		return
	end
	state.topScroll = math.max(0, state.topScroll + delta)
end

addEventHandler("onClientResourceStart", resourceRoot,
	function()
		state.targetFade = 0
		state.currentFade = 0
		state.lastSeconds = 0
		state.stats = nil
		state.statsName = nil
		state.view = "stats"
		state.topList = nil
		state.topScroll = 0
		addEventHandler("onClientRender", root, render)
	end
)

addEventHandler("onClientResourceStop", resourceRoot,
	function()
		removeEventHandler("onClientRender", root, render)
		showCursor(false)
	end
)

bindKey("F10", "down", toggleStats)
bindKey("mouse_wheel_up", "down", function() onWheel(-1) end)
bindKey("mouse_wheel_down", "down", function() onWheel(1) end)
