-- neon_ui / config.lua
-- Constantes visuales compartidas por la telemetria y el panel de votaciones.

NeonUI = {}

NeonUI.colors = {
	bg         = { 8, 12, 20, 205 },
	border     = { 120, 220, 255, 26 },
	accent     = { 53, 225, 255, 255 },
	accentSoft = { 53, 225, 255, 80 },
	text       = { 232, 240, 248, 255 },
	dim        = { 138, 156, 176, 255 },
	track      = { 255, 255, 255, 16 },
	good       = { 53, 225, 255, 255 },
	warn       = { 255, 186, 84, 255 },
	bad        = { 255, 92, 110, 255 },
}

-- Escala base: 1.0 a 1080p, acotada para resoluciones extremas.
function NeonUI.refresh()
	local sw, sh = guiGetScreenSize()
	local scale = math.min(sh / 1080, sw / 1920)
	scale = math.max(0.8, math.min(1.6, scale))

	NeonUI.screenW = sw
	NeonUI.screenH = sh
	NeonUI.scale = scale
	NeonUI.margin = math.floor(24 * scale)
	NeonUI.gap = math.floor(12 * scale)
	NeonUI.pad = math.floor(18 * scale)
	NeonUI.cardW = math.floor(420 * scale)
	NeonUI.telemetryH = math.floor(74 * scale)
	NeonUI.raceH = math.floor(92 * scale)
	NeonUI.voteYInit = false
end

NeonUI.refresh()

NeonUI.telemetryVisible = false
NeonUI.voteY = 0
NeonUI.voteYInit = false

function NeonUI.px(value)
	return value * NeonUI.scale
end

function NeonUI.i(value)
	return math.floor(value * NeonUI.scale + 0.5)
end

-- Convierte un color de la paleta en tocolor, multiplicando el alfa.
function NeonUI.tcol(color, mul)
	local a = (color[4] or 255) * (mul or 1)
	if a < 0 then
		a = 0
	elseif a > 255 then
		a = 255
	end
	return tocolor(color[1], color[2], color[3], math.floor(a))
end

function NeonUI.card(x, y, w, h, mul)
	dxDrawRectangle(x, y, w, h, NeonUI.tcol(NeonUI.colors.bg, mul), false)

	local border = NeonUI.tcol(NeonUI.colors.border, mul)
	dxDrawRectangle(x, y, w, 1, border, false)
	dxDrawRectangle(x, y + h - 1, w, 1, border, false)
	dxDrawRectangle(x, y, 1, h, border, false)
	dxDrawRectangle(x + w - 1, y, 1, h, border, false)
end

function NeonUI.track(x, y, w, h, mul)
	dxDrawRectangle(x, y, w, h, NeonUI.tcol(NeonUI.colors.track, mul), false)
end

-- Formato de tiempo de carrera: M:SS.d (o H:MM:SS si pasa de una hora).
function NeonUI.time(ms)
	ms = tonumber(ms) or 0
	if ms < 0 then
		ms = 0
	end

	local tenths = math.floor(ms / 100)
	local seconds = math.floor(tenths / 10)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60

	if minutes >= 60 then
		local hours = math.floor(minutes / 60)
		return string.format("%d:%02d:%02d", hours, minutes % 60, secs)
	end
	return string.format("%d:%02d.%d", minutes, secs, tenths % 10)
end

-- Y objetivo del panel de votaciones: debajo de la telemetria si esta visible.
function NeonUI.voteTargetY()
	local y = NeonUI.margin
	if NeonUI.telemetryVisible then
		y = y + NeonUI.telemetryH + NeonUI.gap
	end
	return y
end

function NeonUI.updateVoteY(dt)
	local target = NeonUI.voteTargetY()
	if not NeonUI.voteYInit then
		NeonUI.voteY = target
		NeonUI.voteYInit = true
		return
	end
	NeonUI.voteY = NeonUI.voteY + (target - NeonUI.voteY) * math.min(1, dt * 10)
end

addEventHandler("onClientRestore", root, function()
	NeonUI.refresh()
end)


-- neon_ui / votes.lua
-- Panel de votaciones minimalista. Reemplaza la GUI stock de votemanager.
-- El servidor envia el conteo con el evento "doVoteUpdate" (parche en
-- [managers]/votemanager/votemanager_server.lua).

local poll = nil
local closingAt = nil
local shownAt = 0
local result = nil

local anim = {}
local pulse = {}
local boundKeys = {}

local lastTick = getTickCount()

local previewTimer = nil

local sendVote
local onVoteKey
local stopPreview
local startPreview

addEvent("doShowPoll", true)
addEvent("doVoteUpdate", true)
addEvent("doSendVote", true)
addEvent("doStopPoll", true)
addEvent("doVoteResult", true)
addEvent("neon:previewVotes", true)
addEvent("neon:previewVotesStop", true)

local function text(str, x, y, w, h, color, scale, font, alignX, alignY)
	dxDrawText(str, x, y, x + w, y + h, color, scale * NeonUI.scale,
		font or "default", alignX or "left", alignY or "center", true, false, false)
end

local function unbindAll()
	for _, key in ipairs(boundKeys) do
		unbindKey(key, "down", onVoteKey)
		unbindKey("num_" .. key, "down", onVoteKey)
	end
	boundKeys = {}
	unbindKey("backspace", "down", onVoteKey)
end

local function bindAll(count, allowChange)
	unbindAll()
	local limit = math.min(count, 9)
	for i = 1, limit do
		local key = tostring(i)
		bindKey(key, "down", onVoteKey)
		bindKey("num_" .. key, "down", onVoteKey)
		table.insert(boundKeys, key)
	end
	if allowChange then
		bindKey("backspace", "down", onVoteKey)
	end
end

onVoteKey = function(key)
	if not poll then
		return
	end
	if key == "backspace" then
		sendVote(-1)
		return
	end
	key = key:gsub("num_", "")
	local id = tonumber(key)
	if id then
		sendVote(id)
	end
end

sendVote = function(id)
	if not poll then
		return
	end

	if id ~= -1 then
		if id < 1 or id > #poll.options then
			return
		end
		if poll.myVote and not poll.allowchange then
			return
		end
	elseif not poll.allowchange then
		return
	end

	poll.myVote = (id ~= -1) and id or nil

	if poll.preview then
		return
	end

	triggerServerEvent("onClientSendVote", localPlayer, id)
end

local function resetPoll(title, options, timeLeft, allowChange, nomination, preview)
	local now = getTickCount()

	poll = {
		title = title or "Votacion",
		options = options or {},
		counts = {},
		total = 0,
		max = math.max(1, #(options or {})),
		threshold = 65,
		finishesAt = now + (timeLeft or 15000),
		duration = math.max(1, timeLeft or 15000),
		allowchange = allowChange and true or false,
		nomination = nomination or 1,
		myVote = nil,
		preview = preview and true or false,
	}

	anim = {}
	pulse = {}
	for i = 1, #poll.options do
		poll.counts[i] = 0
		anim[i] = 0
		pulse[i] = 0
	end

	shownAt = now
	closingAt = nil
	result = nil

	bindAll(#poll.options, poll.allowchange)
end

stopPreview = function()
	if previewTimer and isTimer(previewTimer) then
		killTimer(previewTimer)
	end
	previewTimer = nil

	if poll and poll.preview then
		poll = nil
		closingAt = nil
		unbindAll()
	end
end

startPreview = function()
	stopPreview()
	resetPoll("Votacion de mapa",
		{ "Vinewood Blast Around", "Sandking Rally", "Airport Speedway", "Desert Run" },
		20000, true, 1, true)
	poll.max = 8
	poll.threshold = 65

	previewTimer = setTimer(function()
		if not poll or not poll.preview then
			return
		end

		if poll.total >= poll.max then
			local best, bestVotes = 1, -1
			for i, votes in ipairs(poll.counts) do
				if votes > bestVotes then
					best, bestVotes = i, votes
				end
			end
			result = { name = poll.options[best], at = getTickCount() }
			closingAt = getTickCount()
			unbindAll()
			if previewTimer and isTimer(previewTimer) then
				killTimer(previewTimer)
			end
			previewTimer = nil
			return
		end

		local index = math.random(1, #poll.options)
		poll.counts[index] = poll.counts[index] + 1
		poll.total = poll.total + 1
		pulse[index] = getTickCount()
	end, 1000, 0)
end

addEventHandler("doShowPoll", root, function(data, options, timeLeft)
	if type(data) ~= "table" or type(options) ~= "table" then
		return
	end
	stopPreview()
	resetPoll(data.title, options, timeLeft, data.allowchange, data.nomination, false)
	if poll then
		poll.threshold = tonumber(data.percentage) or poll.threshold
	end
end)

addEvent("updateBars", true)
addEventHandler("updateBars", root, function(voteCount, maxVoters)
	if not poll or poll.preview or type(voteCount) ~= "table" then
		return
	end

	local now = getTickCount()
	poll.total = 0
	for i = 1, #poll.options do
		local value = tonumber(voteCount[i]) or 0
		if value > (poll.counts[i] or 0) then
			pulse[i] = now
		end
		poll.counts[i] = value
		poll.total = poll.total + value
	end
	poll.max = math.max(1, tonumber(maxVoters) or poll.max)
end)

addEventHandler("doVoteUpdate", root, function(tally)
	if not poll or poll.preview or type(tally) ~= "table" then
		return
	end

	local counts = tally.counts or {}
	local now = getTickCount()
	for i = 1, #poll.options do
		local value = tonumber(counts[i]) or 0
		if value > (poll.counts[i] or 0) then
			pulse[i] = now
		end
		poll.counts[i] = value
	end

	poll.total = tonumber(tally.total) or poll.total
	poll.max = math.max(1, tonumber(tally.max) or poll.max)
	poll.threshold = tonumber(tally.threshold) or poll.threshold
end)

addEventHandler("doSendVote", root, function(voteID)
	if not poll then
		return
	end
	poll.myVote = (voteID ~= -1) and voteID or nil
end)

addEventHandler("doStopPoll", root, function()
	if not poll then
		return
	end
	unbindAll()
	closingAt = getTickCount()
end)

addEventHandler("doVoteResult", root, function(name)
	result = { name = name or "?", at = getTickCount() }
end)

addEventHandler("neon:previewVotes", root, function()
	startPreview()
end)

addEventHandler("neon:previewVotesStop", root, function()
	stopPreview()
end)

local function easeOut(t)
	if t < 0 then
		t = 0
	elseif t > 1 then
		t = 1
	end
	return 1 - (1 - t) * (1 - t) * (1 - t)
end

local function drawPoll(now, dt)
	local w = NeonUI.cardW
	local pad = NeonUI.pad
	local headerH = NeonUI.i(52)
	local rowH = NeonUI.i(46)
	local footerH = NeonUI.i(32)
	local count = #poll.options
	local h = headerH + count * rowH + footerH

	local tIn = easeOut((now - shownAt) / 260)
	local tOut = 1
	if closingAt then
		tOut = 1 - math.max(0, math.min(1, (now - closingAt) / 220))
	end
	local a = tIn * tOut
	if a <= 0 then
		return
	end

	local x = NeonUI.screenW - NeonUI.margin - w + (1 - tIn) * NeonUI.i(10)
	local y = NeonUI.voteY

	NeonUI.card(x, y, w, h, a)
	dxDrawRectangle(x, y, math.max(2, NeonUI.i(2)), h,
		NeonUI.tcol(NeonUI.colors.accent, a), false)

	local title = "VOTACION"
	if (poll.nomination or 1) > 1 then
		title = title .. " " .. poll.nomination
	end
	text(title, x + pad, y, w - pad * 2 - NeonUI.i(60), headerH,
		NeonUI.tcol(NeonUI.colors.accent, a), 1.05, "default-bold", "left", "center")

	local remaining = math.max(0, poll.finishesAt - now)
	local seconds = math.ceil(remaining / 1000)
	text(string.format("%d:%02d", math.floor(seconds / 60), seconds % 60),
		x + pad, y, w - pad * 2, headerH,
		NeonUI.tcol(NeonUI.colors.text, a), 1.05, "default-bold", "right", "center")

	local timeY = y + headerH - 1
	local timeRatio = math.max(0, math.min(1, remaining / math.max(1, poll.duration)))
	dxDrawRectangle(x + pad, timeY, w - pad * 2, 1,
		NeonUI.tcol(NeonUI.colors.track, a), false)
	dxDrawRectangle(x + pad, timeY, (w - pad * 2) * timeRatio, 1,
		NeonUI.tcol(NeonUI.colors.accentSoft, a), false)

	local nameX = x + pad + NeonUI.i(24)
	local nameW = w - pad * 2 - NeonUI.i(24) - NeonUI.i(36)

	for i = 1, count do
		local rowY = y + headerH + (i - 1) * rowH
		local mine = (poll.myVote == i)
		local target = (poll.counts[i] or 0) / math.max(1, poll.max)
		anim[i] = (anim[i] or 0) + (target - (anim[i] or 0)) * math.min(1, dt * 9)

		text(tostring(i), x + pad, rowY, NeonUI.i(18), rowH,
			NeonUI.tcol(mine and NeonUI.colors.accent or NeonUI.colors.dim, a),
			1.0, "default-bold", "left", "center")

		text(poll.options[i], nameX, rowY, nameW, NeonUI.i(28),
			NeonUI.tcol(NeonUI.colors.text, a), 1.1, "default", "left", "center")

		text(tostring(poll.counts[i] or 0), x + pad, rowY, w - pad * 2, NeonUI.i(28),
			NeonUI.tcol(mine and NeonUI.colors.accent or NeonUI.colors.text, a),
			1.1, "default-bold", "right", "center")

		local barX = nameX
		local barY = rowY + NeonUI.i(32)
		local barW = w - pad * 2 - NeonUI.i(24)
		local barH = math.max(4, NeonUI.i(6))

		NeonUI.track(barX, barY, barW, barH, a)
		local fill = math.max(0, math.min(1, anim[i] or 0)) * barW
		if fill > 0 then
			dxDrawRectangle(barX, barY, fill, barH,
				NeonUI.tcol(NeonUI.colors.accent, a), false)
		end

		local elapsed = (now - (pulse[i] or 0)) / 450
		if elapsed >= 0 and elapsed < 1 then
			dxDrawRectangle(barX, barY - NeonUI.i(2), fill, barH + NeonUI.i(4),
				NeonUI.tcol(NeonUI.colors.accent, a * (1 - elapsed) * 0.6), false)
		end

		local threshold = math.max(0, math.min(1, (poll.threshold or 65) / 100))
		dxDrawRectangle(barX + barW * threshold, barY - NeonUI.i(2),
			math.max(1, NeonUI.i(1)), barH + NeonUI.i(4),
			NeonUI.tcol(NeonUI.colors.text, a * 0.35), false)
	end

	local footY = y + headerH + count * rowH
	text(string.format("%d/%d votos", poll.total or 0, poll.max or 0),
		x + pad, footY, NeonUI.i(140), footerH,
		NeonUI.tcol(NeonUI.colors.dim, a), 0.82, "default", "left", "center")

	local hint = "1-" .. math.min(count, 9) .. " votar"
	if poll.allowchange then
		hint = hint .. "  |  Backspace cancela"
	end
	text(hint, x + pad, footY, w - pad * 2, footerH,
		NeonUI.tcol(NeonUI.colors.dim, a), 0.82, "default", "right", "center")
end

local function drawResult(now)
	if not result or poll then
		return
	end

	local elapsed = now - result.at
	if elapsed > 2600 then
		result = nil
		return
	end

	local a = math.min(1, elapsed / 180)
	if elapsed > 2200 then
		a = math.max(0, (2600 - elapsed) / 400)
	end
	if a <= 0 then
		return
	end

	local w = NeonUI.cardW
	local h = NeonUI.i(68)
	local x = NeonUI.screenW - NeonUI.margin - w
	local y = NeonUI.voteY
	local pad = NeonUI.pad

	NeonUI.card(x, y, w, h, a)
	dxDrawRectangle(x, y, math.max(2, NeonUI.i(2)), h,
		NeonUI.tcol(NeonUI.colors.accent, a), false)

	text("GANO", x + pad, y + NeonUI.i(5), w - pad * 2, NeonUI.i(22),
		NeonUI.tcol(NeonUI.colors.dim, a), 0.8, "default-bold", "left", "center")
	text(result.name, x + pad, y + NeonUI.i(27), w - pad * 2, NeonUI.i(32),
		NeonUI.tcol(NeonUI.colors.text, a), 1.15, "default-bold", "left", "center")
end

local function render()
	local now = getTickCount()
	local dt = (now - lastTick) / 1000
	lastTick = now
	if dt > 0.25 then
		dt = 0.25
	end

	if poll and closingAt and (now - closingAt) >= 220 then
		poll = nil
		closingAt = nil
	end

	if poll then
		drawPoll(now, dt)
	end

	if result then
		drawResult(now)
	end
end

addEventHandler("onClientRender", root, render)

addCommandHandler("vote", function(_, ...)
	if not poll then
		return
	end

	local raw = table.concat({ ... }, " ")
	if raw == "" then
		return
	end

	local id = tonumber(raw)
	if not id then
		local needle = raw:lower()
		for i, name in ipairs(poll.options) do
			if name:lower() == needle then
				id = i
				break
			end
		end
	end

	if id then
		sendVote(id)
	end
end)

addCommandHandler("cancelvote", function()
	if poll then
		sendVote(-1)
	end
end)

-- Solo para disenar sin jugadores conectados: muestra un panel falso local.
addCommandHandler("votepreview", function(_, arg)
	if arg and arg:lower() == "stop" then
		stopPreview()
	else
		startPreview()
	end
end)


-- Neon: panel de votos debajo de la telemetria, sin depender de neon_ui.
NeonUI.voteY = NeonUI.margin + NeonUI.telemetryH + NeonUI.gap
addEventHandler("onClientRestore", root, function()
	NeonUI.refresh()
	NeonUI.voteY = NeonUI.margin + NeonUI.telemetryH + NeonUI.gap
end)
