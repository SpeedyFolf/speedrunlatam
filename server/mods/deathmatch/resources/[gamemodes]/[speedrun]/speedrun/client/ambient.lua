-- Ambiente por copia (cliente): trafico y peatones propios en la dimension de la copia.
-- El servidor manda:
--   sr:ambientLoad(dim, stage)  al crear la copia: se carga la poblacion de la etapa;
--   sr:ambientRun(dim)          con la copia en curso: cada 2 s se piden candidatos a GTA y, en
--                               cada frame, se actualizan los modelos de peatones de la zona;
--   sr:ambientCreated(v, p)     autos y peatones creados (este cliente es su syncer);
--   sr:ambientStop()            fin de la copia: se deja de pedir y la poblacion vuelve al bootstrap.
-- Sin policia: los peatones se piden con "civilian" (nunca "cop") y se descartan autos y
-- conductores de policia.

local L = AmbientLogic
local PROPOSE_EVERY_MS = 2000
local READY_CHECK_MS = 250
local READY_TIMEOUT_MS = 10000
local DIAG_EVERY_MS = 15000
local VEHICLE_TRIES = 2 -- autos que se proponen como maximo por pedido
local VEHICLE_QUERIES = 4 -- consultas de lugar a GTA por pedido (native-vehicle-traffic reintenta hasta 25)
local PED_TRIES = 3     -- candidatos de peaton por pedido
local TASK_ATTEMPTS = 3 -- intentos de darle la tarea a un NPC antes de devolverlo al servidor
local TASK_RETRY_MS = 500

local state = { dim = nil, running = false, stage = false }
local vehicleFailStreak = 0 -- "no-path" seguidos: despues de unos cuantos se busca en un anillo
local vehicleSession = 0
local vehicles = {} -- { veh, drv }
local peds = {}     -- ped
local pending = {}  -- { ped, veh|nil, speed, direction, since, attempts, notBefore }: esperan la tarea
local timers = {}
local stats = {}    -- [motivo] = cantidad, se manda al servidor cada 15 s

local function killTimerSafe(name)
    if timers[name] and isTimer(timers[name]) then killTimer(timers[name]) end
    timers[name] = nil
end

local function count(reason)
    stats[reason] = (stats[reason] or 0) + 1
end

local function sendDiag(text)
    triggerServerEvent("sr:ambientDiag", resourceRoot, text)
end

-- Modelos distintos entre los peatones vivos: si "no-model" aparece cuando cada modelo cargado
-- ya esta en uso (distintos == vivos), confirma que faltan modelos de zona cargados.
local function pedModelText()
    local seen, distinct, live = {}, 0, 0
    for _, ped in ipairs(peds) do
        if isElement(ped) then
            live = live + 1
            local m = getElementModel(ped)
            if not seen[m] then seen[m] = true; distinct = distinct + 1 end
        end
    end
    return ("ped_models=%d/%d"):format(distinct, live)
end

local function flushStats()
    local keys = {}
    for k in pairs(stats) do keys[#keys + 1] = k end
    if #keys == 0 then return end
    table.sort(keys)
    local parts = { pedModelText() }
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. ":" .. stats[k] end
    stats = {}
    sendDiag(table.concat(parts, ","))
end

local function prune()
    for i = #vehicles, 1, -1 do
        local v = vehicles[i]
        if not (isElement(v[1]) and isElement(v[2])) then table.remove(vehicles, i) end
    end
    for i = #peds, 1, -1 do
        if not isElement(peds[i]) then table.remove(peds, i) end
    end
end

local function occupiedPoints()
    local points = {}
    local function add(el)
        if isElement(el) then
            local x, y = getElementPosition(el)
            points[#points + 1] = { x = x, y = y }
        end
    end
    for _, v in ipairs(vehicles) do add(v[1]) end
    for _, p in ipairs(peds) do add(p) end
    return points
end

local function apiMissing(names)
    for _, name in ipairs(names) do
        if type(_G[name]) ~= "function" then return name end
    end
    return nil
end

local VEHICLE_API = { "getAmbientVehicleModelCandidate", "getAmbientVehicleSpawnCandidate", "getAmbientVehicleOccupantModelCandidate" }
local PED_API = { "getAmbientPedSpawnCandidate", "updateAmbientPedPopulationModels" }

local function vehicleCandidates(x, y, z, room, points)
    local out = {}
    if room <= 0 then return out end
    local missing = apiMissing(VEHICLE_API)
    if missing then count("api_missing:" .. missing) return out end
    local wanted = math.min(room, VEHICLE_TRIES)
    for _ = 1, VEHICLE_QUERIES do
        if #out >= wanted then break end
        local mc, why = getAmbientVehicleModelCandidate()
        if not mc then
            count("veh_model:" .. tostring(why))
        elseif not L.isAllowedVehicle(mc.model) then
            count("veh_model_blocked")
        else
            vehicleSession = vehicleSession + 1
            local ox, oy, oz, ring = L.vehicleSearchOrigin(x, y, z, vehicleFailStreak, vehicleSession)
            local where = ring > 0 and "@ring" or "@exact"
            -- No se actualizan los modelos de peatones en el origen del anillo: si cae en otro tipo de
            -- zona, StreamZoneModels descargaria todos los modelos de peatones cargados.
            local sc, why2 = getAmbientVehicleSpawnCandidate(Vector3(ox, oy, oz), mc.model)
            local occ = sc and getAmbientVehicleOccupantModelCandidate(sc.model or mc.model, 1)
            if sc then
                vehicleFailStreak = 0
                count("veh_ok" .. where)
            elseif why2 == "no-path" then
                vehicleFailStreak = vehicleFailStreak + 1
            end
            if not sc then
                count("veh_spawn:" .. tostring(why2) .. where)
            elseif sc.model and not L.isAllowedVehicle(sc.model) then
                count("veh_model_blocked")
            elseif L.dist3(sc.x, sc.y, sc.z, x, y, z) < L.VEHICLE_MIN_PLAYER_DIST then
                count("veh_near")
            elseif L.dist3(sc.x, sc.y, sc.z, x, y, z) > L.PROPOSE_RADIUS then
                count("veh_far")
            elseif type(occ) ~= "table" or type(occ[1]) ~= "number" then
                count("veh_occupant")
            elseif L.isCopPed(occ[1]) then
                count("veh_cop_driver")
            elseif L.tooClose(points, sc.x, sc.y, L.MIN_SEPARATION) then
                count("veh_close")
            else
                points[#points + 1] = { x = sc.x, y = sc.y }
                out[#out + 1] = {
                    model = sc.model or mc.model, x = sc.x, y = sc.y, z = sc.z,
                    rotation = sc.rotation, speed = sc.cruiseSpeed, driverModel = occ[1],
                }
            end
        end
    end
    return out
end

local function pedCandidates(x, y, z, room, points)
    local out = {}
    if room <= 0 then return out end
    local missing = apiMissing(PED_API)
    if missing then count("api_missing:" .. missing) return out end
    for _ = 1, math.min(room, PED_TRIES) do
        -- Forma del resource oficial native-ped-traffic: origen en numeros, "civilian", sin banda.
        local pc, why = getAmbientPedSpawnCandidate(x, y, z, "civilian", -1)
        if not pc then
            count("ped:" .. tostring(why))
        elseif type(pc.x) ~= "number" or type(pc.y) ~= "number" or type(pc.z) ~= "number" then
            count("ped_no_xyz")
        elseif pc.populationClass ~= nil and pc.populationClass ~= "civilian" then
            count("ped_class:" .. tostring(pc.populationClass))
        elseif L.dist3(pc.x, pc.y, pc.z, x, y, z) < L.PED_MIN_PLAYER_DIST then
            count("ped_near")
        elseif L.tooClose(points, pc.x, pc.y, L.MIN_SEPARATION) then
            count("ped_close")
        else
            points[#points + 1] = { x = pc.x, y = pc.y }
            out[#out + 1] = {
                model = pc.model, x = pc.x, y = pc.y, z = pc.z,
                heading = pc.heading, direction = pc.direction,
            }
        end
    end
    return out
end

local function canPropose()
    return state.running and getElementDimension(localPlayer) == state.dim and
        getElementInterior(localPlayer) == 0 and not isPedDead(localPlayer)
end

-- Cadencia del oficial (native-ped-traffic, onClientPreRender): GTA solo carga un modelo de
-- peaton nuevo cada 300 llamadas de StreamZoneModels, asi que se llama en cada frame.
local function onFrameUpdateModels()
    if not canPropose() then return end
    local x, y, z = getElementPosition(localPlayer)
    updateAmbientPedPopulationModels(x, y, z)
end

local function setFrameUpdates(on)
    if on and not state.frameHandler and type(updateAmbientPedPopulationModels) == "function" then
        state.frameHandler = addEventHandler("onClientPreRender", root, onFrameUpdateModels)
    elseif not on and state.frameHandler then
        removeEventHandler("onClientPreRender", root, onFrameUpdateModels)
        state.frameHandler = nil
    end
end

local function propose()
    if not canPropose() then return end
    local x, y, z = getElementPosition(localPlayer)
    -- Los modelos de peatones de la zona se cargan con cada pedido (GTA los necesita para proponer).
    if type(updateAmbientPedPopulationModels) == "function" then updateAmbientPedPopulationModels(x, y, z) end
    prune()
    local points = occupiedPoints()
    local vList = vehicleCandidates(x, y, z, L.MAX_VEHICLES - #vehicles, points)
    local pList = pedCandidates(x, y, z, L.MAX_PEDS - #peds, points)
    if #vList > 0 or #pList > 0 then
        triggerServerEvent("sr:ambientPropose", resourceRoot, vList, pList)
    end
end

---------------------------------------------------------------------------
-- Tareas: cuando el NPC esta listo (cargado, syncer y listo para tareas nativas)
---------------------------------------------------------------------------
-- Peaton: cargado, este cliente es su syncer y listo para tareas nativas.
-- Conductor: ademas, como native-vehicle-traffic (client.lua 428-430), el auto cargado, este
-- cliente syncer del auto y el ped sentado en ese auto en el asiento 0.
local function isReady(item)
    local ped, veh = item.ped, item.veh
    if not isElementStreamedIn(ped) or not isElementSyncer(ped) then return false end
    if veh then
        if not isElementStreamedIn(veh) or not isElementSyncer(veh) then return false end
        if getPedOccupiedVehicle(ped) ~= veh or getPedOccupiedVehicleSeat(ped) ~= 0 then return false end
    end
    if type(isPedNativeTaskReady) == "function" then return isPedNativeTaskReady(ped) end
    return true
end

-- true si el NPC quedo con su tarea.
local function assign(item)
    local ped, veh = item.ped, item.veh
    local ok, prep
    if veh then
        ok, prep = prepareActor(ped, veh, true)
    else
        ok, prep = prepareActor(ped, nil, false)
    end
    if prep ~= "prep=ok" then count((veh and "veh_" or "ped_") .. prep) end
    if not ok then return false end
    local accepted
    if veh then
        accepted = type(setPedDriveWander) == "function" and setPedDriveWander(ped, veh, item.speed, "stop_for_cars")
    else
        accepted = type(setPedWander) == "function" and setPedWander(ped, "walk", item.direction, true)
    end
    if not accepted then count(veh and "veh_wander_refused" or "ped_wander_refused") end
    return accepted and true or false
end

local function checkPending()
    local now = getTickCount()
    local drops = {}
    local retries = {}
    for i = #pending, 1, -1 do
        local item = pending[i]
        if not isElement(item.ped) or (item.veh and not isElement(item.veh)) then
            table.remove(pending, i)
        elseif now >= item.notBefore and isReady(item) then
            table.remove(pending, i)
            if not assign(item) then
                item.attempts = item.attempts + 1
                if item.attempts < TASK_ATTEMPTS then
                    retries[#retries + 1] = item
                else
                    count(item.veh and "veh_task_dropped" or "ped_task_dropped")
                    drops[#drops + 1] = item.ped
                end
            end
        elseif now - item.since > READY_TIMEOUT_MS then
            table.remove(pending, i)
            count(item.veh and "veh_ready_timeout" or "ped_ready_timeout")
            drops[#drops + 1] = item.ped
        end
    end
    -- Reintento: vuelve a la cola con un plazo nuevo para quedar listo.
    for _, item in ipairs(retries) do
        item.since = now
        item.notBefore = now + TASK_RETRY_MS
        pending[#pending + 1] = item
    end
    -- Sin tarea, el NPC quedaria quieto ocupando lugar del tope: el servidor lo borra.
    if #drops > 0 then triggerServerEvent("sr:ambientDrop", resourceRoot, drops) end
    if #pending == 0 then killTimerSafe("pending") end
end

local function queue(item)
    item.since = getTickCount()
    item.notBefore = 0
    item.attempts = 0
    pending[#pending + 1] = item
    if not timers.pending then timers.pending = setTimer(checkPending, READY_CHECK_MS, 0) end
end

---------------------------------------------------------------------------
-- Eventos del servidor
---------------------------------------------------------------------------
local function stopAmbient()
    setFrameUpdates(false)
    state.running = false
    state.dim = nil
    state.stage = false
    vehicleFailStreak = 0
    killTimerSafe("propose")
    killTimerSafe("diag")
    killTimerSafe("pending")
    vehicles, peds, pending, stats = {}, {}, {}, {}
end

addEvent("sr:ambientLoad", true)
addEvent("sr:ambientRun", true)
addEvent("sr:ambientCreated", true)
addEvent("sr:ambientStop", true)

addEventHandler("sr:ambientLoad", resourceRoot, function(dim, stage)
    -- Reenvio (sr:clientReady) de lo mismo que ya esta cargado: no se reinicia nada.
    if state.dim == dim and state.stage == (stage or "none") then return end
    stopAmbient()
    state.dim = dim
    state.stage = stage or "none"
    if stage == nil then
        resetPopulationToBootstrap()
        sendDiag("stage=none(bootstrap)")
        return
    end
    local ok, why = loadPopulationStage(stage)
    if not ok then state.stage = false end -- un reenvio vuelve a intentar
    sendDiag("stage=" .. tostring(stage) .. ":" .. (ok and "ok" or ("failed:" .. tostring(why))))
end)

addEventHandler("sr:ambientRun", resourceRoot, function(dim)
    if state.running and state.dim == dim then return end -- reenvio
    state.dim = dim
    state.running = true
    setFrameUpdates(true)
    if type(updateAmbientPedPopulationModels) == "function" then
        local x, y, z = getElementPosition(localPlayer)
        updateAmbientPedPopulationModels(x, y, z)
    end
    killTimerSafe("propose")
    killTimerSafe("diag")
    timers.propose = setTimer(propose, PROPOSE_EVERY_MS, 0)
    timers.diag = setTimer(flushStats, DIAG_EVERY_MS, 0)
end)

addEventHandler("sr:ambientCreated", resourceRoot, function(createdVehicles, createdPeds)
    if not state.running then return end
    for _, v in ipairs(type(createdVehicles) == "table" and createdVehicles or {}) do
        local veh, drv, speed = v[1], v[2], v[3]
        if isElement(veh) and isElement(drv) then
            vehicles[#vehicles + 1] = { veh, drv }
            queue({ ped = drv, veh = veh, speed = tonumber(speed) or L.DEFAULT_SPEED })
        end
    end
    for _, p in ipairs(type(createdPeds) == "table" and createdPeds or {}) do
        local ped, direction = p[1], p[2]
        if isElement(ped) then
            peds[#peds + 1] = ped
            queue({ ped = ped, direction = tonumber(direction) or 0 })
        end
    end
end)

addEventHandler("sr:ambientStop", resourceRoot, function()
    if state.running then flushStats() end
    stopAmbient()
    resetPopulationToBootstrap()
    if type(resetAmbientPedPopulationModels) == "function" then resetAmbientPedPopulationModels() end
end)
