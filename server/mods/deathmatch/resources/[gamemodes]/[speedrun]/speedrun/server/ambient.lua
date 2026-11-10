-- Ambiente por copia (servidor): trafico y peatones propios en la dimension de cada copia.
-- El cliente del jugador propone candidatos de GTA (client/ambient.lua); aca se validan y se
-- crean en su dimension con el jugador como syncer. Tope: 8 autos y 12 peatones por copia;
-- lo que queda a mas de 220 m se borra.
-- Un auto de ambiente con un jugador adentro (lo robo o subio) pasa a "adoptado": sale de la
-- lista de ambiente (libera su lugar del tope), el mantenimiento y sr:ambientDrop no lo tocan, y
-- se borra recien con la copia (stopCopy).
-- Ciclo (lo llama server/instances.lua): startCopy al crear la copia, stopCopy al reiniciarla o
-- terminarla. main.lua define Ambient.canRun y llama a Ambient.activateAll en la largada.
-- Log: SR|ambient|dim=<dim>|vehicles=<n>|peds=<n> cada 15 s por copia en curso, y
--      SR|ambient|dim=<dim>|cleanup|<restantes> al limpiar la copia.
Ambient = {}

local L = AmbientLogic
local LOG_EVERY_MS = 15000
local MAINTENANCE_MS = 2000
local MIN_PROPOSAL_GAP_MS = 250
local DEAD_REMOVE_MS = 15000
local DIAG_WINDOW_MS = 10000
local DIAG_MAX_PER_WINDOW = 4
local DIAG_MAX_LEN = 300
local MAX_DROP_ITEMS = 20
-- Como native-vehicle-traffic: se crea bajo el mapa, se pasa a la dimension de la copia y
-- recien entonces se mueve al lugar real (nadie del lobby lo ve en la dimension 0).
local STAGING_X, STAGING_Y, STAGING_Z = 0, 0, -1000

-- [player] = { dim, stage, running, vehicles = { { veh, drv, deadSince } }, peds = { { ped, deadSince } },
--              adopted = { { veh, drv } }, logTimer, lastProposal }
local copies = {}
local lastDim = {}  -- [player] = dimension de la ultima copia (para el diagnostico del cliente)
local diagWindow = {} -- [player] = { start, count }: tope de mensajes de diagnostico
local maintenanceTimer = nil

-- main.lua lo reemplaza: true si la copia del jugador esta en curso (ronda "running", jugador activo).
Ambient.canRun = function() return false end

local function srLog(...) Instances.log(...) end
local function now() return getTickCount() end

local function own(el, player, dim)
    setElementDimension(el, dim)
    setElementInterior(el, 0)
    setElementSyncer(el, player, true, true)
end

local function destroySafe(el)
    if isElement(el) then destroyElement(el) end
end

local function liveCounts(copy)
    return #copy.vehicles, #copy.peds
end

local function isWreck(veh, drv)
    return isPedDead(drv) or isVehicleBlown(veh) or getElementHealth(veh) <= 0
end

local function hasPlayerInside(veh)
    return isElement(veh) and L.hasPlayerOccupant(getVehicleOccupants(veh), getElementType)
end

-- El auto ya no es ambiente: se guarda solo para borrarlo con la copia.
local function adopt(copy, e)
    copy.adopted[#copy.adopted + 1] = { e[1], e[2] }
end

-- Pasa a adoptados los autos con un jugador adentro (antes de cualquier borrado).
local function adoptTaken(copy)
    for i = #copy.vehicles, 1, -1 do
        local e = copy.vehicles[i]
        if hasPlayerInside(e[1]) then
            adopt(copy, e)
            table.remove(copy.vehicles, i)
        end
    end
end

-- Saca lo destruido, lo muerto hace rato y lo que quedo lejos del jugador.
local function maintain(player, copy)
    local t = now()
    adoptTaken(copy)
    for i = #copy.vehicles, 1, -1 do
        local e = copy.vehicles[i]
        local veh, drv = e[1], e[2]
        local remove = not (isElement(veh) and isElement(drv))
        if not remove and isWreck(veh, drv) then
            e[3] = e[3] or t
            remove = t - e[3] >= DEAD_REMOVE_MS
        end
        if remove then
            if hasPlayerInside(veh) then adopt(copy, e) else destroySafe(drv); destroySafe(veh) end
            table.remove(copy.vehicles, i)
        end
    end
    for i = #copy.peds, 1, -1 do
        local e = copy.peds[i]
        local remove = not isElement(e[1])
        if not remove and isPedDead(e[1]) then
            e[2] = e[2] or t
            remove = t - e[2] >= DEAD_REMOVE_MS
        end
        if remove then
            destroySafe(e[1])
            table.remove(copy.peds, i)
        end
    end
    if not isElement(player) then return end
    local px, py, pz = getElementPosition(player)
    local function despawn(list, elementOf, destroyEntry)
        local entries = {}
        for i, e in ipairs(list) do
            local x, y, z = getElementPosition(elementOf(e))
            entries[i] = { x = x, y = y, z = z }
        end
        for _, i in ipairs(L.selectDespawn(entries, px, py, pz, L.DESPAWN_RADIUS)) do
            destroyEntry(list[i])
            table.remove(list, i)
        end
    end
    despawn(copy.vehicles, function(e) return e[1] end, function(e)
        if hasPlayerInside(e[1]) then adopt(copy, e) else destroySafe(e[2]); destroySafe(e[1]) end
    end)
    despawn(copy.peds, function(e) return e[1] end, function(e) destroySafe(e[1]) end)
end

local function logCounts(copy)
    local nv, np = liveCounts(copy)
    srLog("ambient", "dim=" .. copy.dim, "vehicles=" .. nv, "peds=" .. np)
end

local function anyRunning()
    for _, copy in pairs(copies) do
        if copy.running then return true end
    end
    return false
end

local function stopTimerIfIdle()
    if maintenanceTimer and not anyRunning() then
        if isTimer(maintenanceTimer) then killTimer(maintenanceTimer) end
        maintenanceTimer = nil
    end
end

local function onMaintenance()
    for player, copy in pairs(copies) do
        if copy.running then maintain(player, copy) end
    end
    stopTimerIfIdle()
end

---------------------------------------------------------------------------
-- Ciclo de la copia
---------------------------------------------------------------------------
-- Borra el ambiente de la copia, registra lo que quedo y avisa al cliente. No hace nada sin copia.
function Ambient.stopCopy(player)
    local copy = copies[player]
    if not copy then return end
    copies[player] = nil
    if copy.logTimer and isTimer(copy.logTimer) then killTimer(copy.logTimer) end
    copy.logTimer = nil
    local tracked = {}
    for _, e in ipairs(copy.vehicles) do
        tracked[#tracked + 1] = e[2]
        tracked[#tracked + 1] = e[1]
    end
    for _, e in ipairs(copy.peds) do tracked[#tracked + 1] = e[1] end
    for _, e in ipairs(copy.adopted) do
        tracked[#tracked + 1] = e[2]
        tracked[#tracked + 1] = e[1]
    end
    for _, el in ipairs(tracked) do destroySafe(el) end
    local remaining = 0
    for _, el in ipairs(tracked) do
        if isElement(el) then remaining = remaining + 1 end
    end
    srLog("ambient", "dim=" .. copy.dim, "cleanup", remaining)
    if isElement(player) then triggerClientEvent(player, "sr:ambientStop", resourceRoot) end
    stopTimerIfIdle()
end

-- La copia ya esta en curso: el cliente empieza a pedir candidatos.
function Ambient.activate(player)
    local copy = copies[player]
    if not copy or copy.running or not isElement(player) then return false end
    copy.running = true
    -- Timer propio de 15 s por copia: una linea SR|ambient exacta cada 15 s.
    copy.logTimer = setTimer(function()
        if copies[player] ~= copy then return end
        maintain(player, copy)
        logCounts(copy)
    end, LOG_EVERY_MS, 0)
    triggerClientEvent(player, "sr:ambientRun", resourceRoot, copy.dim)
    if not maintenanceTimer then maintenanceTimer = setTimer(onMaintenance, MAINTENANCE_MS, 0) end
    return true
end

-- Copia nueva (o reiniciada): el cliente carga la poblacion de la etapa de la mision.
function Ambient.startCopy(player, dim, stage)
    if not isElement(player) then return false end
    Ambient.stopCopy(player)
    if stage ~= nil and not PopulationStages.has(stage) then
        outputDebugString(("speedrun: populationStage desconocida '%s'; se usa el bootstrap"):format(tostring(stage)), 2)
        stage = nil
    end
    copies[player] = { dim = dim, stage = stage, running = false, vehicles = {}, peds = {}, adopted = {}, lastProposal = 0 }
    lastDim[player] = dim
    triggerClientEvent(player, "sr:ambientLoad", resourceRoot, dim, stage)
    if Ambient.canRun(player) then Ambient.activate(player) end
    return true
end

-- El cliente termino de cargar despues de que su copia arranco (sr:clientReady): se le vuelve
-- a mandar la etapa y, si la copia ya esta en curso, la orden de pedir candidatos.
function Ambient.resend(player)
    local copy = copies[player]
    if not copy or not isElement(player) then return false end
    triggerClientEvent(player, "sr:ambientLoad", resourceRoot, copy.dim, copy.stage)
    if copy.running then triggerClientEvent(player, "sr:ambientRun", resourceRoot, copy.dim) end
    return true
end

-- Largada: se activan las copias de los jugadores que siguen jugando.
function Ambient.activateAll()
    for player in pairs(copies) do
        if Ambient.canRun(player) then Ambient.activate(player) end
    end
end

---------------------------------------------------------------------------
-- Propuestas del cliente (siempre `client`, nunca un jugador pasado)
---------------------------------------------------------------------------
local function createVehicleEntry(player, copy, v)
    local veh = createVehicle(v.model, STAGING_X, STAGING_Y, STAGING_Z, 0, 0, v.rotation)
    if not veh then return nil end
    own(veh, player, copy.dim)
    local drv = createPed(v.driverModel, STAGING_X, STAGING_Y, STAGING_Z + 1.0, v.rotation)
    if not drv then
        destroyElement(veh)
        return nil
    end
    own(drv, player, copy.dim)
    warpPedIntoVehicle(drv, veh, 0)
    if getPedOccupiedVehicle(drv) ~= veh or getPedOccupiedVehicleSeat(drv) ~= 0 then
        destroyElement(drv); destroyElement(veh)
        return nil
    end
    setElementPosition(veh, v.x, v.y, v.z + 0.5)
    copy.vehicles[#copy.vehicles + 1] = { veh, drv }
    return { veh, drv, v.speed }
end

local function createPedEntry(player, copy, p)
    local ped = createPed(p.model, STAGING_X, STAGING_Y, STAGING_Z, p.heading)
    if not ped then return nil end
    own(ped, player, copy.dim)
    setElementPosition(ped, p.x, p.y, p.z)
    copy.peds[#copy.peds + 1] = { ped }
    return { ped, p.direction }
end

addEvent("sr:ambientPropose", true)
addEventHandler("sr:ambientPropose", resourceRoot, function(vehicleList, pedList)
    local player = client
    if not isElement(player) then return end
    local copy = copies[player]
    if not copy or not copy.running then return end
    if not Ambient.canRun(player) or not Instances.isAccepting(player) then return end
    if getElementDimension(player) ~= copy.dim or getElementInterior(player) ~= 0 or isPedDead(player) then return end
    local t = now()
    if t - copy.lastProposal < MIN_PROPOSAL_GAP_MS then return end
    copy.lastProposal = t

    maintain(player, copy)
    local px, py, pz = getElementPosition(player)
    local occupied = {}
    local function addPoint(el)
        local x, y = getElementPosition(el)
        occupied[#occupied + 1] = { x = x, y = y }
    end
    for _, e in ipairs(copy.vehicles) do addPoint(e[1]) end
    for _, e in ipairs(copy.peds) do addPoint(e[1]) end

    local nv, np = liveCounts(copy)
    local vAccepted = L.acceptBatch(vehicleList, L.normalizeVehicle, nv, L.MAX_VEHICLES, occupied, px, py, pz)
    local pAccepted = L.acceptBatch(pedList, L.normalizePed, np, L.MAX_PEDS, occupied, px, py, pz)

    local createdVehicles, createdPeds = {}, {}
    for _, v in ipairs(vAccepted) do
        local c = createVehicleEntry(player, copy, v)
        if c then createdVehicles[#createdVehicles + 1] = c end
    end
    for _, p in ipairs(pAccepted) do
        local c = createPedEntry(player, copy, p)
        if c then createdPeds[#createdPeds + 1] = c end
    end
    if #createdVehicles > 0 or #createdPeds > 0 then
        triggerClientEvent(player, "sr:ambientCreated", resourceRoot, createdVehicles, createdPeds)
    end
end)

-- El cliente no pudo darle la tarea a un NPC (no quedo listo o rechazo la tarea dos veces):
-- se borra para liberar su lugar. Solo elementos de la copia de quien lo pide.
addEvent("sr:ambientDrop", true)
addEventHandler("sr:ambientDrop", resourceRoot, function(list)
    local player = client
    if not isElement(player) or type(list) ~= "table" then return end
    local copy = copies[player]
    if not copy then return end
    adoptTaken(copy) -- un auto con un jugador adentro ya no es ambiente: no se borra
    local wanted = {}
    for i = 1, math.min(#list, MAX_DROP_ITEMS) do
        if isElement(list[i]) then wanted[list[i]] = true end
    end
    for i = #copy.vehicles, 1, -1 do
        local e = copy.vehicles[i]
        if (wanted[e[1]] or wanted[e[2]]) and not hasPlayerInside(e[1]) then
            destroySafe(e[2]); destroySafe(e[1])
            table.remove(copy.vehicles, i)
        end
    end
    for i = #copy.peds, 1, -1 do
        local e = copy.peds[i]
        if wanted[e[1]] then
            destroySafe(e[1])
            table.remove(copy.peds, i)
        end
    end
end)

-- Diagnostico del cliente (motivos de candidatos fallidos, preparacion, etapa cargada).
addEvent("sr:ambientDiag", true)
addEventHandler("sr:ambientDiag", resourceRoot, function(text)
    local player = client
    if not isElement(player) or type(text) ~= "string" then return end
    local dim = lastDim[player]
    if not dim then return end
    local t = now()
    local w = diagWindow[player]
    if not w or t - w.start >= DIAG_WINDOW_MS then
        w = { start = t, count = 0 }
        diagWindow[player] = w
    end
    if w.count >= DIAG_MAX_PER_WINDOW then return end
    w.count = w.count + 1
    text = text:sub(1, DIAG_MAX_LEN):gsub("[|%c]", "/")
    srLog("ambient_diag", "dim=" .. dim, text)
end)

-- Un jugador sube a un auto de ambiente de su copia: se adopta en el acto (no espera al
-- mantenimiento de 2 s).
addEventHandler("onVehicleEnter", root, function(enterer)
    if not isElement(enterer) or getElementType(enterer) ~= "player" then return end
    local copy = copies[enterer]
    if not copy then return end
    for i = #copy.vehicles, 1, -1 do
        local e = copy.vehicles[i]
        if e[1] == source then
            adopt(copy, e)
            table.remove(copy.vehicles, i)
            return
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    lastDim[source] = nil
    diagWindow[source] = nil
end)
