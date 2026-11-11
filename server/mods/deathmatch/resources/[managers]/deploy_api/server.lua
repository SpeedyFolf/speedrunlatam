-- deploy_api
-- Funciones para el agente de deploy. Se llaman por el HTTP interno (22007)
-- con las funciones exportadas como http="true", por lo que trabajan con
-- nombres de resource (string) y devuelven valores serializables.

local function collectStates()
    local out = {}
    for _, res in ipairs(getResources()) do
        out[getResourceName(res)] = getResourceState(res)
    end
    return out
end

-- Devuelve un JSON string con el estado de todos los resources.
function resourceStates()
    return toJSON(collectStates())
end

-- Devuelve el estado de un resource por nombre ("missing" si no existe).
function stateOf(name)
    local res = getResourceFromName(name)
    if not res then
        return "missing"
    end
    return getResourceState(res)
end

-- Arranca un resource por nombre. Devuelve true si quedo corriendo.
function startByName(name)
    local res = getResourceFromName(name)
    if not res then
        return false
    end
    if getResourceState(res) == "running" then
        return true
    end
    return startResource(res)
end
