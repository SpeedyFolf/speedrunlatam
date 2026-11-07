-- sr-dummy: mision de prueba del gamemode speedrun.
-- Objetivo: caminar desde el inicio hasta el marcador. La muerte la maneja la base.

local START = { x = 2495.0, y = -1680.0, z = 13.5, rot = 0 }
local GOAL = { x = 2510.0, y = -1660.0, z = 13.0 }
local GOAL_RADIUS = 3.0

local DEF = {
    id = "dummy",
    title = "Prueba: caminar al punto",
    -- Mision de prueba: no entra en votaciones ni en elecciones al azar. Se carga a mano con
    -- /changemode speedrun sr-dummy (y /srtest). Lo mismo dice speedrun_test en meta.xml.
    test = true,
    -- timeLimitMs / extraAfterFirstMs omitidos: se usan los valores por defecto de la base
    populationStage = "postCleaningTheHood", -- poblacion de peatones de esa etapa (Task 7)
    playerState = {
        skin = 0,
        x = START.x, y = START.y, z = START.z, rot = START.rot,
        interior = 0,
        health = 100, armor = 0, maxHealthStat = 569,
        stats = {},
        weapons = {},
    },
}

local instances = {} -- [player] = { token, dim, marker, blip }

local function isFromBase()
    local base = getResourceFromName("speedrun")
    return base ~= false and base ~= nil and sourceResource == base
end

local function destroyInstanceFor(player)
    local inst = instances[player]
    if not inst then return end
    if isElement(inst.blip) then destroyElement(inst.blip) end
    if isElement(inst.marker) then destroyElement(inst.marker) end
    instances[player] = nil
end

local function onGoalHit(hitElement, matchingDimension)
    if not matchingDimension or getElementType(hitElement) ~= "player" then return end
    local inst = instances[hitElement]
    if not inst or inst.marker ~= source then return end
    if getElementDimension(hitElement) ~= inst.dim then return end
    local px, py, pz = getElementPosition(hitElement)
    if getDistanceBetweenPoints3D(px, py, pz, GOAL.x, GOAL.y, GOAL.z) > GOAL_RADIUS then return end
    local base = getResourceFromName("speedrun")
    if base and getResourceState(base) == "running" then
        call(base, "reportCompleted", hitElement, inst.token)
    end
end

function srCreateInstance(player, dim, token)
    if not isFromBase() then return false end
    if not isElement(player) then return false end
    destroyInstanceFor(player)
    local marker = createMarker(GOAL.x, GOAL.y, GOAL.z, "cylinder", 2.0, 255, 200, 0, 160, player)
    setElementDimension(marker, dim)
    setElementInterior(marker, 0)
    local blip = createBlipAttachedTo(marker, 0, 2, 255, 200, 0, 255, 0, 16383, player)
    setElementDimension(blip, dim)
    addEventHandler("onMarkerHit", marker, onGoalHit, false)
    instances[player] = { token = token, dim = dim, marker = marker, blip = blip }
    outputChatBox("Caminá hasta el marcador amarillo.", player, 255, 200, 0)
    return true
end

function srDestroyInstance(player, token)
    if not isFromBase() then return false end
    local inst = instances[player]
    if not inst or inst.token ~= token then return false end
    destroyInstanceFor(player)
    return true
end

addEventHandler("onPlayerQuit", root, function()
    destroyInstanceFor(source)
end)

local function register()
    local base = getResourceFromName("speedrun")
    if base and getResourceState(base) == "running" then
        call(base, "registerMission", DEF)
    end
end

addEventHandler("onResourceStart", resourceRoot, register)

-- Si la base arranca despues que esta mision, se vuelve a registrar.
addEventHandler("onResourceStart", root, function(startedResource)
    if getResourceName(startedResource) == "speedrun" then
        setTimer(register, 50, 1)
    end
end)
