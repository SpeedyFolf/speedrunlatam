-- Cliente de "Sweet's Girl": recibe las ordenes del servidor para la copia del jugador local.
-- Eventos servidor -> cliente (todos con el token de la copia como primer argumento):
--   sr5:begin(token, info)            copia nueva: texto SWEET5, precarga, barra en info.health
--   sr5:end(token)                    copia destruida: se limpia todo
--   sr5:stage(token, name)            etapa nueva (solo informativa)
--   sr5:go(token)                     largada
--   sr5:health(token, value|false)    barra de Sweet (false = CLEAR_ONSCREEN_COUNTER)
--   sr5:text(token, key, ms)          showMissionText (PRINT_NOW)
--   sr5:help(token, key)              showMissionHelp (PRINT_HELP)
--   sr5:audio(token, id, keys, opts)  secuencia de audio; opts.report -> sr5:audioDone al terminar
--   sr5:task(token, el, name, args)   tarea de actor (client/actors.lua y client/chase.lua)
--   sr5:passed(token)                 mision cumplida: PLAY_MISSION_PASSED_TUNE 1
-- Cliente -> servidor: sr5:clientReady, sr5:audioDone(token, id), sr5:clientLog(token, kind, text),
--   sr5:carBase(token, veh, base) (solo en scene2: altura del auto para el salto de la escena).
-- Areas de mision (renderScriptImportantArea) segun la etapa: recogida en scene2, llegada en scene3.
Sw5Client = { token = nil, stage = nil }
local state = Sw5Client

local function isCurrent(token)
    return state.token ~= nil and token == state.token
end

function Sw5Client.log(kind, detail)
    if not state.token then return end
    triggerServerEvent("sr5:clientLog", resourceRoot, state.token, kind, tostring(detail or ""))
end

local setAreas -- forward

function Sw5Client.reset()
    setAreas(nil)
    Actors.reset()
    TextAudio.stop()
    state.token = nil
    state.stage = nil
end

local function preload()
    local p = SW5.PRELOAD
    if type(enginePreloadWorldAreaInDirection) == "function" then
        pcall(enginePreloadWorldAreaInDirection, Vector3(p.x, p.y, p.z), p.heading)
    end
end

---------------------------------------------------------------------------
-- Areas de mision: LOCATE_CHAR_ANY_MEANS_3D ... TRUE (marca roja), se dibuja cada frame.
---------------------------------------------------------------------------
local AREAS = {
    scene2 = { p = SW5.PICKUP_LOCATE },
    scene3 = { p = SW5.FINISH_PLAYER },
}
local currentArea = nil

local function drawArea()
    local a = currentArea
    if not a or type(renderScriptImportantArea) ~= "function" then return end
    pcall(renderScriptImportantArea, Vector3(a.p.x, a.p.y, a.p.z), a.p.rx, a.p.ry)
end

setAreas = function(stage)
    local area = stage and AREAS[stage] or nil
    if area and not currentArea then
        addEventHandler("onClientPreRender", root, drawArea)
    elseif not area and currentArea then
        removeEventHandler("onClientPreRender", root, drawArea)
    end
    currentArea = area
end

-- Base del modelo del auto que usa el jugador (solo la altura de SET_CAR_COORDINATES en T0).
local function sendCarBase()
    if not state.token or state.stage ~= "scene2" then return end
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end
    local ok, base = pcall(getElementDistanceFromCentreOfMassToBaseOfModel, veh)
    if ok and type(base) == "number" then
        triggerServerEvent("sr5:carBase", resourceRoot, state.token, veh, base)
    end
end

addEventHandler("onClientPlayerVehicleEnter", localPlayer, function()
    sendCarBase()
end)

addEvent("sr5:begin", true)
addEventHandler("sr5:begin", resourceRoot, function(token, info)
    if type(token) ~= "number" then return end
    Sw5Client.reset()
    state.token = token
    TextAudio.start()
    preload()
    if type(info) == "table" and info.health then TextAudio.setHealth(info.health) end
end)

addEvent("sr5:end", true)
addEventHandler("sr5:end", resourceRoot, function(token)
    if isCurrent(token) then Sw5Client.reset() end
end)

addEvent("sr5:stage", true)
addEventHandler("sr5:stage", resourceRoot, function(token, name)
    if not isCurrent(token) then return end
    state.stage = name
    if name ~= "scene1" then Actors.stopScene1() end
    setAreas(name)
    if name == "scene2" then sendCarBase() end
end)

addEvent("sr5:passed", true)
addEventHandler("sr5:passed", resourceRoot, function(token)
    if not isCurrent(token) then return end
    setAreas(nil)
end)

addEvent("sr5:go", true)
addEventHandler("sr5:go", resourceRoot, function(token)
    if not isCurrent(token) then return end
    state.goAt = getTickCount()
end)

addEvent("sr5:health", true)
addEventHandler("sr5:health", resourceRoot, function(token, value)
    if not isCurrent(token) then return end
    TextAudio.setHealth(value or nil)
end)

addEvent("sr5:text", true)
addEventHandler("sr5:text", resourceRoot, function(token, key, duration)
    if not isCurrent(token) or type(key) ~= "string" or not SW5.TEXT_KEYS[key] then return end
    TextAudio.showText(key, tonumber(duration) or 4000)
end)

addEvent("sr5:help", true)
addEventHandler("sr5:help", resourceRoot, function(token, key)
    if not isCurrent(token) or type(key) ~= "string" or not SW5.TEXT_KEYS[key] then return end
    TextAudio.showHelp(key)
end)

addEvent("sr5:audio", true)
addEventHandler("sr5:audio", resourceRoot, function(token, id, keys, opts)
    if not isCurrent(token) or type(id) ~= "string" or type(keys) ~= "table" then return end
    opts = type(opts) == "table" and opts or {}
    local accepted = TextAudio.playSequence(id, keys, opts, function()
        if state.token ~= token then return end
        if type(opts.thenTexts) == "table" then TextAudio.queueTexts(opts.thenTexts) end
        if opts.report then triggerServerEvent("sr5:audioDone", resourceRoot, token, id) end
    end)
    -- Linea perdida (dropIfBusy): la cola del servidor no tiene que esperarla.
    if not accepted and opts.report then triggerServerEvent("sr5:audioDone", resourceRoot, token, id) end
end)

addEvent("sr5:task", true)
addEventHandler("sr5:task", resourceRoot, function(token, el, taskName, args)
    if not isCurrent(token) then return end
    Actors.dispatch(el, taskName, args)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("sr5:clientReady", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    Sw5Client.reset()
end)
