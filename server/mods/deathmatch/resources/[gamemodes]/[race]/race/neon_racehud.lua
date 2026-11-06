-- neon_ui / racehud.lua
-- Tarjeta inferior derecha con posicion, checkpoints y tiempo de carrera.
-- Reemplaza los dxText stock del gamemode race (ver docs/RUNBOOK.md).
-- race_client.lua envia el estado local con "neon:raceHud" (~10 Hz).

local state = nil
local lastUpdate = 0

-- Previsualizacion local para ajustar el diseno sin jugadores.
local preview = nil
local previewTimer = nil
local previewStart = 0

local function stopPreview()
	if previewTimer and isTimer(previewTimer) then
		killTimer(previewTimer)
	end
	previewTimer = nil
	preview = nil
end

-- Evento local compartido entre recursos (race_client.lua lo emite ~10 Hz).
addEvent("neon:raceHud", false)

local alpha = 0
local lastTick = getTickCount()

local shownRatio = 0
local lastCheckpoint = -1
local cpPulse = 0
local lastRank = -1
local rankPulse = 0

addEventHandler("neon:raceHud", root, function(data)
	if type(data) ~= "table" then
		return
	end
	if preview and data.active then
		stopPreview()
	end
	state = data
	lastUpdate = getTickCount()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
	stopPreview()
	state = nil
	lastUpdate = 0
	alpha = 0
	shownRatio = 0
	lastCheckpoint = -1
	lastRank = -1
end)

local function render()
	local now = getTickCount()
	local dt = (now - lastTick) / 1000
	lastTick = now
	if dt > 0.25 then
		dt = 0.25
	end

	-- Si el recurso race deja de emitir, la tarjeta se oculta sola.
	local data = preview or state or {}
	local live = preview ~= nil
	if not live and state then
		live = (now - lastUpdate) < 1000 and state.active
	end
	local target = live and 1 or 0
	alpha = alpha + (target - alpha) * math.min(1, dt * 10)
	if alpha < 0.01 then
		alpha = 0
		return
	end

	local ranked = live and data.ranked or false
	local rank = tonumber(data.rank) or 0
	local total = tonumber(data.total) or 0
	local checkpoint = tonumber(data.checkpoint) or 0
	local remaining = tonumber(data.remaining)
	local finished = live and data.finished or false

	local targetRatio = 0
	if total > 0 then
		targetRatio = math.max(0, math.min(1, checkpoint / total))
	end

	if alpha < 0.05 then
		shownRatio = targetRatio
	else
		shownRatio = shownRatio + (targetRatio - shownRatio) * math.min(1, dt * 8)
	end

	if checkpoint ~= lastCheckpoint then
		if lastCheckpoint >= 0 then
			cpPulse = now
		end
		lastCheckpoint = checkpoint
	end
	if rank ~= lastRank then
		if lastRank > 0 then
			rankPulse = now
		end
		lastRank = rank
	end

	local a = alpha
	local w = NeonUI.cardW
	local h = NeonUI.raceH
	local pad = NeonUI.pad
	local x = NeonUI.screenW - NeonUI.margin - w + (1 - alpha) * NeonUI.i(14)
	local y = NeonUI.screenH - NeonUI.margin - h

	NeonUI.card(x, y, w, h, a)
	dxDrawRectangle(x, y, math.max(2, NeonUI.i(2)), h,
		NeonUI.tcol(NeonUI.colors.accent, a), false)

	-- Cabecera: tipo y nombre del mapa, con el autor a la derecha.
	-- g_MapInfo lo asigna initRace en race_client.lua (mismo recurso).
	local mapInfo = (preview and preview.map) or g_MapInfo
	local mapType = mapInfo and mapInfo.racetype or nil
	local mapName = mapInfo and (mapInfo.name or mapInfo.resname) or nil
	local mapAuthor = mapInfo and mapInfo.author or nil

	local headerTop = y + NeonUI.i(8)
	local headerH = NeonUI.i(20)

	if mapName then
		local tagText = "[" .. (mapType or "???") .. "] "
		local tagScale = NeonUI.px(0.85)
		local tagW = dxGetTextWidth(tagText, tagScale, "default-bold")

		local authorReserve = 0
		if mapAuthor and mapAuthor ~= "" then
			authorReserve = dxGetTextWidth(mapAuthor, NeonUI.px(0.75), "default-bold") + NeonUI.i(14)
		end

		dxDrawText(tagText, x + pad, headerTop, x + pad + tagW + 2, headerTop + headerH,
			NeonUI.tcol(NeonUI.colors.accent, a), tagScale, "default-bold",
			"left", "center", true, false, false)
		dxDrawText(mapName, x + pad + tagW, headerTop, x + w - pad - authorReserve, headerTop + headerH,
			NeonUI.tcol(NeonUI.colors.text, a), tagScale, "default-bold",
			"left", "center", true, false, false)

		if mapAuthor and mapAuthor ~= "" then
			dxDrawText(mapAuthor, x + pad, headerTop, x + w - pad, headerTop + headerH,
				NeonUI.tcol(NeonUI.colors.dim, a), NeonUI.px(0.75), "default-bold",
				"right", "center", true, false, false)
		end

		-- Separador entre la cabecera del mapa y las filas de carrera.
		dxDrawRectangle(x + pad, y + NeonUI.i(30), w - pad * 2, 1,
			NeonUI.tcol(NeonUI.colors.border, a), false)
	end

	local labelTop = y + NeonUI.i(34)
	local labelH = NeonUI.i(22)
	local valueTop = y + NeonUI.i(54)
	local valueH = NeonUI.i(42)

	local rankX = x + pad
	local rankW = NeonUI.i(112)
	local cpX = x + pad
	local cpW = NeonUI.i(200)
	if ranked then
		cpX = x + pad + NeonUI.i(142)
		cpW = NeonUI.i(150)
	end

	-- Etiquetas
	if ranked then
		dxDrawText("POSICION", rankX, labelTop, rankX + rankW, labelTop + labelH,
			NeonUI.tcol(NeonUI.colors.dim, a), NeonUI.px(0.85), "default-bold",
			"left", "center", true, false, false)
	end
	dxDrawText("CHECKPOINTS", cpX, labelTop, cpX + cpW, labelTop + labelH,
		NeonUI.tcol(NeonUI.colors.dim, a), NeonUI.px(0.85), "default-bold",
		"left", "center", true, false, false)
	dxDrawText("TIEMPO", x + pad, labelTop, x + w - pad, labelTop + labelH,
		NeonUI.tcol(NeonUI.colors.dim, a), NeonUI.px(0.85), "default-bold",
		"right", "center", true, false, false)

	-- Posicion
	if ranked then
		local rankText = rank > 0 and (rank .. "\194\186") or "-"
		local rankColor = rank > 0 and NeonUI.colors.accent or NeonUI.colors.dim
		local glow = 0
		local elapsed = (now - rankPulse) / 500
		if elapsed >= 0 and elapsed < 1 then
			glow = (1 - elapsed) * 0.45
		end
		if glow > 0 then
			dxDrawText(rankText, rankX, valueTop, rankX + rankW, valueTop + valueH,
				NeonUI.tcol(NeonUI.colors.accent, a * glow), NeonUI.px(1.6),
				"default-bold", "left", "center", true, false, false)
		end
		dxDrawText(rankText, rankX, valueTop, rankX + rankW, valueTop + valueH,
			NeonUI.tcol(rankColor, a), NeonUI.px(1.45), "default-bold",
			"left", "center", true, false, false)
	end

	-- Checkpoints
	local cpText = total > 0 and (checkpoint .. " / " .. total) or "-"
	local cpColor = (total > 0 and checkpoint >= total)
		and NeonUI.colors.accent or NeonUI.colors.text
	dxDrawText(cpText, cpX, valueTop, cpX + cpW, valueTop + valueH,
		NeonUI.tcol(cpColor, a), NeonUI.px(1.25), "default-bold",
		"left", "center", true, false, false)

	-- Tiempo
	local timeColor = finished and NeonUI.colors.accent or NeonUI.colors.text
	dxDrawText(NeonUI.time(data.elapsed), x + pad, valueTop, x + w - pad, valueTop + valueH,
		NeonUI.tcol(timeColor, a), NeonUI.px(1.25), "default-bold",
		"right", "center", true, false, false)

	-- Tiempo restante del mapa (solo si hay duracion y la carrera sigue).
	if remaining and not finished then
		local remScale = NeonUI.px(1.0)
		local remText = NeonUI.time(remaining)
		local remW = dxGetTextWidth(remText, remScale, "default-bold")
		local remTop = y + NeonUI.i(92)
		local remH = NeonUI.i(20)

		dxDrawText(remText, x + w - pad - remW, remTop, x + w - pad, remTop + remH,
			NeonUI.tcol(NeonUI.colors.text, a), remScale, "default-bold",
			"right", "center", true, false, false)
		dxDrawText("RESTANTE", x + pad, remTop, x + w - pad - remW - NeonUI.i(8), remTop + remH,
			NeonUI.tcol(NeonUI.colors.dim, a), NeonUI.px(0.8), "default-bold",
			"right", "center", true, false, false)
	end

	-- Barra de progreso de checkpoints
	local barX = x + pad
	local barY = y + NeonUI.i(116)
	local barW = w - pad * 2
	local barH = math.max(4, NeonUI.i(6))

	NeonUI.track(barX, barY, barW, barH, a)
	local fill = barW * math.max(0, math.min(1, shownRatio))
	if fill > 0 then
		dxDrawRectangle(barX, barY, fill, barH,
			NeonUI.tcol(NeonUI.colors.accent, a), false)
	end

	local pulseElapsed = (now - cpPulse) / 600
	if pulseElapsed >= 0 and pulseElapsed < 1 and fill > 0 then
		dxDrawRectangle(barX, barY - NeonUI.i(2), fill, barH + NeonUI.i(4),
			NeonUI.tcol(NeonUI.colors.accent, a * (1 - pulseElapsed) * 0.5), false)
	end
end

addEventHandler("onClientRender", root, render)

-- Solo para disenar sin carrera activa: muestra una tarjeta falsa local.
addCommandHandler("racehudpreview", function(_, arg)
	if arg and arg:lower() == "stop" then
		stopPreview()
		return
	end

	stopPreview()
	previewStart = getTickCount()
	preview = {
		active = true,
		ranked = true,
		rank = 3,
		checkpoint = 4,
		total = 12,
		elapsed = 0,
		remaining = 245000,
		finished = false,
		map = {
			name = "Downtown Sprint",
			author = "Ferecece",
			racetype = "SR",
		},
	}

	previewTimer = setTimer(function()
		if not preview then
			return
		end
		local elapsed = getTickCount() - previewStart
		preview.elapsed = elapsed
		preview.checkpoint = math.min(preview.total, 4 + math.floor(elapsed / 4000))
		preview.rank = math.max(1, 3 - math.floor(elapsed / 8000))
	end, 100, 0)
end)
