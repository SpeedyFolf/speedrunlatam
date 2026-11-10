-- Server del drive-by custom. El cliente manda el impacto; aca se valida
-- distancia/sector/cooldown, se descuenta ammo y se aplica dano manual.

local lastShot = {}
local deniedLogAt = {}

local function vehicleKind(vehicle)
    if not isElement(vehicle) then return nil end
    local t = getVehicleType(vehicle)
    t = type(t) == "string" and t:lower() or ""
    if t == "automobile" or t == "car" then return "car" end
    if t == "bike" or t == "bicycle" or t == "bmx" then return "bike" end
    return nil
end

local function logDenied(player, reason)
    local now = getTickCount()
    local last = deniedLogAt[player] or 0
    if now - last < 1000 then return end
    deniedLogAt[player] = now
    outputServerLog(("SR|driveby|denied|%s|%s"):format(isElement(player) and getPlayerName(player) or "?", tostring(reason)))
end

local function sectorAllows(kind, vehicle, dirX, dirY)
    local _, _, rz = getElementRotation(vehicle)
    local rad = math.rad(rz)
    local forwardX, forwardY = -math.sin(rad), math.cos(rad)
    local forwardDot = dirX * forwardX + dirY * forwardY
    if kind == "car" then
        -- Solo lateral: el objetivo no puede estar dominante al frente/atras.
        return math.abs(forwardDot) <= DriveBy.carMaxForwardDot
    end
    -- Moto/bici: lateral y adelante, nunca atras.
    return forwardDot >= DriveBy.bikeMinForwardDot
end

local function applyPedDamage(target, damage)
    local armor = getPedArmor(target) or 0
    if armor > 0 then
        local absorbed = math.min(armor, damage)
        setPedArmor(target, armor - absorbed)
        damage = damage - absorbed
    end
    if damage > 0 then
        local health = getElementHealth(target) or 0
        setElementHealth(target, math.max(0, health - damage))
    end
end

addEvent("speedrun:drivebyShot", true)
addEventHandler("speedrun:drivebyShot", resourceRoot, function(data)
    if source ~= resourceRoot or type(data) ~= "table" then return end
    local player = client
    if not isElement(player) or getElementType(player) ~= "player" or isPedDead(player) or
        not isPedInVehicle(player) then
        return
    end
    local vehicle = getPedOccupiedVehicle(player)
    local kind = vehicleKind(vehicle)
    if not kind then return end

    local weapon = getPedWeapon(player)
    local cfg = DriveBy.weapons[weapon]
    if not cfg or getPedWeaponSlot(player) ~= 4 then
        return logDenied(player, "arma/slot invalido weapon=" .. tostring(weapon))
    end

    local now = getTickCount()
    if now - (lastShot[player] or 0) < cfg.interval then return end

    local total = getPedTotalAmmo(player, 4) or 0
    if total <= 0 then return logDenied(player, "sin ammo") end

    local px, py, pz = getElementPosition(player)
    local hx = tonumber(data.x) or px
    local hy = tonumber(data.y) or py
    local hz = tonumber(data.z) or pz
    local dx, dy, dz = hx - px, hy - py, hz - pz
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance > cfg.range * 1.15 then return logDenied(player, "fuera de rango") end

    local target = data.target
    if isElement(target) then
        if target == player or target == vehicle then return end
        local targetType = getElementType(target)
        if targetType ~= "player" and targetType ~= "ped" and targetType ~= "vehicle" then
            target = nil
        elseif targetType == "player" or targetType == "ped" then
            if getPedOccupiedVehicle(target) == vehicle then target = nil end
        end
    else
        target = nil
    end
    if target then
        local tx, ty, tz = getElementPosition(target)
        if getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz) > cfg.range * 1.5 then
            target = nil
        end
    end

    -- Sector: usar el punto de impacto (lateral real), no el centro del
    -- objetivo, para no rechazar tiros al costado de un vehiculo grande.
    local dirX, dirY = data.aimX, data.aimY
    if distance > 0.1 then
        dirX, dirY = dx, dy
    elseif target then
        local tx, ty = getElementPosition(target)
        dirX, dirY = tx - px, ty - py
    end
    local dirLen = math.sqrt((dirX or 0) * (dirX or 0) + (dirY or 0) * (dirY or 0))
    if dirLen > 0.0001 and not sectorAllows(kind, vehicle, dirX / dirLen, dirY / dirLen) then
        return logDenied(player, "fuera de sector")
    end

    -- Descontar ammo aunque se dispare al aire.
    local clip = getPedAmmoInClip(player, 4) or 0
    local remaining = math.max(0, total - 1)
    local ammoOk = setWeaponAmmo(player, weapon, remaining, math.min(clip, remaining))
    if not ammoOk then
        -- Fallback por si la API no acepta el arma actual.
        takeWeapon(player, weapon)
        if remaining > 0 then
            giveWeapon(player, weapon, remaining, false)
            setPedWeaponSlot(player, 4)
        end
    end
    lastShot[player] = now

    local damage = 0
    if target then
        local factor = 1 - (1 - DriveBy.minDamageFactor) * math.min(1, distance / cfg.range)
        local targetType = getElementType(target)
        if targetType == "player" or targetType == "ped" then
            damage = cfg.damage * factor
            applyPedDamage(target, damage)
        else
            damage = cfg.vehicleDamage * factor
            local health = getElementHealth(target) or 0
            setElementHealth(target, math.max(0, health - damage))
        end
    end

    local ammoAfter = getPedTotalAmmo(player, 4) or -1
    outputServerLog(("SR|driveby|shot|%s|weapon=%d|target=%s|damage=%.1f|ammo=%d|ammoAfter=%d"):format(
        getPlayerName(player), weapon,
        target and (getElementType(target) == "player" and getPlayerName(target) or getElementType(target)) or "air",
        damage, remaining, ammoAfter))
end)

addEventHandler("onPlayerQuit", root, function()
    lastShot[source] = nil
    deniedLogAt[source] = nil
end)

-- Diagnostico de arranque/entrada/press. Permite confirmar que el script
-- cliente cargo y que vehicle_fire llega con el binding real del jugador.
addEvent("speedrun:drivebyDiag", true)
addEventHandler("speedrun:drivebyDiag", resourceRoot, function(data)
    if source ~= resourceRoot or type(data) ~= "table" then return end
    local who = isElement(client) and getPlayerName(client) or "?"
    local keys = type(data.keys) == "table" and table.concat(data.keys, ",") or tostring(data.keys)
    outputServerLog(("SR|driveby|%s|%s|weapon=%s|slot=%s|ammo=%s|fire=%s|fireState=%s|accelerate=%s|gang=%s|seat=%s|frozen=%s|keys=%s"):format(
        tostring(data.tag), who, tostring(data.weapon), tostring(data.slot), tostring(data.ammo),
        tostring(data.fire), tostring(data.fireState), tostring(data.accelerate), tostring(data.gang),
        tostring(data.seat), tostring(data.frozen), keys))
end)
