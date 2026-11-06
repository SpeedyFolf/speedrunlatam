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
	NeonUI.raceH = math.floor(118 * scale)
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
