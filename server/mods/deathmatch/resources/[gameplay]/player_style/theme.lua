-- player_style / config.lua
-- Constantes visuales compartidas por la telemetria y el panel de votaciones.

StyleUI = {}

StyleUI.colors = {
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
function StyleUI.refresh()
	local sw, sh = guiGetScreenSize()
	local scale = math.min(sh / 1080, sw / 1920)
	scale = math.max(0.8, math.min(1.6, scale))

	StyleUI.screenW = sw
	StyleUI.screenH = sh
	StyleUI.scale = scale
	StyleUI.margin = math.floor(24 * scale)
	StyleUI.gap = math.floor(12 * scale)
	StyleUI.pad = math.floor(18 * scale)
	StyleUI.cardW = math.floor(420 * scale)
	StyleUI.telemetryH = math.floor(74 * scale)
	StyleUI.raceH = math.floor(92 * scale)
	StyleUI.voteYInit = false
end

StyleUI.refresh()

StyleUI.telemetryVisible = false
StyleUI.voteY = 0
StyleUI.voteYInit = false

function StyleUI.px(value)
	return value * StyleUI.scale
end

function StyleUI.i(value)
	return math.floor(value * StyleUI.scale + 0.5)
end

-- Convierte un color de la paleta en tocolor, multiplicando el alfa.
function StyleUI.tcol(color, mul)
	local a = (color[4] or 255) * (mul or 1)
	if a < 0 then
		a = 0
	elseif a > 255 then
		a = 255
	end
	return tocolor(color[1], color[2], color[3], math.floor(a))
end

function StyleUI.card(x, y, w, h, mul)
	dxDrawRectangle(x, y, w, h, StyleUI.tcol(StyleUI.colors.bg, mul), false)

	local border = StyleUI.tcol(StyleUI.colors.border, mul)
	dxDrawRectangle(x, y, w, 1, border, false)
	dxDrawRectangle(x, y + h - 1, w, 1, border, false)
	dxDrawRectangle(x, y, 1, h, border, false)
	dxDrawRectangle(x + w - 1, y, 1, h, border, false)
end

function StyleUI.track(x, y, w, h, mul)
	dxDrawRectangle(x, y, w, h, StyleUI.tcol(StyleUI.colors.track, mul), false)
end

-- Formato de tiempo de carrera: M:SS.d (o H:MM:SS si pasa de una hora).
function StyleUI.time(ms)
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
function StyleUI.voteTargetY()
	local y = StyleUI.margin
	if StyleUI.telemetryVisible then
		y = y + StyleUI.telemetryH + StyleUI.gap
	end
	return y
end

function StyleUI.updateVoteY(dt)
	local target = StyleUI.voteTargetY()
	if not StyleUI.voteYInit then
		StyleUI.voteY = target
		StyleUI.voteYInit = true
		return
	end
	StyleUI.voteY = StyleUI.voteY + (target - StyleUI.voteY) * math.min(1, dt * 10)
end

addEventHandler("onClientRestore", root, function()
	StyleUI.refresh()
end)
