-- Drive-by custom para el jugador (MTA/SA:O desactiva el task nativo).
-- Input: vehicle_fire (respeta el binding del jugador: lalt/rctrl en este server).
-- El cliente calcula el rayo/impacto y manda el disparo; el server valida,
-- aplica dano y descuenta ammo.
--
-- Autos: solo a los costados (se elige el lado por la camara).
-- Motos/bicis: costados y hacia adelante.
-- Disparar al aire consume ammo y crea el efecto, pero no hace dano.

local lastShotAt = 0
local wasPressed = false
local sfxVariant = 0

local function vehicleKind(vehicle)
    if not isElement(vehicle) then return nil end
    local t = getVehicleType(vehicle)
    t = type(t) == "string" and t:lower() or ""
    if t == "automobile" or t == "car" then return "car" end
    if t == "bike" or t == "bicycle" or t == "bmx" then return "bike" end
    return nil
end

local function currentConfig()
    local weapon = getPedWeapon(localPlayer)
    local cfg = DriveBy.weapons[weapon]
    if not cfg then return nil end
    if getPedWeaponSlot(localPlayer) ~= 4 then return nil end
    return cfg, weapon
end

local function boundKeys()
    local keys = {}
    if type(getBoundKeys) ~= "function" then return keys end
    local ok, binds = pcall(getBoundKeys, "vehicle_fire")
    if not ok or type(binds) ~= "table" then return keys end
    for key in pairs(binds) do keys[#keys + 1] = tostring(key) end
    table.sort(keys)
    return keys
end

local function deviceState(tag)
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local slot = getPedWeaponSlot(localPlayer)
    triggerServerEvent("speedrun:drivebyDiag", resourceRoot, {
        tag = tag,
        weapon = getPedWeapon(localPlayer),
        slot = slot,
        ammo = slot and getPedTotalAmmo(localPlayer, 4) or 0,
        fire = isControlEnabled("vehicle_fire") == true,
        fireState = getPedControlState("vehicle_fire") == true,
        accelerate = isControlEnabled("accelerate") == true,
        gang = isPedDoingGangDriveby(localPlayer) == true,
        seat = isElement(vehicle) and getPedOccupiedVehicleSeat(localPlayer) or -1,
        frozen = isElementFrozen(localPlayer) == true,
        keys = boundKeys(),
    })
end

local function ensureFireControl()
    if not isElement(localPlayer) or isPedDead(localPlayer) or not isPedInVehicle(localPlayer) then return end
    if isElementFrozen(localPlayer) or isCursorShowing() or isChatBoxInputActive() then return end
    if not isControlEnabled("accelerate") then return end
    if not vehicleKind(getPedOccupiedVehicle(localPlayer)) then return end
    if not isControlEnabled("vehicle_fire") then toggleControl("vehicle_fire", true) end
end

local function canFire()
    if not isElement(localPlayer) or isPedDead(localPlayer) or not isPedInVehicle(localPlayer) then
        return false
    end
    if isElementFrozen(localPlayer) or isCursorShowing() or isChatBoxInputActive() then return false end
    -- No dependemos de isControlEnabled("vehicle_fire") aca: abajo lo
    -- re-habilitamos; el disparo lo decide getPedControlState.
    if not isControlEnabled("accelerate") then return false end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicleKind(vehicle) then return false end
    local ammo = getPedTotalAmmo(localPlayer, 4) or 0
    return currentConfig() ~= nil and ammo > 0
end

local function aimData(vehicle, kind)
    local _, _, rz = getElementRotation(vehicle)
    local rad = math.rad(rz)
    local forwardX, forwardY = -math.sin(rad), math.cos(rad)
    local rightX, rightY = math.cos(rad), math.sin(rad)

    local lookLeft = getPedControlState("vehicle_look_left") == true
    local lookRight = getPedControlState("vehicle_look_right") == true

    if lookLeft and not lookRight then
        -- Q: mirar/disparar a la izquierda.
        return { x = -rightX, y = -rightY, z = 0, side = -1,
                 rightX = rightX, rightY = rightY }
    elseif lookRight and not lookLeft then
        -- E: mirar/disparar a la derecha.
        return { x = rightX, y = rightY, z = 0, side = 1,
                 rightX = rightX, rightY = rightY }
    end

    -- Ninguna tecla (adelante) o Q+E (atras): solo dispara la moto/bici, adelante.
    if kind == "bike" then
        return { x = forwardX, y = forwardY, z = 0, side = 0,
                 rightX = rightX, rightY = rightY }
    end
    return nil
end

-- Devuelve el objetivo visible mas cercano al rayo (auto-aim), peds y vehiculos.
local function aimAssist(ox, oy, oz, aim, range, vehicle)
    local dim = getElementDimension(localPlayer)
    local bestEl, bestDist = nil, nil

    local function consider(el, radius, sampleZ)
        if el == localPlayer or el == vehicle then return end
        if getElementDimension(el) ~= dim or not isElementStreamedIn(el) then return end
        local elType = getElementType(el)
        if elType == "ped" and isPedDead(el) then return end
        if elType == "vehicle" and isVehicleBlown(el) then return end

        local px, py, pz = getElementPosition(el)
        local dx, dy, dz = px - ox, py - oy, pz - oz
        local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
        if dist > range then return end
        local proj = dx * aim.x + dy * aim.y + dz * aim.z
        if proj <= 0 then return end
        local perpSq = dist * dist - proj * proj
        if perpSq > radius * radius then return end

        -- Linea de vision: no debe haber un muro entre el origen y el objetivo.
        local losHit, _, _, _, losEl = processLineOfSight(
            ox, oy, oz, px, py, pz + sampleZ, true, true, true, true,
            false, false, false, false, vehicle)
        if (not losHit) or (losEl == el) then
            if not bestDist or dist < bestDist then
                bestEl, bestDist = el, dist
            end
        end
    end

    for _, ped in ipairs(getElementsByType("ped")) do
        consider(ped, DriveBy.aimAssistRadius, 0.7)
    end
    for _, veh in ipairs(getElementsByType("vehicle")) do
        consider(veh, DriveBy.aimAssistVehicleRadius, 0.5)
    end

    return bestEl
end

-- Animacion de apuntado del jugador segun el lado (izq/der/delante).
local aimAnimKey = nil
local function aimAnimFrom(aim)
    if aim.side == 0 then return "front" end
    return aim.side > 0 and "right" or "left"
end

local function playAimAnim(key)
    if key == "front" then
        setPedAnimation(localPlayer, "PLAYER_DVBYS", "Plyr_DrivebyFwd", -1, true, false, false, false)
    elseif key == "right" then
        setPedAnimation(localPlayer, "ped", "Driveby_R", -1, true, false, false, false)
    else
        setPedAnimation(localPlayer, "ped", "Driveby_L", -1, true, false, false, false)
    end
end

local function setAimAnim(key)
    if key == aimAnimKey then return end
    aimAnimKey = key
    playAimAnim(key)
end

local function stopAimAnim()
    if aimAnimKey then
        aimAnimKey = nil
        setPedAnimation(localPlayer, false)
    end
end

local function fireShot()
    if not canFire() then return end
    local cfg, weapon = currentConfig()
    if not cfg then return end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local kind = vehicleKind(vehicle)
    local aim = aimData(vehicle, kind)
    if not aim then return end

    local px, py, pz = getElementPosition(localPlayer)
    local ox, oy, oz
    if kind == "car" then
        ox = px + aim.rightX * aim.side * DriveBy.fireOriginSide
        oy = py + aim.rightY * aim.side * DriveBy.fireOriginSide
        oz = pz + DriveBy.fireOriginUp
    else
        ox = px + aim.x * DriveBy.fireOriginBikeForward
        oy = py + aim.y * DriveBy.fireOriginBikeForward
        oz = pz + DriveBy.fireOriginUp
    end

    local ex = ox + aim.x * cfg.range
    local ey = oy + aim.y * cfg.range
    local ez = oz + aim.z * cfg.range
    local hit, hx, hy, hz, hitElement = processLineOfSight(
        ox, oy, oz, ex, ey, ez,
        true, true, true, true, false, false, false, false, vehicle)

    local target = nil
    if hit and isElement(hitElement) and hitElement ~= localPlayer and hitElement ~= vehicle then
        local hitType = getElementType(hitElement)
        if hitType == "player" or hitType == "ped" or hitType == "vehicle" then
            target = hitElement
        end
    end

    local impactX, impactY, impactZ = ex, ey, ez
    if hit then
        impactX, impactY, impactZ = hx or ex, hy or ey, hz or ez
    end

    -- Auto-aim: si el rayo no impactó nada, enganchar el objetivo más cercano
    -- (ped o vehículo) al rayo.
    if not target then
        local assist = aimAssist(ox, oy, oz, aim, cfg.range, vehicle)
        if assist then
            target = assist
            local tx, ty, tz = getElementPosition(assist)
            impactX, impactY, impactZ = tx, ty, tz
        end
    end

    fxAddGunshot(ox, oy, oz, aim.x, aim.y, aim.z, true)
    local sfx = cfg.sfx
    if sfx and sfx.ids then
        local index = 1
        if #sfx.ids > 1 then
            sfxVariant = sfxVariant % #sfx.ids + 1
            index = sfxVariant
        end
        local sound = playSFX("genrl", 136, sfx.ids[index], false)
        if isElement(sound) and type(setSoundVolume) == "function" then
            pcall(setSoundVolume, sound, 0.8)
        end
    end

    -- Recoil: breve sacudida de disparo; después se re-aplica el apuntado.
    setPedAnimation(localPlayer, "ped", "SHOT_partial", -1, false, false, false, false)
    if aimAnimKey then
        setTimer(function()
            if aimAnimKey and wasPressed then playAimAnim(aimAnimKey) end
        end, 320, 1)
    end

    triggerServerEvent("speedrun:drivebyShot", resourceRoot, {
        weapon = weapon,
        slot = getPedWeaponSlot(localPlayer),
        target = target,
        x = impactX, y = impactY, z = impactZ,
        aimX = aim.x, aimY = aim.y, aimZ = aim.z,
    })
end

-- Poll del control real de disparo. getPedControlState("vehicle_fire") respeta
-- el binding de GTA/MTA (en este server: lalt / rctrl), no solo mouse1.
addEventHandler("onClientRender", root, function()
    if not isElement(localPlayer) or isPedDead(localPlayer) then
        wasPressed = false
        stopAimAnim()
        return
    end
    ensureFireControl()
    local pressed = isPedInVehicle(localPlayer) and getPedControlState("vehicle_fire") == true
    if not pressed then
        wasPressed = false
        stopAimAnim()
        return
    end
    if not wasPressed then
        wasPressed = true
        deviceState("press")
    end
    if not canFire() then return end
    local cfg = currentConfig()
    if not cfg then return end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local kind = vehicleKind(vehicle)
    local aim = aimData(vehicle, kind)
    if not aim then
        -- Auto sin mirar a un costado (o Q+E hacia atras): no dispara.
        stopAimAnim()
        return
    end
    setAimAnim(aimAnimFrom(aim))
    local now = getTickCount()
    if now - lastShotAt < DriveBy.effectiveInterval(cfg, kind) then return end
    lastShotAt = now
    fireShot()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    deviceState("ready")
end)

addEventHandler("onClientPlayerVehicleEnter", localPlayer, function()
    -- Se selecciona el arma de drive-by (slot 4) sin activar el task nativo.
    local function select()
        if not isElement(localPlayer) or not isPedInVehicle(localPlayer) then return end
        local vehicle = getPedOccupiedVehicle(localPlayer)
        if not vehicleKind(vehicle) then return end
        local weapon = getPedWeapon(localPlayer, 4)
        local ammo = getPedTotalAmmo(localPlayer, 4) or 0
        if weapon and weapon ~= 0 and weapon ~= 1 and ammo > 0 then
            if getPedWeaponSlot(localPlayer) ~= 4 then setPedWeaponSlot(localPlayer, 4) end
        end
    end
    setTimer(select, 200, 1)
    setTimer(function()
        select()
        deviceState("enter")
    end, 1200, 1)
end)

addEventHandler("onClientPlayerVehicleExit", localPlayer, function()
    wasPressed = false
    stopAimAnim()
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    wasPressed = false
    stopAimAnim()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    wasPressed = false
    stopAimAnim()
end)
