--
-- toptimes_client.lua
-- Tabla de records del mapa con la estetica cian del servidor.
--

CToptimes = {}
CToptimes.__index = CToptimes
CToptimes.instances = {}
g_Settings = {}

---------------------------------------------------------------------------
-- Paleta y medidas (misma estetica que neon_ui)
---------------------------------------------------------------------------

local UI = {
	bg         = { 8, 12, 20, 205 },
	border     = { 120, 220, 255, 26 },
	accent     = { 53, 225, 255, 255 },
	accentSoft = { 53, 225, 255, 80 },
	text       = { 232, 240, 248, 255 },
	dim        = { 138, 156, 176, 255 },
	track      = { 255, 255, 255, 16 },
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
	local s = math.min(sh / 1080, sw / 1920)
	s = math.max(0.8, math.min(1.6, s))
	return sw, sh, s
end

local function px(v, s)
	return v * s
end

local function ip(v, s)
	return math.floor(v * s + 0.5)
end

local function cleanName(name)
	name = tostring(name or "")
	name = name:gsub("#%x%x%x%x%x%x", "")
	name = name:gsub("^%s*(.-)%s*$", "%1")
	return name
end

local function isEmptyRow(row)
	local name = cleanName(row.playerName)
	return name == "" or name == "-- Empty --" or name == "--Empty--"
end

local function formatTime(text)
	text = tostring(text or "")
	local minutes, seconds, millis = text:match("^(%d+):(%d+):(%d+)$")
	if not minutes then
		return text
	end
	return string.format("%d:%02d.%s", tonumber(minutes), tonumber(seconds), millis)
end

-- El server de esta base envia tiempos en milisegundos (row.time).
local function formatMs(ms)
	ms = math.max(0, tonumber(ms) or 0)
	local minutes = math.floor(ms / 60000)
	local seconds = math.floor((ms % 60000) / 1000)
	local millis = math.floor(ms % 1000)
	return string.format("%d:%02d.%03d", minutes, seconds, millis)
end

---------------------------------------------------------------------------
-- Events from Race
---------------------------------------------------------------------------

addEventHandler('onClientResourceStart', resourceRoot,
	function()
		triggerServerEvent('onLoadedAtClient_tt', localPlayer)
	end
)

addEvent('onClientMapStarting', true)
addEventHandler('onClientMapStarting', root,
	function(mapinfo)
		if g_CToptimes then
			g_CToptimes:onMapStarting(mapinfo)
		end
	end
)

addEvent('onClientMapStopping', true)
addEventHandler('onClientMapStopping', root,
	function()
		if g_CToptimes then
			g_CToptimes:onMapStopping()
		end
	end
)

addEvent('onClientPlayerFinish', true)
addEventHandler('onClientPlayerFinish', root,
	function()
		if g_CToptimes then
			g_CToptimes:doAutoShow()
		end
	end
)

addEvent('onClientSetMapName', true)
addEventHandler('onClientSetMapName', root,
	function(mapName)
		if g_CToptimes then
			g_CToptimes:setWindowTitle(mapName)
		end
	end
)

function updateSettings(settings, playeradmin)
	if not g_CToptimes then
		return
	end
	if settings then
		if settings.gui_x and settings.gui_y then
			g_CToptimes:setWindowPosition(settings.gui_x, settings.gui_y)
		end
		g_CToptimes.startshow = settings.startshow
	end
	-- Si un admin cambio la opcion, se le muestra la tabla.
	if playeradmin == localPlayer then
		g_CToptimes:doToggleToptimes(true)
	end
end

---------------------------------------------------------------------------
-- CToptimes
---------------------------------------------------------------------------

function CToptimes:create()
	local id = #CToptimes.instances + 1
	CToptimes.instances[id] = setmetatable(
		{
			id = id,
			bManualShow = false,
			bAutoShow = false,
			bGettingUpdates = false,
			listStatus = 'Empty',
			clientRevision = -1,
			rows = {},
			playerPosition = 0,
			mapName = '',
			targetFade = 0,
			currentFade = 0,
			lastSeconds = 0,
			autoOffTimer = Timer:create(),
		},
		self
	)

	CToptimes.instances[id]:postCreate()
	return CToptimes.instances[id]
end

function CToptimes:destroy()
	self:setHotKey(nil)
	self:closeWindow()
	self.autoOffTimer:destroy()
	CToptimes.instances[self.id] = nil
	self.id = 0
end

function CToptimes:postCreate()
	self:setHotKey('F5')
end

-- Ya no se usan elementos GUI: toda la tabla se dibuja con dxDraw.
function CToptimes:openWindow()
end

function CToptimes:closeWindow()
end

function CToptimes:setWindowPosition(gui_x, gui_y)
end

function CToptimes:setWindowTitle(mapName)
	self.mapName = cleanName(mapName)
end

function CToptimes:setHotKey(hotkey)
	if self.hotkey then
		unbindKey(self.hotkey, 'down', 'showtimes')
	end
	self.hotkey = hotkey
	if self.hotkey then
		bindKey(self.hotkey, 'down', 'showtimes')
	end
end

function CToptimes:onMapStarting(mapinfo)
	self.bAutoShow = false
	self.bManualShow = false
	self.bGettingUpdates = false
	self.listStatus = 'Empty'
	self.clientRevision = -1
	self.rows = {}
	self.playerPosition = 0
	self:setWindowTitle(mapinfo and mapinfo.name or '')
	self:updateShow()

	if self.startshow then
		self:doToggleToptimes(true)
	end
end

function CToptimes:onMapStopping()
	self.bAutoShow = false
	self.bManualShow = false
	self.bGettingUpdates = false
	self.listStatus = 'Empty'
	self.clientRevision = -1
	self.rows = {}
	self.playerPosition = 0
	self:doToggleToptimes(false)
	self:setWindowTitle('')
end

function CToptimes:doAutoShow()
	self.bAutoShow = true
	self:updateShow()
end

function CToptimes:updateShow()
	local bShowAny = self.bAutoShow or self.bManualShow
	self:enableToptimeUpdatesFromServer(bShowAny)

	if not bShowAny then
		self.targetFade = 0
	elseif not self.bManualShow and self.listStatus ~= 'Full' then
		return true
	else
		self.targetFade = 1
	end
end

function CToptimes:enableToptimeUpdatesFromServer(bOn)
	if bOn ~= self.bGettingUpdates then
		self.bGettingUpdates = bOn
		triggerServerEvent('onClientRequestToptimesUpdates', localPlayer, bOn, self.clientRevision)
	end
	if self.bGettingUpdates and self.listStatus == 'Empty' then
		self.listStatus = 'Loading'
	end
end

function CToptimes:doOnServerSentToptimes(data, serverRevision, playerPosition)
	if type(data) ~= 'table' then
		data = {}
	end

	local rows = {}
	for i, row in ipairs(data) do
		if type(row) == 'table' then
			rows[i] = {
				playerName = row.playerName,
				timeText = formatMs(row.time),
			}
		end
	end

	self.rows = rows
	self.playerPosition = tonumber(playerPosition) or 0
	self.clientRevision = serverRevision
	self.listStatus = 'Full'
	self:updateShow()
end

function onServerSentToptimes(data, serverRevision, playerPosition)
	if g_CToptimes then
		g_CToptimes:doOnServerSentToptimes(data, serverRevision, playerPosition)
	end
end

---------------------------------------------------------------------------
-- Dibujo
---------------------------------------------------------------------------

function CToptimes:draw()
	local sw, sh, s = screenScale()
	local a = self.currentFade
	if a <= 0 then
		return
	end

	local pad = ip(18, s)
	local headerH = ip(36, s)
	local rowH = ip(28, s)
	local bottomPad = ip(8, s)
	local w = ip(400, s)
	local margin = ip(24, s)

	local n = #self.rows
	local bodyH
	if self.listStatus ~= 'Full' then
		bodyH = ip(42, s)
	elseif n == 0 then
		bodyH = ip(30, s)
	else
		bodyH = n * rowH
	end

	local h = headerH + bodyH + bottomPad
	local x = sw - margin - w + (1 - a) * ip(14, s)
	-- Altura de la tarjeta de carrera (NeonUI.raceH en race/neon_ui_style.lua).
	local raceHudH = 134
	local y = sh - margin - ip(raceHudH, s) - ip(12, s) - h
	if y < margin then
		y = margin
	end

	-- Tarjeta
	dxDrawRectangle(x, y, w, h, color(UI.bg, a), false)
	local border = color(UI.border, a)
	dxDrawRectangle(x, y, w, 1, border, false)
	dxDrawRectangle(x, y + h - 1, w, 1, border, false)
	dxDrawRectangle(x, y, 1, h, border, false)
	dxDrawRectangle(x + w - 1, y, 1, h, border, false)
	dxDrawRectangle(x, y, math.max(2, ip(2, s)), h, color(UI.accent, a), false)

	-- Cabecera compacta
	dxDrawText('RECORDS', x + pad, y, x + w - pad, y + headerH,
		color(UI.accent, a), px(1.0, s), 'default-bold',
		'left', 'center', true, false, false)

	if self.mapName ~= '' then
		dxDrawText(self.mapName,
			x + pad + ip(110, s), y, x + w - pad, y + headerH,
			color(UI.dim, a), px(0.8, s), 'default-bold',
			'right', 'center', true, false, false)
	end

	dxDrawRectangle(x + pad, y + headerH - 1, w - pad * 2, 1,
		color(UI.track, a), false)

	local bodyY = y + headerH

	if self.listStatus ~= 'Full' then
		dxDrawText('CARGANDO...', x + pad, bodyY, x + w - pad, bodyY + bodyH,
			color(UI.dim, a), px(0.85, s), 'default-bold',
			'center', 'center', true, false, false)
	elseif n == 0 then
		dxDrawText('SIN TIEMPOS', x + pad, bodyY, x + w - pad, bodyY + bodyH,
			color(UI.dim, a), px(0.85, s), 'default-bold',
			'center', 'center', true, false, false)
	else
		local posW = ip(44, s)
		local timeW = ip(92, s)
		local nameX = x + pad + posW
		local nameW = w - pad * 2 - posW - timeW

		for index, row in ipairs(self.rows) do
			local rowY = bodyY + (index - 1) * rowH
			local mine = (index == self.playerPosition)
			local empty = isEmptyRow(row)
			local leader = (index == 1 and not empty)

			if mine then
				dxDrawRectangle(x + 1, rowY, w - 2, rowH,
					color(UI.accentSoft, a * 0.28), false)
			elseif index % 2 == 0 then
				dxDrawRectangle(x + 1, rowY, w - 2, rowH,
					color(UI.track, a), false)
			end

			if leader then
				dxDrawRectangle(x, rowY, math.max(2, ip(2, s)), rowH,
					color(UI.accent, a), false)
			end

			local posColor = (leader or mine) and UI.accent or UI.text
			dxDrawText(index .. '.', x + pad, rowY, x + pad + posW, rowY + rowH,
				color(posColor, a), px(0.9, s), 'default-bold',
				'left', 'center', true, false, false)

			dxDrawText(empty and '-' or cleanName(row.playerName),
				nameX, rowY, nameX + nameW, rowY + rowH,
				color(mine and UI.accent or (empty and UI.dim or UI.text), a),
				px(0.92, s), 'default', 'left', 'center', true, false, false)

			dxDrawText(empty and '-' or formatTime(row.timeText),
				x + pad, rowY, x + w - pad, rowY + rowH,
				color((leader or mine) and UI.accent or (empty and UI.dim or UI.text), a),
				px(0.92, s), 'default-bold', 'right', 'center', true, false, false)

			dxDrawRectangle(x + pad, rowY + rowH - 1, w - pad * 2, 1,
				color(UI.track, a), false)
		end
	end
end

function CToptimes:doOnClientRender()
	if self.targetFade == self.currentFade and self.currentFade <= 0 then
		return
	end

	local currentSeconds = getTickCount() / 1000
	local deltaSeconds = currentSeconds - self.lastSeconds
	self.lastSeconds = currentSeconds
	deltaSeconds = math.clamp(0, deltaSeconds, 1 / 25)

	local fadeSpeed = self.targetFade < self.currentFade and 2 or 6
	local maxChange = deltaSeconds * fadeSpeed
	local dif = self.targetFade - self.currentFade
	dif = math.clamp(-maxChange, dif, maxChange)
	self.currentFade = self.currentFade + dif

	if self.currentFade < 0 then
		self.currentFade = 0
	elseif self.currentFade > 1 then
		self.currentFade = 1
	end

	if self.currentFade > 0 then
		self:draw()
	end
end

addEventHandler('onClientRender', root,
	function()
		if g_CToptimes then
			g_CToptimes:doOnClientRender()
		end
	end
)

function CToptimes:doToggleToptimes(bOn)
	self.autoOffTimer:killTimer()

	if bOn ~= nil then
		self.bManualShow = bOn
	else
		self.bManualShow = not self.bManualShow
	end

	if self.bManualShow then
		self.autoOffTimer:setTimer(function()
			self:doToggleToptimes(false)
		end, 15000, 1)
	end

	self:updateShow()
end

function onHotKey()
	if g_CToptimes then
		g_CToptimes:doToggleToptimes()
	end
end
addCommandHandler('showtimes', onHotKey)

addCommandHandler('doF5',
	function()
		if g_CToptimes then
			g_CToptimes:doToggleToptimes()
		end
	end
)

---------------------------------------------------------------------------
-- Instancia global
---------------------------------------------------------------------------
g_CToptimes = CToptimes:create()
