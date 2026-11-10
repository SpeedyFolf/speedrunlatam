-- HUD del speedrun: cuenta regresiva, reloj, aviso de falla / mision cumplida y avisos.
-- El reloj es solo visual: parte de sr:go y cuenta con getTickCount(). El tiempo oficial es el del servidor.
SR = SR or {}
SR.running = false        -- hay una ronda en curso (reloj visible)
SR.spectating = false
SR.resultsVisible = false

local FONT_BIG = "bankgothic"
local FONT_TITLE = "pricedown"
local FONT_SMALL = "default-bold"
-- Fuente de los carteles de mision cumplida / fallida, como en GTA SA. MTA la trae integrada
-- (MTA/cgui/pricedown.ttf): tiene ¡ y vocales con tilde, pero no "º".
local FONT_BANNER = "pricedown"
local BANNER_SCALE = 4
local COLOR_PASSED = { 225, 160, 30 }   -- dorado de "MISIÓN SUPERADA!"
local COLOR_FAILED = { 180, 25, 29 }    -- rojo de "MISIÓN FALLIDA!"
local SOUND_PASSED = "audio/mission_accomplished.mp3"  -- copia del de race (race no corre junto a speedrun)
local COUNTDOWN_STEP_MS = 1000
local GO_SHOW_MS = 1000
local FAILED_SHOW_MS = 4000
local FINISHED_SHOW_MS = 4000
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

-- Cartel grande al estilo GTA SA: Pricedown con borde negro grueso (8 direcciones).
local function drawBanner(text, y1, y2, rgb)
    local o = math.max(2, math.floor(ui(3)))
    local black = tocolor(0, 0, 0, 255)
    local scale = ui(BANNER_SCALE)
    for dx = -o, o, o do
        for dy = -o, o, o do
            if dx ~= 0 or dy ~= 0 then
                dxDrawText(text, dx, y1 + dy, sw + dx, y2 + dy, black, scale, FONT_BANNER, "center", "center", false, false, false)
            end
        end
    end
    dxDrawText(text, 0, y1, sw, y2, tocolor(rgb[1], rgb[2], rgb[3], 255), scale, FONT_BANNER, "center", "center", false, false, false)
end

function SR.resetRound()
    countdown, goUntil, localStart = nil, 0, nil
    finishedMs, finishedUntil, failedUntil = nil, 0, 0
    SR.running = false
end

-- La ronda termino (lo llama results.lua): el reloj se apaga.
-- Los carteles de falla / cumplida no se tocan: results.lua espera a que terminen.
function SR.endRound()
    countdown, goUntil, localStart = nil, 0, nil
    SR.running = false
end

-- Milisegundos que le faltan al cartel de falla / mision cumplida para cumplir su tiempo minimo.
function SR.bannerRemainingMs()
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
addEventHandler("sr:go", resourceRoot, function(serverStartTick, elapsedMs)
    countdown = nil
    SR.running = true
    finishedMs = nil
    localStart = getTickCount() - (tonumber(elapsedMs) or 0)
    if (tonumber(elapsedMs) or 0) == 0 then goUntil = getTickCount() + GO_SHOW_MS end
end)

addEventHandler("sr:failed", resourceRoot, function(reasonKey)
    failedReason = reasonKey
    failedUntil = getTickCount() + FAILED_SHOW_MS
end)

addEventHandler("sr:finished", resourceRoot, function(timeMs, position)
    finishedMs = timeMs
    finishedPos = position
    finishedUntil = getTickCount() + FINISHED_SHOW_MS
    failedUntil = 0
    playSound(SOUND_PASSED)
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

    -- Falla
    if now < failedUntil then
        drawBanner("¡Misión fallida!", sh * 0.3, sh * 0.45, COLOR_FAILED)
        if failedReason == "death" then
            drawText("Moriste. La misión se reinicia; el reloj sigue.", 0, sh * 0.45, sw, sh * 0.5,
                tocolor(255, 190, 190, 255), ui(1.3), FONT_SMALL)
        end
    end

    -- Mision cumplida
    if now < finishedUntil and finishedMs then
        drawBanner("¡Misión cumplida!", sh * 0.3, sh * 0.45, COLOR_PASSED)
        drawText(("%s  (%dº)"):format(Results.formatTime(finishedMs), finishedPos), 0, sh * 0.45, sw, sh * 0.52,
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
