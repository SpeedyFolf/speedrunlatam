-- Copias de "Sweet's Girl" (servidor): una por jugador, en la dimension que da la base.
-- inst = { player, dim, token, stage, elements = {}, ... }. Exports: srCreateInstance, srInstanceGo y
-- srDestroyInstance (solo los acepta si los llama el resource speedrun).
-- Eventos remotos (cliente -> servidor), todos validados con `client` == inst.player y el token:
--   sr5:clientReady()                -> el cliente cargo: se le mandan los eventos en cola
--   sr5:audioDone(token, seqId)      -> pista "audio terminado": "phoneCall" -> Stages.onCallHint;
--                                       otra -> Stages.onAudioHint (solo libera la cola de dialogo)
--   sr5:clientLog(token, kind, text) -> linea SR5| en el log (lista cerrada de tipos, con tope)
--   sr5:carBase(token, veh, value)   -> base del modelo del auto que usa el jugador (solo para la
--                                       altura de SET_CAR_COORDINATES en T0): Stages.onCarBase
-- Ninguno llama a reportCompleted ni cambia inst.stage (Task 9, Step 5; Task 10).
Instance = {}

local STAGING_X, STAGING_Y, STAGING_Z = 0, 0, -1000 -- se crea bajo el mapa y se pasa a la dimension
local BLIP_DISTANCE = 16383
local CLEANUP_TYPES = { "ped", "vehicle", "blip", "marker", "pickup", "colshape", "object" }
local LOG_KINDS = {
    text_missing = true, text_block_missing = true, audio_missing = true, audio_dropped = true,
    prep = true, ready_timeout = true, task_refused = true, task = true, chase = true, damage = true,
}
local LOG_WINDOW_MS, LOG_MAX_PER_WINDOW, LOG_MAX_LEN = 10000, 20, 200

local instances = {}   -- [player] = inst
local readyClients = {} -- [player] = true: su cliente ya tiene los handlers de la mision
local logWindow = {}   -- [player] = { start, count }

---------------------------------------------------------------------------
-- Log y base
---------------------------------------------------------------------------
local function clean(v)
    return (tostring(v):gsub("|", "/"):gsub("[%c]", " "))
end

function Instance.log(...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = clean(parts[i]) end
    outputServerLog("SR5|" .. table.concat(parts, "|"))
end
local log = Instance.log

local function getBase()
    local base = getResourceFromName("speedrun")
    if base and getResourceState(base) == "running" then return base end
    return nil
end

local function isFromBase()
    local base = getResourceFromName("speedrun")
    return base ~= false and base ~= nil and sourceResource == base
end

-- Solo lo llama Stages.complete, desde el tick del servidor (nunca desde un evento remoto).
function Instance.reportCompleted(inst)
    local base = getBase()
    if not base then return false end
    local ok, result = pcall(call, base, "reportCompleted", inst.player, inst.token)
    return ok and result == true
end

function Instance.reportFailed(inst, reasonKey)
    local base = getBase()
    if not base then return false end
    local ok, result = pcall(call, base, "reportFailed", inst.player, inst.token, reasonKey)
    return ok and result == true
end

---------------------------------------------------------------------------
-- Envio al cliente del dueño (con cola hasta que su cliente cargue)
---------------------------------------------------------------------------
function Instance.send(inst, eventName, ...)
    if inst.destroyed then return end
    if readyClients[inst.player] then
        triggerClientEvent(inst.player, eventName, resourceRoot, inst.token, ...)
    else
        inst.queue[#inst.queue + 1] = { name = eventName, n = select("#", ...), args = { ... } }
    end
end

local function flushQueue(inst)
    local queue = inst.queue
    inst.queue = {}
    for _, item in ipairs(queue) do
        triggerClientEvent(inst.player, item.name, resourceRoot, inst.token, unpack(item.args, 1, item.n))
    end
end

---------------------------------------------------------------------------
-- Elementos de la copia: todos en su dimension, el jugador como syncer
---------------------------------------------------------------------------
local function track(inst, el)
    if el then inst.elements[#inst.elements + 1] = el end
    return el or nil
end

local function placeInCopy(inst, el, x, y, z)
    setElementDimension(el, inst.dim)
    setElementInterior(el, 0)
    setElementPosition(el, x, y, z)
end

function Instance.createPed(inst, model, x, y, z, rot)
    local ped = createPed(model, STAGING_X, STAGING_Y, STAGING_Z, rot or 0)
    if not ped then return nil end
    track(inst, ped)
    placeInCopy(inst, ped, x, y, z)
    setElementSyncer(ped, inst.player, true, true)
    return ped
end

function Instance.createVehicle(inst, model, x, y, z, rot)
    local veh = createVehicle(model, STAGING_X, STAGING_Y, STAGING_Z, 0, 0, rot or 0)
    if not veh then return nil end
    track(inst, veh)
    placeInCopy(inst, veh, x, y, z)
    setElementRotation(veh, 0, 0, rot or 0)
    setElementSyncer(veh, inst.player, true, true)
    return veh
end

function Instance.createPickup(inst, x, y, z, weapon, ammo)
    local pickup = createPickup(STAGING_X, STAGING_Y, STAGING_Z, 2, weapon, 30000, ammo)
    if not pickup then return nil end
    track(inst, pickup)
    placeInCopy(inst, pickup, x, y, z)
    return pickup
end

-- Blips y marcadores: visibles solo para el dueño (los espectadores tambien estan en la dimension).
function Instance.createBlip(inst, x, y, z, icon, color)
    local blip = createBlip(x, y, z, icon, 2, color[1], color[2], color[3], color[4], 0, BLIP_DISTANCE, inst.player)
    if not blip then return nil end
    setElementDimension(blip, inst.dim)
    return track(inst, blip)
end

function Instance.createBlipFor(inst, el, color)
    local blip = createBlipAttachedTo(el, 0, 2, color[1], color[2], color[3], color[4], 0, BLIP_DISTANCE, inst.player)
    if not blip then return nil end
    setElementDimension(blip, inst.dim)
    return track(inst, blip)
end

function Instance.createMarker(inst, x, y, z, markerType, size, color)
    local marker = createMarker(x, y, z, markerType, size, color[1], color[2], color[3], color[4], inst.player)
    if not marker then return nil end
    setElementDimension(marker, inst.dim)
    setElementInterior(marker, 0)
    return track(inst, marker)
end

-- Flecha 3D de un blip de personaje (ADD_BLIP_FOR_CHAR): marcador "arrow" solo para el dueño,
-- en la dimension de la copia, pegado encima del ped. Se destruye junto con su blip.
function Instance.createArrowFor(inst, el, color)
    local A = SW5.CHAR_ARROW
    if not isElement(el) then return nil end
    local x, y, z = getElementPosition(el)
    local marker = Instance.createMarker(inst, x, y, z + A.zOffset, "arrow", A.size, color)
    if not marker then return nil end
    if not attachElements(marker, el, 0, 0, A.zOffset) then log("error", "arrow_attach", inst.nick) end
    return marker
end

function Instance.destroyEl(inst, el)
    if el and isElement(el) then destroyElement(el) end
end

-- CLEAR_AREA_OF_CARS: autos de ambiente de la copia (los crea la base, en su dimension) dentro
-- de la caja, con sus ocupantes que no son jugadores. Los de la mision y `keep` no se tocan.
-- Devuelve cuantos se borraron. La base saca de su lista lo que ya no existe.
function Instance.clearAmbientCars(inst, inBox, keep)
    local base = getResourceFromName("speedrun")
    if not base then return 0 end
    local root = getResourceRootElement(base)
    if not root then return 0 end
    local n = 0
    for _, veh in ipairs(getElementsByType("vehicle", root)) do
        if veh ~= keep and getElementDimension(veh) == inst.dim then
            local x, y, z = getElementPosition(veh)
            if inBox(x, y, z) then
                for _, occupant in pairs(getVehicleOccupants(veh) or {}) do
                    if isElement(occupant) and getElementType(occupant) == "ped" then destroyElement(occupant) end
                end
                destroyElement(veh)
                n = n + 1
            end
        end
    end
    return n
end

---------------------------------------------------------------------------
-- Ciclo de la copia
---------------------------------------------------------------------------
local function countRemaining(dim)
    local n = 0
    for _, elementType in ipairs(CLEANUP_TYPES) do
        for _, el in ipairs(getElementsByType(elementType, resourceRoot)) do
            if getElementDimension(el) == dim then n = n + 1 end
        end
    end
    return n
end

local function destroyFor(player, why)
    local inst = instances[player]
    if not inst then return end
    instances[player] = nil
    inst.ended = true
    if inst.timer and isTimer(inst.timer) then killTimer(inst.timer) end
    inst.timer = nil
    for _, el in ipairs(inst.elements) do
        if isElement(el) then destroyElement(el) end
    end
    inst.elements = {}
    if isElement(player) and readyClients[player] then
        triggerClientEvent(player, "sr5:end", resourceRoot, inst.token)
    end
    inst.destroyed = true
    log("cleanup", countRemaining(inst.dim), inst.nick, "token=" .. tostring(inst.token), "why=" .. tostring(why))
end

function Instance.get(player)
    return instances[player]
end

function srCreateInstance(player, dim, token)
    if not isFromBase() then return false end
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if type(dim) ~= "number" or token == nil then return false end
    destroyFor(player, "replaced")
    local inst = {
        player = player, dim = dim, token = token, stage = nil,
        elements = {}, queue = {}, nick = getPlayerName(player), createdAt = getTickCount(),
    }
    instances[player] = inst
    local ok, result = pcall(Stages.setup, inst)
    if not ok or result ~= true then
        log("error", "create_failed", inst.nick, tostring(result))
        destroyFor(player, "create_failed")
        return false
    end
    inst.timer = setTimer(function() Stages.tick(inst) end, Stages.TICK_MS, 0)
    log("create", inst.nick, "dim=" .. dim, "token=" .. tostring(token))
    return true
end

function srDestroyInstance(player, token)
    if not isFromBase() then return false end
    local inst = instances[player]
    if not inst or inst.token ~= token then return false end
    destroyFor(player, "base")
    return true
end

-- Hook de la base: la copia empieza a correr (largada o copia recreada con la ronda en curso).
-- Solo desde speedrun y con el token actual; la largada ocurre una vez por copia.
function srInstanceGo(player, token, goTick)
    if not isFromBase() then return false end
    local inst = instances[player]
    if not inst or inst.ended or inst.token ~= token then return false end
    return Stages.onGo(inst, getTickCount(), "hook") == true
end

addEventHandler("onPlayerQuit", root, function()
    destroyFor(source, "quit")
    readyClients[source] = nil
    logWindow[source] = nil
end)

---------------------------------------------------------------------------
-- Eventos remotos: solo pistas. Siempre `client`, nunca un jugador pasado como argumento.
---------------------------------------------------------------------------
local function validInst(player, token)
    if not isElement(player) then return nil end
    local inst = instances[player]
    if not inst or inst.ended or type(token) ~= "number" or token ~= inst.token then return nil end
    return inst
end

addEvent("sr5:clientReady", true)
addEventHandler("sr5:clientReady", resourceRoot, function()
    local player = client
    if not isElement(player) then return end
    readyClients[player] = true
    local inst = instances[player]
    if inst and not inst.destroyed then flushQueue(inst) end
end)

addEvent("sr5:audioDone", true)
addEventHandler("sr5:audioDone", resourceRoot, function(token, seqId)
    local inst = validInst(client, token)
    if not inst then return end
    if type(seqId) ~= "string" then return end
    if seqId == "phoneCall" then
        Stages.onCallHint(inst)
    else
        Stages.onAudioHint(inst, seqId)
    end
end)

addEvent("sr5:carBase", true)
addEventHandler("sr5:carBase", resourceRoot, function(token, veh, value)
    local player = client
    local inst = validInst(player, token)
    if not inst or type(value) ~= "number" then return end
    if not isElement(veh) or getElementType(veh) ~= "vehicle" or getPedOccupiedVehicle(player) ~= veh then return end
    Stages.onCarBase(inst, veh, value)
end)

addEvent("sr5:clientLog", true)
addEventHandler("sr5:clientLog", resourceRoot, function(token, kind, detail)
    local player = client
    local inst = validInst(player, token)
    if not inst or type(kind) ~= "string" or not LOG_KINDS[kind] then return end
    local now = getTickCount()
    local w = logWindow[player]
    if not w or now - w.start > LOG_WINDOW_MS then
        w = { start = now, count = 0 }
        logWindow[player] = w
    end
    w.count = w.count + 1
    if w.count > LOG_MAX_PER_WINDOW then return end
    -- Primero se corta (el texto del cliente puede ser enorme) y despues se limpia.
    local text = clean(tostring(detail or ""):sub(1, LOG_MAX_LEN))
    log(kind, text, inst.nick)
end)

---------------------------------------------------------------------------
-- Registro en la base (como sr-dummy)
---------------------------------------------------------------------------
local DEF = {
    id = SW5.MISSION_ID,
    title = SW5.TITLE,
    populationStage = SW5.POPULATION_STAGE,
    playerState = SW5.PLAYER_STATE,
}

local function register()
    local base = getBase()
    if base then call(base, "registerMission", DEF) end
end

addEventHandler("onResourceStart", resourceRoot, register)

-- Si la base arranca despues que esta mision, se vuelve a registrar.
addEventHandler("onResourceStart", root, function(startedResource)
    if getResourceName(startedResource) == "speedrun" then
        setTimer(register, 50, 1)
    end
end)
