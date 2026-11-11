-- helpmanager_client.lua
-- Panel de ayuda con la estética Neon (DirectX), igual que el resto del server.
-- Lista clickeable de recursos a la izquierda y el texto de ayuda a la derecha.
-- Abre/cierra con F9 o /help. Sin elementos GUI de MTA.

local HELP_KEY = "F9"
local HELP_COMMAND = "help"
local POPUP_TIMEOUT = 15000

local FONT_TITLE = "default-bold"
local FONT_TEXT = "default-bold"

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
	-- Escala por altura (legibilidad) con piso/techo: no se achica en 4:3 ni se
	-- agranda de mas en ultrawide.
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

--
-- Estado
--

local pages = {}          -- [resource] = { title = string, text = string }
local pageOrder = {}      -- array de recursos, ordenado por titulo
local selectedResource = nil
local open = false
local listScroll = 0      -- en filas
local contentScroll = 0   -- en pixeles

local contentRT, rtW, rtH = nil, 0, 0

local unseenPending = 0
local popupActive = false
local popupReminder = false
local popupStart = 0
local popupDebounce = nil
local seenXml = nil

local function titleOf(resource)
	local page = pages[resource]
	if page then
		return page.title
	end
	return getResourceName(resource) or "?"
end

local function textOf(resource)
	local page = pages[resource]
	return (page and page.text) or ""
end

local function refreshPageList()
	pageOrder = {}
	for resource in pairs(pages) do
		pageOrder[#pageOrder + 1] = resource
	end
	table.sort(pageOrder, function(a, b)
		return string.lower(titleOf(a)) < string.lower(titleOf(b))
	end)
	if selectedResource and not pages[selectedResource] then
		selectedResource = nil
	end
	if not selectedResource then
		selectedResource = pageOrder[1]
	end
end

local function selectPage(resource)
	if pages[resource] then
		selectedResource = resource
		contentScroll = 0
	end
end

--
-- Geometria
--

local function getLayout(sw, sh, s)
	-- Responsive: porcentaje de pantalla con tope, asi se adapta a cualquier
	-- aspect ratio (16:9, 21:9, 4:3...) sin desperdiciar resoluciones altas.
	local w = math.min(sw * 0.84, ip(1200, s))
	local h = math.min(sh * 0.84, ip(780, s))
	local x = math.floor((sw - w) / 2)
	local y = math.floor((sh - h) / 2)
	local pad = ip(20, s)
	local headerH = ip(66, s)
	local rowH = ip(44, s)
	local sidebarW = math.floor(math.min(math.max(w * 0.27, ip(220, s)), ip(380, s)))
	local listX = x + pad
	local listY = y + headerH
	local listW = sidebarW - pad
	local listH = h - headerH - pad
	local contentX = x + sidebarW + ip(14, s)
	local contentY = y + headerH + ip(8, s)
	local contentW = w - sidebarW - pad - ip(14, s)
	local contentH = h - headerH - pad - ip(8, s)
	return {
		x = x, y = y, w = w, h = h, pad = pad, headerH = headerH,
		sidebarW = sidebarW, rowH = rowH,
		listX = listX, listY = listY, listW = listW, listH = listH,
		contentX = contentX, contentY = contentY, contentW = contentW, contentH = contentH,
	}
end

local function estimateTextHeight(text, maxW, fontScale)
	local lineH = dxGetFontHeight(fontScale, FONT_TEXT)
	local total = 0
	for line in (tostring(text) .. "\n"):gmatch("(.-)\n") do
		local w = dxGetTextWidth(line ~= "" and line or " ", fontScale, FONT_TEXT)
		total = total + math.max(1, math.ceil(w / math.max(1, maxW)))
	end
	return total * lineH
end

local function ensureRT(w, h)
	w = math.floor(w)
	h = math.floor(h)
	if w <= 0 or h <= 0 then
		return nil
	end
	if contentRT and isElement(contentRT) and rtW == w and rtH == h then
		return contentRT
	end
	if contentRT and isElement(contentRT) then
		destroyElement(contentRT)
	end
	contentRT = dxCreateRenderTarget(w, h, true)
	rtW, rtH = w, h
	return contentRT
end

--
-- Dibujo
--

local function drawCard(x, y, w, h, s, a)
	dxDrawRectangle(x, y, w, h, color(UI.bg, a), false)
	local border = color(UI.border, a)
	dxDrawRectangle(x, y, w, 1, border, false)
	dxDrawRectangle(x, y + h - 1, w, 1, border, false)
	dxDrawRectangle(x, y, 1, h, border, false)
	dxDrawRectangle(x + w - 1, y, 1, h, border, false)
	dxDrawRectangle(x, y, math.max(2, ip(2, s)), h, color(UI.accent, a), false)
end

local function draw(sw, sh, s)
	local L = getLayout(sw, sh, s)
	local a = 1

	drawCard(L.x, L.y, L.w, L.h, s, a)

	-- Cabecera
	dxDrawText("AYUDA", L.x + L.pad, L.y, L.x + L.w - L.pad, L.y + L.headerH,
		color(UI.accent, a), px(1.5, s), FONT_TITLE, "left", "center", true, false, false)
	dxDrawText("Rueda del mouse para desplazar  ·  " .. HELP_KEY .. " o /" .. HELP_COMMAND .. " para cerrar",
		L.x + L.pad, L.y, L.x + L.w - L.pad, L.y + L.headerH,
		color(UI.dim, a), px(0.9, s), FONT_TITLE, "right", "center", true, false, false)
	dxDrawRectangle(L.x + L.pad, L.y + L.headerH - 1, L.w - L.pad * 2, 1, color(UI.track, a), false)

	-- Fondo de la barra lateral
	dxDrawRectangle(L.listX, L.listY, L.listW, L.listH, color(UI.track, a), false)

	local rowH = L.rowH
	local visibleRows = math.max(1, math.floor(L.listH / rowH))
	local maxListScroll = math.max(0, #pageOrder - visibleRows)
	if listScroll > maxListScroll then listScroll = maxListScroll end
	if listScroll < 0 then listScroll = 0 end

	local hovered = nil
	if isCursorShowing() then
		local mx, my = getCursorPosition()
		if mx and my and mx >= L.listX and mx <= L.listX + L.listW and my >= L.listY and my <= L.listY + L.listH then
			hovered = math.floor((my - L.listY) / rowH) + listScroll + 1
		end
	end

	for i = 1, visibleRows do
		local idx = i + listScroll
		local resource = pageOrder[idx]
		if not resource then
			break
		end
		local ry = L.listY + (i - 1) * rowH
		local selected = (resource == selectedResource)

		if selected then
			dxDrawRectangle(L.listX, ry, L.listW, rowH, color(UI.accentSoft, a * 0.20), false)
			dxDrawRectangle(L.listX, ry, math.max(2, ip(2, s)), rowH, color(UI.accent, a), false)
		elseif hovered == idx then
			dxDrawRectangle(L.listX, ry, L.listW, rowH, color(UI.track, a * 1.6), false)
		end

		dxDrawText(titleOf(resource), L.listX + ip(12, s), ry, L.listX + L.listW - ip(8, s), ry + rowH,
			color(selected and UI.accent or UI.text, a), px(1.0, s), FONT_TITLE, "left", "center", true, false, false)
	end

	-- Separador vertical
	dxDrawRectangle(L.contentX - ip(6, s), L.listY, 1, L.listH, color(UI.track, a), false)

	-- Fondo del contenido: solido y oscuro para que el texto contraste.
	local wellBorder = color(UI.border, a)
	dxDrawRectangle(L.contentX, L.contentY, L.contentW, L.contentH, tocolor(4, 8, 14, 235), false)
	dxDrawRectangle(L.contentX, L.contentY, L.contentW, 1, wellBorder, false)
	dxDrawRectangle(L.contentX, L.contentY + L.contentH - 1, L.contentW, 1, wellBorder, false)
	dxDrawRectangle(L.contentX, L.contentY, 1, L.contentH, wellBorder, false)
	dxDrawRectangle(L.contentX + L.contentW - 1, L.contentY, 1, L.contentH, wellBorder, false)

	local innerPad = ip(16, s)
	local textX = L.contentX + innerPad
	local textY = L.contentY + innerPad
	local textW = L.contentW - innerPad * 2
	local textH = L.contentH - innerPad * 2

	if selectedResource and textOf(selectedResource) ~= "" then
		local fontScale = px(1.15, s)
		local maxContentScroll = math.max(0, estimateTextHeight(textOf(selectedResource), textW, fontScale) - textH)
		if contentScroll > maxContentScroll then contentScroll = maxContentScroll end
		if contentScroll < 0 then contentScroll = 0 end

		local rt = ensureRT(textW, textH)
		if rt then
			dxSetRenderTarget(rt, true)
			dxDrawText(textOf(selectedResource), 0, -contentScroll, textW, textH + contentScroll + 4000,
				color(UI.text, 1), fontScale, FONT_TEXT, "left", "top", true, true, false)
			dxSetRenderTarget()
			dxDrawImage(textX, textY, textW, textH, rt, 0, 0, 0, tocolor(255, 255, 255, 255), false)
		else
			dxDrawText(textOf(selectedResource), textX, textY, textX + textW, textY + textH,
				color(UI.text, a), fontScale, FONT_TEXT, "left", "top", true, true, false)
		end
	else
		dxDrawText(#pageOrder > 0 and "Selecciona una ayuda de la lista." or "No hay páginas de ayuda disponibles.",
			textX, textY, textX + textW, textY + textH,
			color(UI.dim, a), px(1.1, s), FONT_TITLE, "center", "center", true, false, false)
	end
end

-- Muestra un recordatorio corto de que existe la ayuda.
local function showHelpReminder()
	if popupActive then
		return
	end
	popupReminder = true
	unseenPending = 0
	popupActive = true
	popupStart = getTickCount()
end

local function drawPopup(sw, sh, s)
	if not popupActive then
		return
	end

	local elapsed = getTickCount() - popupStart
	if elapsed >= POPUP_TIMEOUT then
		popupActive = false
		popupReminder = false
		unseenPending = 0
		return
	end

	local fade = 1
	if elapsed < 300 then
		fade = elapsed / 300
	elseif elapsed > POPUP_TIMEOUT - 600 then
		fade = math.max(0, (POPUP_TIMEOUT - elapsed) / 600)
	end

	local msg
	if popupReminder then
		msg = "¿Necesitas ayuda? Presiona " .. HELP_KEY .. " o /" .. HELP_COMMAND .. "."
	elseif unseenPending > 1 then
		msg = "Hay " .. unseenPending .. " páginas de ayuda disponibles. Presiona " .. HELP_KEY .. " o /" .. HELP_COMMAND .. " para verlas."
	else
		msg = "Página de ayuda disponible. Presiona " .. HELP_KEY .. " o /" .. HELP_COMMAND .. " para verla."
	end
	-- Ancho ajustado al texto (con padding), centrado y abajo.
	local fontScale = px(1.0, s)
	local textW = dxGetTextWidth(msg, fontScale, FONT_TITLE)
	local fontH = dxGetFontHeight(fontScale, FONT_TITLE)
	local padX = ip(22, s)
	local padY = ip(14, s)
	local w = math.max(ip(180, s), math.min(sw - ip(80, s), textW + padX * 2))
	local h = fontH + padY * 2
	local x = (sw - w) / 2
	local y = sh - ip(48, s) - h

	drawCard(x, y, w, h, s, fade)
	dxDrawText(msg, x, y, x + w, y + h,
		color(UI.text, fade), fontScale, FONT_TITLE, "center", "center", true, false, false)
end

--
-- Abrir / cerrar
--

local function setOpen(state)
	open = state
	if open then
		showCursor(true)
		triggerEvent("onHelpShown", localPlayer)
	else
		showCursor(false)
		triggerEvent("onHelpHidden", localPlayer)
	end
end

function showHelp()
	setOpen(true)
	return true
end
addEventHandler("doShowHelp", root, showHelp)

function hideHelp()
	setOpen(false)
	return true
end
addEventHandler("doHideHelp", root, hideHelp)

function clientToggleHelp(state)
	if state ~= true and state ~= false then
		state = not open
	end
	setOpen(state)
	return true
end

--
-- Paginas de ayuda
--

local function loadSeen()
	if not seenXml then
		seenXml = xmlLoadFile("seen.xml")
		if not seenXml then
			seenXml = xmlCreateFile("seen.xml", "seen")
		end
	end
	return seenXml
end

local function isSeen(resourceName)
	local xml = loadSeen()
	if not xml then
		return true
	end
	local contents = xmlNodeGetValue(xml) or ""
	for page in contents:gmatch("([^,]+)") do
		if page == resourceName then
			return true
		end
	end
	return false
end

local function markSeen(resourceName)
	local xml = loadSeen()
	if not xml then
		return
	end
	local contents = xmlNodeGetValue(xml) or ""
	xmlNodeSetValue(xml, contents .. resourceName .. ",")
	xmlSaveFile(xml)
end

local function queuePopup(resource)
	local resourceName = getResourceName(resource)
	if not resourceName or isSeen(resourceName) then
		return
	end
	markSeen(resourceName)
	unseenPending = unseenPending + 1
	-- Debounce: agrupa todas las paginas nuevas en un solo aviso.
	if not popupDebounce then
		popupDebounce = setTimer(function()
			popupDebounce = nil
			popupReminder = false
			popupActive = true
			popupStart = getTickCount()
		end, 800, 1)
	end
end

-- Devuelve el resource element valido para `value`, o nil.
-- Usa getElementID + getResourceFromName (no dispara warnings con elementos que
-- no son resource, como los resource root que devuelve getElementsByType).
local function asResource(value)
	if not isElement(value) then
		return nil
	end
	local name = getElementID(value)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	return getResourceFromName(name)
end

function addHelpTab(resource, showPopup)
	resource = asResource(resource) or asResource(source)
	if not resource or pages[resource] then
		return false
	end
	-- El propio helpmanager no se lista a si mismo.
	if resource == getThisResource() then
		return false
	end

	local title = getResourceName(resource)
	if not title then
		return false
	end

	local text = ""
	local helpnode = getResourceConfig(":" .. title .. "/help.xml")
	if helpnode then
		title = xmlNodeGetAttribute(helpnode, "title") or title
		text = (xmlNodeGetValue(helpnode) or ""):gsub("\r", "")
	end

	pages[resource] = { title = title, text = text }
	refreshPageList()

	if showPopup ~= false then
		queuePopup(resource)
	end
	return true
end

function removeHelpTab(resource)
	resource = asResource(resource) or asResource(source)
	if not resource or not pages[resource] then
		return false
	end
	pages[resource] = nil
	refreshPageList()
	return true
end
addEventHandler("onClientResourceStop", root, removeHelpTab)

function addHelpTabFromXML(resource)
	resource = asResource(resource) or asResource(source)
	if not resource or pages[resource] then
		return false
	end
	-- El propio helpmanager no se lista a si mismo.
	if resource == getThisResource() then
		return false
	end
	local title = getResourceName(resource)
	if not title then
		return false
	end
	local helpnode = getResourceConfig(":" .. title .. "/help.xml")
	if helpnode then
		addHelpTab(resource, xmlNodeGetAttribute(helpnode, "popup") ~= "no")
	end
end
addEventHandler("onClientResourceStart", root, addHelpTabFromXML)

--
-- Interaccion
--

addEventHandler("onClientClick", root,
	function(button, state, absX, absY)
		if not open or button ~= "left" or state ~= "down" then
			return
		end
		local sw, sh, s = screenScale()
		local L = getLayout(sw, sh, s)

		-- Clic afuera de la tarjeta: cerrar.
		if absX < L.x or absX > L.x + L.w or absY < L.y or absY > L.y + L.h then
			hideHelp()
			return true
		end

		-- Clic en la lista lateral: seleccionar.
		if absX >= L.listX and absX <= L.listX + L.listW and absY >= L.listY and absY <= L.listY + L.listH then
			local idx = math.floor((absY - L.listY) / L.rowH) + listScroll + 1
			local resource = pageOrder[idx]
			if resource then
				selectPage(resource)
			end
		end
		return true
	end, false
)

local function scrollHelp(delta)
	if not open or not isCursorShowing() then
		return
	end
	local sw, sh, s = screenScale()
	local L = getLayout(sw, sh, s)
	local mx, my = getCursorPosition()
	if not mx or not my then
		return
	end
	if mx >= L.listX and mx <= L.listX + L.listW and my >= L.listY and my <= L.listY + L.listH then
		listScroll = math.max(0, listScroll + delta)
	else
		contentScroll = math.max(0, contentScroll + delta * ip(30, s))
	end
end

local function onWheelUp()
	scrollHelp(-1)
end

local function onWheelDown()
	scrollHelp(1)
end

bindKey("mouse_wheel_up", "down", onWheelUp)
bindKey("mouse_wheel_down", "down", onWheelDown)

-- Recordatorio de ayuda: 50% de las veces al cargar un mapa de race.
addEvent("onClientMapStarting", true)
addEventHandler("onClientMapStarting", root,
	function()
		if open then
			return
		end
		if math.random(100) <= 50 then
			showHelpReminder()
		end
	end
)

addEventHandler("onClientRender", root,
	function()
		local sw, sh, s = screenScale()
		if open then
			draw(sw, sh, s)
		end
		drawPopup(sw, sh, s)
	end
)

addEventHandler("onClientRestore", root,
	function()
		if contentRT and isElement(contentRT) then
			destroyElement(contentRT)
		end
		contentRT, rtW, rtH = nil, 0, 0
	end
)

--
-- Arranque
--

addEventHandler("onClientResourceStart", resourceRoot,
	function()
		-- Primero el atajo: asi F9 /help funcionan aunque falle alguna pagina.
		addCommandHandler(HELP_COMMAND, clientToggleHelp)
		bindKey(HELP_KEY, "down", clientToggleHelp)

		-- Cargar las paginas de ayuda disponibles.
		for _, resRoot in ipairs(getElementsByType("resource") or {}) do
			pcall(addHelpTabFromXML, resRoot)
		end
	end
)

addEventHandler("onClientResourceStop", resourceRoot,
	function()
		if open then
			setOpen(false)
		end
		if popupDebounce and isTimer(popupDebounce) then
			killTimer(popupDebounce)
		end
		popupDebounce = nil
	end
)
