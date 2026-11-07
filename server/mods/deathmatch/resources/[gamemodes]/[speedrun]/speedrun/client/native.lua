-- Helpers de Neon para el cliente: preparar NPCs para tareas nativas y cargar la poblacion
-- de una etapa de la historia. Exports de cliente: prepareActor y loadPopulationStage.

local leases = {} -- [element] = token de acquireElementStreamingLease (del resource speedrun)

local function onLeasedDestroy()
    local token = leases[source]
    leases[source] = nil
    if token and type(releaseElementStreamingLease) == "function" then
        releaseElementStreamingLease(token)
    end
end

-- Reserva de streaming: el elemento queda cargado mientras exista. true si quedo reservado.
local function lease(el)
    if leases[el] then return true end
    if type(acquireElementStreamingLease) ~= "function" then return false end
    local token = acquireElementStreamingLease(el)
    if not token then return false end
    leases[el] = token
    addEventHandler("onClientElementDestroy", el, onLeasedDestroy, false)
    return true
end

-- Receta validada en la Fase 0 (como native-vehicle-traffic y native-drive-route-test):
--   reserva de streaming del ped (y del auto), actor de mision si se pide y, para un conductor
--   metido con warp, killPedTask(primary 3) y setVehicleLoadCollisionFlag(veh, false).
-- Devuelve ok, problemsText. ok es false solo si falla algo imprescindible (reserva o actor de
-- mision). killPedTask devolvio false en la Fase 0 y aun asi el auto manejo: se informa en el
-- texto ("kill_primary") pero no hace fallar.
function prepareActor(ped, vehicle, missionActor)
    if not isElement(ped) or getElementType(ped) ~= "ped" then return false, "prep=no_ped" end
    if not vehicle then vehicle = nil end -- false o nil: ped a pie
    if vehicle ~= nil and not (isElement(vehicle) and getElementType(vehicle) == "vehicle") then
        return false, "prep=no_vehicle"
    end
    local hard, soft = {}, {}
    if not lease(ped) then hard[#hard + 1] = "lease_ped" end
    if vehicle and not lease(vehicle) then hard[#hard + 1] = "lease_veh" end
    if missionActor then
        if type(setPedMissionActor) ~= "function" or not setPedMissionActor(ped, true) then
            hard[#hard + 1] = "mission_actor"
        end
    end
    if vehicle then
        -- Al meter un conductor con warp, GTA le deja su tarea generica "en el auto"; se quita.
        if type(killPedTask) ~= "function" or not killPedTask(ped, "primary", 3, false) then
            soft[#soft + 1] = "kill_primary"
        end
        if type(setVehicleLoadCollisionFlag) ~= "function" or not setVehicleLoadCollisionFlag(vehicle, false) then
            soft[#soft + 1] = "collision_flag"
        end
    end
    local all = {}
    for _, p in ipairs(hard) do all[#all + 1] = p end
    for _, p in ipairs(soft) do all[#all + 1] = p end
    return #hard == 0, #all == 0 and "prep=ok" or ("prep=" .. table.concat(all, "+"))
end

---------------------------------------------------------------------------
-- Poblacion por etapa (shared/population_stages.lua)
---------------------------------------------------------------------------
local currentStage = nil

-- Vuelve las zonas al estado inicial de main.scm. true si se pudo.
function resetPopulationToBootstrap()
    currentStage = nil
    if type(resetAmbientPedPopulationZonesToBootstrap) ~= "function" then return false end
    return resetAmbientPedPopulationZonesToBootstrap() and true or false
end

-- Bootstrap y despues el estado de cada zona de la etapa, en orden. Si falla una zona,
-- vuelve al bootstrap y devuelve false (y el motivo como segundo valor).
function loadPopulationStage(stageName)
    local zones = PopulationStages.build(stageName)
    if not zones then return false, "unknown_stage" end
    if type(resetAmbientPedPopulationZonesToBootstrap) ~= "function" or type(setAmbientPedPopulationZoneState) ~= "function" then
        return false, "api_missing"
    end
    currentStage = nil
    if not resetAmbientPedPopulationZonesToBootstrap() then return false, "bootstrap_failed" end
    for _, label in ipairs(PopulationStages.sortedLabels(zones)) do
        if not setAmbientPedPopulationZoneState(label, zones[label]) then
            resetAmbientPedPopulationZonesToBootstrap()
            return false, "zone_failed:" .. label
        end
    end
    currentStage = stageName
    return true
end

function getLoadedPopulationStage()
    return currentStage
end

-- Al detenerse el gamemode, la poblacion vuelve a la de main.scm.
addEventHandler("onClientResourceStop", resourceRoot, function()
    if currentStage then resetPopulationToBootstrap() end
end)
