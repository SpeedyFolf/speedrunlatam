-- HUD del speedrun: cuenta regresiva, reloj, aviso de falla / mision cumplida y avisos.
-- El reloj es solo visual: parte de sr:go y cuenta con getTickCount(). El tiempo oficial es el del servidor.
SR = SR or {}
SR.running = false        -- hay una ronda en curso (reloj visible)
SR.spectating = false
SR.resultsVisible = false
SR.missionResource = nil  -- resource de la mision en curso (export srShowMissionBigText)
SR.passRespect = 5        -- numero de respeto para M_PASSR

local FONT_BIG = "bankgothic"
local FONT_TITLE = "pricedown"
local FONT_SMALL = "default-bold"
local MISSION_TEXT_MS = 5000
local COUNTDOWN_STEP_MS = 1000
local GO_SHOW_MS = 1000
local NOTICE_SHOW_MS = 6000
local NOTICE_MAX = 5

local sw, sh = guiGetScreenSize()
local function ui(n) return n * math.max(0.6, sh / 1080) end

local countdown = nil       -- { value, from }
local goUntil = 0
local localStart = nil      -- getTickCount() local equivalente al inicio del reloj del servidor
local finishedMs = nil      -- reloj congelado al terminar
local finishedUntil = 0
local finishedPos = 0
local failedUntil = 0
local failedReason = nil
local notices = {}          -- { text, expires }

addEvent("sr:countdown", true)
addEvent("sr:go", true)
addEvent("sr:failed", true)
addEvent("sr:finished", true)
addEvent("sr:notice", true)

-- Texto con borde negro para que se lea sobre cualquier fondo.
local function drawText(text, x1, y1, x2, y2, color, scale, font, alignX, alignY)
    alignX = alignX or "center"
    alignY = alignY or "center"
    local o = math.max(1, math.floor(ui(2)))
    local black = tocolor(0, 0, 0, 220)
    for _, d in ipairs({ { -o, 0 }, { o, 0 }, { 0, -o }, { 0, o } }) do
        dxDrawText(text, x1 + d[1], y1 + d[2], x2 + d[1], y2 + d[2], black, scale, font, alignX, alignY, false, false, false)
    end
    dxDrawText(text, x1, y1, x2, y2, color, scale, font, alignX, alignY, false, false, false)
end
SR.drawText = drawText
SR.ui = ui

-- El gamemode manda que mostrar; la mision presta el lease GXT y el tune nativo.
local function missionBigText(key, number, duration)
    local res = SR.missionResource
    if not res then return false end
    local ms = tonumber(duration) or MISSION_TEXT_MS
    local fn = function()
        if number ~= nil then
            return exports[res]:srShowMissionBigText(key, ms, number)
        end
        return exports[res]:srShowMissionBigText(key, ms)
    end
    local ok, result = pcall(fn)
    if not ok or result ~= true then
        outputDebugString(("sr:missionBigText %s fallo (res=%s ok=%s result=%s)"):format(
            tostring(key), tostring(res), tostring(ok), tostring(result)), 2)
    end
    return ok and result == true
end

function SR.resetRound()
    countdown, goUntil, localStart = nil, 0, nil
    finishedMs, finishedUntil, failedUntil = nil, 0, 0
    SR.running = false
    SR.missionResource = nil
    SR.passRespect = 5
end

-- La ronda termino (lo llama results.lua): el reloj se apaga.
-- El GXT de falla / cumplida no se toca: results.lua espera a que termine.
function SR.endRound()
    countdown, goUntil, localStart = nil, 0, nil
    SR.running = false
end

-- Milisegundos que le faltan al GXT de falla / mision cumplida para cumplir su tiempo minimo.
function SR.missionTextRemainingMs()
    local now = getTickCount()

    return math.max(0, failedUntil - now, finishedMs and (finishedUntil - now) or 0)
end

addEventHandler("sr:countdown", resourceRoot, function(seconds)
    if seconds >= 3 then
        SR.resetRound()
        if SR.hideResults then SR.hideResults() end
    end
    countdown = { value = seconds, from = getTickCount() }
end)

-- serverStartTick: referencia del servidor (informativa). elapsedMs: cuanto lleva el reloj al recibirlo
-- (0 en el inicio normal; mayor para quien entra a mitad de ronda).
-- missionResource: resource de la mision (export srShowMissionBigText). respect: numero para M_PASSR.
addEventHandler("sr:go", resourceRoot, function(serverStartTick, elapsedMs, missionResource, respect)
    countdown = nil
    SR.running = true
    finishedMs = nil
    SR.missionResource = type(missionResource) == "string" and missionResource or SR.missionResource
    SR.passRespect = tonumber(respect) or SR.passRespect
    localStart = getTickCount() - (tonumber(elapsedMs) or 0)
    if (tonumber(elapsedMs) or 0) == 0 then goUntil = getTickCount() + GO_SHOW_MS end
end)

addEventHandler("sr:failed", resourceRoot, function(reasonKey, textMs)
    local ms = tonumber(textMs) or MISSION_TEXT_MS
    failedReason = reasonKey
    failedUntil = getTickCount() + ms
    missionBigText("M_FAIL", nil, ms)
end)

addEventHandler("sr:finished", resourceRoot, function(timeMs, position)
    finishedMs = timeMs
    finishedPos = position
    finishedUntil = getTickCount() + MISSION_TEXT_MS
    failedUntil = 0
    missionBigText("M_PASSR", SR.passRespect)
end)

addEventHandler("sr:notice", resourceRoot, function(text)
    if type(text) ~= "string" then return end
    notices[#notices + 1] = { text = text, expires = getTickCount() + NOTICE_SHOW_MS }
    while #notices > NOTICE_MAX do table.remove(notices, 1) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("sr:clientReady", resourceRoot)
end)

addEventHandler("onClientRender", root, function()
    local now = getTickCount()
    local cx = sw / 2

    -- Reloj arriba al centro
    if SR.running and localStart then
        local ms = finishedMs or math.max(0, now - localStart)
        local color = finishedMs and tocolor(120, 255, 120, 255) or tocolor(255, 255, 255, 255)
        drawText(Results.formatTime(ms), cx - ui(250), ui(14), cx + ui(250), ui(74), color, ui(1.4), FONT_BIG)
    end

    -- Cuenta regresiva
    if countdown then
        if now - countdown.from <= COUNTDOWN_STEP_MS + 300 then
            local t = (now - countdown.from) / COUNTDOWN_STEP_MS
            local pop = 1 + math.max(0, 0.35 * (1 - t * 2))
            drawText(tostring(countdown.value), 0, sh * 0.25, sw, sh * 0.5, tocolor(255, 220, 60, 255), ui(5) * pop, FONT_TITLE)
        end
    elseif now < goUntil then
        drawText("¡YA!", 0, sh * 0.25, sw, sh * 0.5, tocolor(120, 255, 120, 255), ui(5), FONT_TITLE)
    end

    -- Falla: el cartel grande lo pone el GXT de la mision.
    if now < failedUntil and failedReason == "death" then
        drawText("Moriste. La misión se reinicia; el reloj sigue.", 0, sh * 0.5, sw, sh * 0.56,
            tocolor(255, 190, 190, 255), ui(1.3), FONT_SMALL)
    end

    -- Mision cumplida: GXT de la mision + tiempo/puesto del gamemode.
    if now < finishedUntil and finishedMs then
        drawText(("%s  (%dº)"):format(Results.formatTime(finishedMs), finishedPos), 0, sh * 0.5, sw, sh * 0.58,
            tocolor(255, 255, 255, 255), ui(1.8), FONT_BIG)
    end

    -- Avisos (arriba a la derecha)
    local y = ui(110)
    for i = #notices, 1, -1 do
        if notices[i].expires <= now then table.remove(notices, i) end
    end
    for _, n in ipairs(notices) do
        drawText(n.text, sw - ui(620), y, sw - ui(20), y + ui(26), tocolor(255, 255, 255, 255), ui(1.2), FONT_SMALL, "right")
        y = y + ui(26)
    end

    -- Sin ronda: espera
    if not SR.running and not countdown and not SR.resultsVisible and not SR.spectating then
        drawText("Esperando la próxima misión", 0, ui(20), sw, ui(70), tocolor(255, 255, 255, 230), ui(1.1), FONT_BIG)
    end
end)
