-- Copias de mision por jugador: una dimension propia (1000 + slot) y un token por copia.
-- El token cambia en cada reinicio; las llamadas de la mision con un token viejo se ignoran.
Instances = {}

local DIM_BASE = 1000
local MAX_SLOTS = 32

local slotOwner = {}  -- [slot] = player
local playerSlot = {} -- [player] = slot
local instances = {}  -- [player] = { token, dim, accepting }
local tokenCounter = 0
local mission = { resource = nil, def = nil }

local function srLog(...)
    local parts = { ... }
    for i = 1, #parts do parts[i] = tostring(parts[i]) end
    outputServerLog("SR|" .. table.concat(parts, "|"))
end
Instances.log = srLog

local function newToken()
    tokenCounter = tokenCounter + 1
    return tokenCounter
end

function Instances.setMission(res, def)
    mission.resource = res
    mission.def = def
end

function Instances.getMissionResource()
    return mission.resource
end

-- Llama a un export de la mision solo si su resource esta corriendo.
local function callMission(fnName, ...)
    local res = mission.resource
    if not res or getResourceState(res) ~= "running" then return false end
    local ok, result = pcall(call, res, fnName, ...)
    if not ok then
        outputDebugString(("speedrun: %s fallo en %s: %s"):format(fnName, getResourceName(res), tostring(result)), 1)
        return false
    end
    return result
end

---------------------------------------------------------------------------
-- Dimensiones
---------------------------------------------------------------------------
function allocateDimension(player)
    local slot = playerSlot[player]
    if slot then return DIM_BASE + slot end
    for s = 1, MAX_SLOTS do
        if not slotOwner[s] then
            slotOwner[s] = player
            playerSlot[player] = s
            return DIM_BASE + s
        end
    end
    return nil
end

function freeDimension(player)
    local slot = playerSlot[player]
    if not slot then return end
    slotOwner[slot] = nil
    playerSlot[player] = nil
end

-- Export de servidor: dimension de la copia del jugador, o false si no tiene.
function getPlayerDimension(player)
    local slot = playerSlot[player]
    if not slot then return false end
    return DIM_BASE + slot
end

function Instances.isInstanceDimension(dim)
    return type(dim) == "number" and dim > DIM_BASE and dim <= DIM_BASE + MAX_SLOTS
end

---------------------------------------------------------------------------
-- Ciclo de la copia
---------------------------------------------------------------------------
local function startFailed(player, why)
    freeDimension(player)
    srLog("start_failed", isElement(player) and getPlayerName(player) or "?", why)
    return false
end

-- Aplica el estado y crea la copia. Si algo falla, libera la dimension y devuelve false.
local function createFor(player, dim)
    local def = mission.def
    if not isElement(player) then return startFailed(player, "no_player") end
    if not def then return startFailed(player, "no_mission") end
    local token = newToken()
    if not applyPlayerState(player, def.playerState, dim) then
        return startFailed(player, "spawn_failed")
    end
    instances[player] = { token = token, dim = dim, accepting = true }
    local created = callMission("srCreateInstance", player, dim, token)
    if not created then
        instances[player] = nil
        callMission("srDestroyInstance", player, token) -- por si quedo a medias
        return startFailed(player, "create_failed")
    end
    srLog("start", getPlayerName(player), "dim=" .. dim, "mission=" .. tostring(def.id), "token=" .. token)
    -- Ambiente propio de la copia (server/ambient.lua): poblacion de la etapa, trafico y peatones.
    Ambient.startCopy(player, dim, def.populationStage)
    return true
end

-- Aplica el estado y crea la copia con un token nuevo. Devuelve false si no se pudo.
function Instances.startInstance(player)
    if not isElement(player) then return false end
    local dim = allocateDimension(player)
    if not dim then return startFailed(player, "no_slot") end
    return createFor(player, dim)
end

-- Destruye la copia actual y la vuelve a crear con un token nuevo, en la misma dimension.
-- Devuelve false si no se pudo (la dimension queda libre).
function Instances.restartInstance(player)
    local inst = instances[player]
    if not inst then return Instances.startInstance(player) end
    Ambient.stopCopy(player)
    callMission("srDestroyInstance", player, inst.token)
    instances[player] = nil
    return createFor(player, inst.dim)
end

function Instances.isDimensionInUse(dim)
    if not Instances.isInstanceDimension(dim) then return false end
    return slotOwner[dim - DIM_BASE] ~= nil
end

-- Destruye la copia y libera la dimension. No mueve al jugador.
function Instances.endInstance(player)
    Ambient.stopCopy(player)
    local inst = instances[player]
    if inst then
        instances[player] = nil
        callMission("srDestroyInstance", player, inst.token)
    end
    freeDimension(player)
end

function Instances.has(player)
    return instances[player] ~= nil
end

function Instances.getToken(player)
    local inst = instances[player]
    return inst and inst.token or nil
end

-- true si el token es el de la copia viva del jugador y todavia acepta reportes.
function Instances.isCurrentToken(player, token)
    local inst = instances[player]
    return inst ~= nil and inst.accepting and inst.token == token
end

function Instances.isAccepting(player)
    local inst = instances[player]
    return inst ~= nil and inst.accepting
end

-- Hook opcional de la mision: srInstanceGo(player, token, goTick) cuando su copia empieza a correr
-- (largada de la ronda o copia recreada con la ronda en curso). Si la mision no lo exporta, no se
-- llama (sin avisos de call en el log).
local function missionExports(fnName)
    local res = mission.resource
    if not res or getResourceState(res) ~= "running" then return false end
    local list = getResourceExportedFunctions(res)
    if type(list) ~= "table" then return false end
    for _, name in ipairs(list) do
        if name == fnName then return true end
    end
    return false
end

function Instances.notifyGo(player, goTick)
    local inst = instances[player]
    if not inst or not inst.accepting then return false end
    if not missionExports("srInstanceGo") then return false end
    return callMission("srInstanceGo", player, inst.token, goTick)
end

-- Deja de aceptar reportes de la copia actual (fallo o fin), sin destruirla todavia.
function Instances.suspend(player)
    local inst = instances[player]
    if inst then inst.accepting = false end
end

-- Alias globales con los nombres del brief (no son exports).
startInstance = Instances.startInstance
restartInstance = Instances.restartInstance
endInstance = Instances.endInstance
