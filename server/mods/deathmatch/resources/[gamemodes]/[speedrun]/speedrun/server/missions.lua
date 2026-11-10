-- Registro de misiones. La base no sabe nada de ninguna mision en particular:
-- cada resource de mision se registra con exports.speedrun:registerMission(def).
Missions = {}

local registered = {}      -- [resource] = def
local lastRegistered = nil -- resource registrado mas recientemente

-- Lo asigna main.lua: se llama despues de cada registro valido.
Missions.onRegistered = nil

local function isNumber(v) return type(v) == "number" end

function Missions.validate(def)
    if type(def) ~= "table" then return false, "def no es una tabla" end
    if type(def.id) ~= "string" or def.id == "" then return false, "id invalido" end
    if type(def.title) ~= "string" or def.title == "" then return false, "title invalido" end
    if def.timeLimitMs ~= nil and (not isNumber(def.timeLimitMs) or def.timeLimitMs <= 0) then
        return false, "timeLimitMs invalido"
    end
    if def.extraAfterFirstMs ~= nil and (not isNumber(def.extraAfterFirstMs) or def.extraAfterFirstMs < 0) then
        return false, "extraAfterFirstMs invalido"
    end
    -- test = true: mision de prueba, fuera de las votaciones y de las elecciones al azar (vote.lua).
    if def.test ~= nil and type(def.test) ~= "boolean" then return false, "test invalido" end
    local ps = def.playerState
    if type(ps) ~= "table" then return false, "playerState falta" end
    if not (isNumber(ps.x) and isNumber(ps.y) and isNumber(ps.z)) then
        return false, "playerState sin x/y/z"
    end
    if ps.stats ~= nil and type(ps.stats) ~= "table" then return false, "playerState.stats invalido" end
    if ps.weapons ~= nil and type(ps.weapons) ~= "table" then return false, "playerState.weapons invalido" end
    if ps.money ~= nil and (not isNumber(ps.money) or ps.money < 0) then return false, "playerState.money invalido" end
    return true
end

-- Export de servidor. El registro queda atado al resource que llama (sourceResource).
function registerMission(def)
    local res = sourceResource
    if not res or res == getThisResource() then return false end
    local ok, err = Missions.validate(def)
    if not ok then
        outputDebugString(("speedrun: registro rechazado de %s: %s"):format(getResourceName(res), err), 2)
        return false
    end
    registered[res] = def
    lastRegistered = res
    outputServerLog(("speedrun: mision '%s' registrada por %s"):format(def.id, getResourceName(res)))
    if Missions.onRegistered then Missions.onRegistered(res, def) end
    return true
end

function Missions.get(res)
    if not res then return nil end
    return registered[res]
end

-- Mision registrada por id (el id publico que usa el gamemode y sr_records).
function Missions.getById(missionId)
    if type(missionId) ~= "string" then return nil end
    for _, def in pairs(registered) do
        if def.id == missionId then return def end
    end
    return nil
end

function Missions.unregister(res)
    registered[res] = nil
    if lastRegistered == res then lastRegistered = nil end
end

-- Mision "cargada": la del mapa actual si esta registrada; si no, la ultima registrada.
function Missions.getCurrent(preferredResource)
    if preferredResource and registered[preferredResource] then
        return preferredResource, registered[preferredResource]
    end
    if lastRegistered and registered[lastRegistered] then
        return lastRegistered, registered[lastRegistered]
    end
    return nil, nil
end
