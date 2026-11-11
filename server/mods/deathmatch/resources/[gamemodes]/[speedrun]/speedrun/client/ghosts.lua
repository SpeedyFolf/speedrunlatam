-- Fantasmas de otros jugadores (cross-dimension).
--
-- Cada jugador corre en su propia dimension, asi que MTA no puede mostrar los
-- jugadores reales entre si. El server manda la lista de jugadores visibles y
-- aca se dibujan proxies locales (vehiculo o ped) con alpha, dentro de la
-- dimension del jugador local. Son elementos client-side: no chocan ni afectan
-- la fisica de nadie.
SR = SR or {}

local GHOST_ALPHA_DEFAULT = 120
local ghosts = {} -- [id] = { element, kind, ... }
local ghostAlpha = GHOST_ALPHA_DEFAULT

local function lerpAngle(a, b, k)
    local d = (b - a + 180) % 360 - 180
    return a + d * k
end

local function destroyGhost(id)
    local g = ghosts[id]
    if not g then return end
    if isElement(g.driver) then destroyElement(g.driver) end
    if isElement(g.element) then destroyElement(g.element) end
    ghosts[id] = nil
end

local function clearGhosts()
    for id in pairs(ghosts) do destroyGhost(id) end
end

local function createGhostElement(entry, kind)
    local model = tonumber(entry.model) or 0
    local skin = tonumber(entry.skin) or model
    local interior = tonumber(entry.interior) or 0
    local element, driver
    if kind == "ped" then
        -- No se congela (un ped congelado no anima) y va sin animacion: como
        -- las colisiones estan apagadas, en cada frame se le resetea posicion y
        -- velocidad para que no caiga (ver onClientPreRender).
        element = createPed(skin, entry.x, entry.y, entry.z, tonumber(entry.rz) or 0)
    else
        element = createVehicle(model, entry.x, entry.y, entry.z)
        if element then
            -- Conductor fantasma sentado en el vehiculo, para que no quede un
            -- vehiculo vacio flotando.
            driver = createPed(skin, entry.x, entry.y, entry.z, tonumber(entry.rz) or 0)
            if driver then
                warpPedIntoVehicle(driver, element, tonumber(entry.seat) or 0)
                setElementAlpha(driver, ghostAlpha)
                setElementCollisionsEnabled(driver, false)
                setElementDimension(driver, getElementDimension(localPlayer))
                setElementInterior(driver, interior)
            end
            -- Un vehiculo client-side tiene fisica: congelado queda fijo y lo
            -- movemos/rotamos nosotros en cada frame. Solo yaw: el fantasma
            -- siempre va nivelado (rx/ry en 0) para evitar giros raros.
            setElementFrozen(element, true)
            setElementRotation(element, 0, 0, tonumber(entry.rz) or 0)
        end
    end
    if not element then
        if isElement(driver) then destroyElement(driver) end
        return nil, nil
    end
    setElementAlpha(element, ghostAlpha)
    setElementCollisionsEnabled(element, false)
    setElementDimension(element, getElementDimension(localPlayer))
    setElementInterior(element, interior)
    return element, driver
end

local function updateGhost(entry)
    local kind = entry.onFoot == true and "ped" or "vehicle"
    local model = tonumber(entry.model)
    local skin = tonumber(entry.skin) or model
    local seat = tonumber(entry.seat) or -1
    local g = ghosts[entry.id]
    if g and (g.kind ~= kind or g.model ~= model or g.skin ~= skin or g.seat ~= seat) then
        destroyGhost(entry.id)
        g = nil
    end
    if not g then
        local element, driver = createGhostElement(entry, kind)
        if not element then return end
        g = {
            id = entry.id,
            kind = kind,
            model = model,
            skin = skin,
            seat = seat,
            element = element,
            driver = driver,
            x = entry.x, y = entry.y, z = entry.z,
            rz = tonumber(entry.rz) or 0,
            tx = entry.x, ty = entry.y, tz = entry.z,
            trz = tonumber(entry.rz) or 0,
            name = tostring(entry.name or ""),
            interior = tonumber(entry.interior) or 0,
            updatedAt = getTickCount(),
        }
        ghosts[entry.id] = g
    else
        g.tx, g.ty, g.tz = entry.x, entry.y, entry.z
        g.trz = tonumber(entry.rz) or 0
        g.name = tostring(entry.name or g.name)
        g.interior = tonumber(entry.interior) or g.interior
        for _, el in ipairs({ g.element, g.driver }) do
            if isElement(el) then
                setElementAlpha(el, ghostAlpha)
                setElementDimension(el, getElementDimension(localPlayer))
                setElementInterior(el, g.interior)
            end
        end
    end
end

addEvent("sr:ghosts", true)
addEventHandler("sr:ghosts", resourceRoot, function(entries, alpha)
    ghostAlpha = math.max(0, math.min(255, tonumber(alpha) or ghostAlpha))
    local seen = {}
    if type(entries) == "table" then
        for _, entry in ipairs(entries) do
            if type(entry) == "table" and type(entry.id) == "number" then
                seen[entry.id] = true
                updateGhost(entry)
            end
        end
    end
    -- La lista es completa: lo que no vino ya no se ve.
    for id in pairs(ghosts) do
        if not seen[id] then destroyGhost(id) end
    end
end)

-- Suavizado: los updates llegan cada ~100 ms; interpolamos posicion/rotacion.
addEventHandler("onClientPreRender", root, function()
    if SR.hudHidden or SR.resultsVisible then return end
    local now = getTickCount()
    for _, g in pairs(ghosts) do
        if isElement(g.element) then
            local dt = math.min(0.1, (now - (g.updatedAt or now)) / 1000)
            g.updatedAt = now
            local k = math.min(1, dt * 12)
            g.x = g.x + (g.tx - g.x) * k
            g.y = g.y + (g.ty - g.y) * k
            g.z = g.z + (g.tz - g.z) * k
            g.rz = lerpAngle(g.rz, g.trz, k)
            setElementPosition(g.element, g.x, g.y, g.z, false)
            setElementRotation(g.element, 0, 0, g.rz)
            -- El ped no esta congelado y no tiene colisiones: sin esto la
            -- gravedad lo va hundiendo entre frames.
            if g.kind == "ped" then setElementVelocity(g.element, 0, 0, 0) end
        end
    end
end)

-- Nametag de cada fantasma.
addEventHandler("onClientRender", root, function()
    if SR.hudHidden or SR.resultsVisible then return end
    local ui, drawText = SR.ui, SR.drawText
    if not ui or not drawText then return end
    local sw, sh = guiGetScreenSize()
    local px, py, pz = getElementPosition(localPlayer)
    for _, g in pairs(ghosts) do
        if isElement(g.element) and g.name ~= "" and getDistanceBetweenPoints3D(px, py, pz, g.x, g.y, g.z) < 250 then
            local zOffset = g.kind == "vehicle" and 2.0 or 1.2
            local sx, sy = getScreenFromWorldPosition(g.x, g.y, g.z + zOffset)
            if sx and sy and sx > 0 and sy > 0 and sx < sw and sy < sh then
                local name = g.name:gsub("#%x%x%x%x%x%x", "")
                drawText(name, sx - ui(200), sy - ui(18), sx + ui(200), sy,
                    tocolor(255, 255, 255, 220), ui(0.9), "default-bold")
            end
        end
    end
end)

-- Limpieza en transiciones de ronda y al parar el resource.
addEventHandler("sr:countdown", resourceRoot, function() clearGhosts() end)
addEventHandler("sr:results", resourceRoot, function() clearGhosts() end)
addEventHandler("sr:failed", resourceRoot, function() clearGhosts() end)
addEventHandler("sr:finished", resourceRoot, function() clearGhosts() end)
addEventHandler("onClientResourceStop", resourceRoot, function() clearGhosts() end)
