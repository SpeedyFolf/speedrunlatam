-- Panel de records del speedrun (F5 / /records / /top).
-- Solo lectura: no crea GUI ni captura clicks. Se dibuja abajo a la derecha
-- para poder seguir jugando mientras se mira. F5 (o el comando) lo cierra.
SR = SR or {}

local FONT_TITLE = "pricedown"
local FONT_SMALL = "default-bold"
local PANEL_W = 380
local MAX_ROWS = 10

local open = false
local data = nil

addEvent("sr:records", true)

local function clean(name)
    return (tostring(name or ""):gsub("#%x%x%x%x%x%x", ""))
end

-- ip2c publica las banderas en su propio resource. Si el cliente todavia no
-- las descargo, dxDrawImage las pide y aparecen en los frames siguientes.
local function ip2cReady()
    local res = getResourceFromName("ip2c")
    return res and getResourceState(res) == "running"
end

local function flagPath(country)
    if type(country) ~= "string" or not ip2cReady() then return nil end
    country = string.lower(country)
    if not country:match("^%a%a$") or country == "zz" then return nil end
    return ":ip2c/client/images/flags/" .. country .. ".png"
end

local function request(missionId)
    data = nil
    triggerServerEvent("sr:requestRecords", resourceRoot, missionId)
end

local function toggleRecords(missionId)
    if open and (type(missionId) ~= "string" or missionId == "") then
        open = false
        data = nil
        return
    end
    open = true
    request(type(missionId) == "string" and missionId ~= "" and missionId or nil)
end

function SR.hideRecords()
    open = false
    data = nil
end

addEventHandler("sr:records", resourceRoot, function(payload)
    if not open or type(payload) ~= "table" then return end
    data = payload
end)

-- Si arranca una ronda nueva o termina con el panel abierto, refrescar.
addEventHandler("sr:go", resourceRoot, function()
    if open then request() end
end)

addEventHandler("sr:results", resourceRoot, function()
    if open then request() end
end)

local function drawPanel()
    if not open or SR.hudHidden or SR.resultsVisible then return end
    local ui, drawText = SR.ui, SR.drawText
    if not ui or not drawText then return end

    local sw, sh = guiGetScreenSize()
    local w = ui(PANEL_W)
    local rowH = ui(24)
    local headH = ui(48)
    local footH = ui(36)
    local rows = type(data) == "table" and type(data.rows) == "table" and data.rows or {}
    local shown = math.min(#rows, MAX_ROWS)
    local bodyRows = math.max(shown, 2) -- lugar para "Sin tiempos registrados"
    local h = headH + rowH * (bodyRows + 1) + footH
    local x = sw - w - ui(20)
    local y = sh - h - ui(20)

    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 175))
    dxDrawRectangle(x, y, w, ui(2), tocolor(255, 220, 60, 220))

    local title
    if type(data) ~= "table" then
        title = "RÉCORDS"
    elseif data.mode == "summary" then
        title = "RÉCORDS · MISIONES"
    else
        title = "RÉCORDS · " .. tostring(data.title or data.missionId or "?")
    end
    drawText(title, x + ui(12), y + ui(6), x + w - ui(12), y + ui(34),
        tocolor(255, 220, 60, 255), ui(1.05), FONT_TITLE, "left")

    if type(data) ~= "table" then
        drawText("Cargando...", x + ui(12), y + headH, x + w - ui(12), y + h - footH,
            tocolor(190, 190, 190, 255), ui(0.95), FONT_SMALL, "center")
        return
    end

    local colRank = x + ui(12)
    local colFlag = x + ui(40)
    local colName = x + ui(66)
    local colTime = x + w - ui(12)
    local ry = y + headH
    local head = tocolor(190, 190, 190, 255)
    drawText("#", colRank, ry, colRank + ui(24), ry + rowH, head, ui(0.9), FONT_SMALL, "left")
    drawText("Jugador", colName, ry, colName + ui(200), ry + rowH, head, ui(0.9), FONT_SMALL, "left")
    drawText("Tiempo", colTime - ui(90), ry, colTime, ry + rowH, head, ui(0.9), FONT_SMALL, "right")
    ry = ry + rowH

    if shown == 0 then
        drawText("Sin tiempos registrados", x + ui(12), ry, x + w - ui(12), ry + rowH * 2,
            tocolor(170, 170, 170, 255), ui(0.95), FONT_SMALL, "center")
    end

    for i = 1, shown do
        local row = rows[i]
        local color = i == 1 and tocolor(255, 220, 60, 255) or tocolor(255, 255, 255, 255)
        local name, timeMs, country
        if data.mode == "summary" then
            name = tostring(row.title or row.mission or "?")
            timeMs = tonumber(row.time_ms) or 0
            country = row.country
        else
            name = clean(row.account)
            timeMs = tonumber(row.time_ms) or 0
            country = row.country
        end

        drawText(tostring(i) .. "º", colRank, ry, colRank + ui(24), ry + rowH, color, ui(0.95), FONT_SMALL, "left")
        local flag = flagPath(country)
        if flag then
            dxDrawImage(colFlag, ry + ui(4), ui(20), ui(13), flag)
        else
            dxDrawRectangle(colFlag, ry + ui(6), ui(20), ui(10), tocolor(255, 255, 255, 22))
        end
        drawText(name, colName, ry, colName + ui(200), ry + rowH, color, ui(0.95), FONT_SMALL, "left")
        drawText(Results.formatTime(timeMs), colTime - ui(90), ry, colTime, ry + rowH, color, ui(0.95), FONT_SMALL, "right")
        ry = ry + rowH
    end

    local footY = y + h - footH
    if data.mode ~= "summary" then
        local personal = tonumber(data.personal)
        local text = personal and ("Tu mejor: " .. Results.formatTime(personal)) or "Tu mejor: —"
        drawText(text, x + ui(12), footY, x + w - ui(12), footY + ui(17),
            tocolor(255, 220, 60, 255), ui(0.9), FONT_SMALL, "left")
    end
    drawText("F5 / /records para cerrar", x + ui(12), footY + ui(17), x + w - ui(12), footY + footH,
        tocolor(160, 160, 160, 255), ui(0.85), FONT_SMALL, "left")
end

addEventHandler("onClientRender", root, drawPanel)

addCommandHandler("records", function(_, missionId) toggleRecords(missionId) end)
addCommandHandler("top", function(_, missionId) toggleRecords(missionId) end)

local function onHotkey()
    toggleRecords()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    unbindKey("F5", "down", onHotkey)
    bindKey("F5", "down", onHotkey)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey("F5", "down", onHotkey)
end)
