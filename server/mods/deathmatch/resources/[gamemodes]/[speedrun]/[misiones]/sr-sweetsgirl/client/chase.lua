-- Persecucion de "Sweet's Girl" (cliente syncer), desde T0 (salto de sw5_cutscene_3, regla R3)
-- hasta el final. El servidor crea los peds y autos y manda sr5:task(token, ped, nombre, args);
-- client/actors.lua los pasa aqui (Chase.dispatch). COVERAGE.md manda.
--   group_member    {role, speaker, seat}: Sweet / novia. Emulacion del grupo del jugador
--                   (uncertain): suben al auto del jugador, bajan y lo siguen a pie; Sweet hace
--                   drive-by a los conductores Sentinel (setPedDriveBy, sin parametros del SCM).
--   member_state    {lost}: perdido / recuperado lo decide el servidor; perdido = sin ordenes.
--   sentinel_driver {role, vehicle}: TEMPACT_WAIT 1500 ([1]: + REVERSE_RIGHT 1000) y despues
--                   BLOCKPLAYER / RAMPLAYER con el sustituto setPedDriveTo renovado cada 500 ms
--                   (missing); alcance del [1] (teletransporte del SCM, uncertain); drive-by de
--                   los conductores a Sweet / novia (uncertain).
--   sentinel_leave  {speed}: MISSION_CRUISE -> setPedDriveWander a 20.
--   police_bike     {vehicle}: policia en moto (agregado, no esta en el SCM; SW5.COP). Persigue al
--                   jugador con setPedDriveTo, se baja y lo ataca a pie (setPedKillOnFoot) cuando
--                   lo alcanza, y vuelve a la moto si el jugador sube a un vehiculo o se aleja.
--   police_leave    {speed}: deja de perseguir (empieza la pelea en Seville) y se va.
-- Nada de aqui decide etapas, fallas ni la llegada: eso lo ve el servidor.
Chase = {}

local L = Sw5Logic
local LOOP_MS = 100
local PREP_POLL_MS = 250
local READY_TIMEOUT_MS = 10000

-- Grupo (sustituto en Lua; valores del builder, no del SCM)
local FOLLOW_STOP_DIST = 3.0
local SPRINT_DIST = 12.0
local FOLLOW_REISSUE_MS = 1000
local ENTER_REISSUE_MS = 5000
local EXIT_REISSUE_MS = 3000
local SWEET_DRIVEBY_RANGE = 40.0      -- COVERAGE: setPedDriveBy(sweet, conductor, 40, ..., 70)
local SWEET_DRIVEBY_RATE = 70
local SWEET_DRIVEBY_REISSUE_MS = 3000
-- Conductores Sentinel: TASK_SIMPLE_GANG_DRIVEBY 0.0 100.0 (decision maker) -> rafagas de drive-by
-- cuando estan cerca, porque la tarea reemplaza a la de manejo (sin probar en conductores).
local DRIVER_DRIVEBY_RANGE = 20.0
local DRIVER_DRIVEBY_ABORT = 40.0
local DRIVER_DRIVEBY_MS = 1500
local DRIVER_DRIVEBY_EVERY_MS = 4000
-- IS_POINT_ON_SCREEN ... 8.0
local SCREEN_RADIUS = 8.0
-- setPedDriveTo: "racing" (modo 3) y "plough_through" (DRIVINGSTYLE_PLOUGH_THROUGH = 3)
local DRIVE_MODE, DRIVE_STYLE, DRIVE_MODE_INT, DRIVE_STYLE_INT = "racing", "plough_through", 3, 3
local VEHICLE_HEALTH_PACKET_CAP = 2047.5

local TASKS = {
    group_member = true, member_state = true, sentinel_driver = true, sentinel_leave = true,
    police_bike = true, police_leave = true,
}

local actors = {}   -- [ped] = actor
local loopTimer = nil
local profiles = {} -- [ped] = token de acquirePedNativeEventProfile
local logged = {}
local catchups = 0

local function api(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return false end
    local ok, result = pcall(fn, ...)
    return ok and result
end

local function logOnce(kind, detail)
    local k = kind .. ":" .. detail
    if logged[k] then return end
    logged[k] = true
    if Sw5Client and Sw5Client.log then Sw5Client.log(kind, detail) end
end

local function isDead(ped)
    return not isElement(ped) or isPedDead(ped) or getElementHealth(ped) <= 0
end

local function carDead(veh)
    return not isElement(veh) or isVehicleBlown(veh) or getElementHealth(veh) <= 0
end

local function label(a)
    if a.kind == "member" then return a.role end
    if a.kind == "cop" then return "cop" end
    return "sentinel" .. a.role
end

-- El policia solo necesita la moto cargada y propia mientras va arriba de ella.
local function copOnBike(a)
    return a.kind == "cop" and isElement(a.vehicle) and getPedOccupiedVehicle(a.ped) == a.vehicle
end

-- Coordenadas "any means" del jugador y su heading (GET_CHAR_HEADING: en un auto, el del auto).
local function playerPose()
    local veh = getPedOccupiedVehicle(localPlayer)
    local el = veh or localPlayer
    local x, y, z = getElementPosition(el)
    local _, _, h = getElementRotation(el)
    return x, y, z, h
end

---------------------------------------------------------------------------
-- Preparacion (Fase 0: prepareActor + isPedNativeTaskReady)
---------------------------------------------------------------------------
local function owned(el)
    return isElement(el) and isElementStreamedIn(el) and isElementSyncer(el)
end

local function nativeReady(a)
    if not owned(a.ped) or api("isPedNativeTaskReady", a.ped) ~= true then return false end
    if (a.kind == "sentinel" or copOnBike(a)) and not owned(a.vehicle) then return false end
    return true
end

local function releaseReverse(a)
    if a.reversing and isElement(a.ped) then
        api("setPedControlState", a.ped, "brake_reverse", false)
        api("setPedControlState", a.ped, "vehicle_right", false)
    end
    a.reversing = false
end

local function onPrepared(a)
    local ped = a.ped
    a.prepared = true
    a.order = nil
    if a.kind == "member" then
        if not a.initialized then
            a.initialized = true
            -- SET_CHAR_SUFFERS_CRITICAL_HITS FALSE y SET_CHAR_ONLY_DAMAGED_BY_PLAYER FALSE.
            -- Daño de ped comun de GTA (x defendWeakness, no x 0.33): onPedDamage.
            Actors.applyCriticalHits(ped, false, "members", logOnce, true)
            if api("setPedOnlyDamagedByPlayer", ped, false) ~= true then logOnce("prep", "only_by_player:" .. a.role) end
        end
        return
    end
    if a.kind == "cop" then
        -- Perfil "mission": no reacciona por su cuenta (huir, etc.); solo hace lo que se le ordena.
        if not profiles[ped] then
            local token = api("acquirePedNativeEventProfile", ped, "mission")
            if token then profiles[ped] = token else logOnce("prep", "event_profile:cop") end
        end
        if not a.initialized then
            a.initialized = true
            Actors.applyCriticalHits(ped, true, "cop", logOnce, true)
        end
        a.nextDrive = 0
        a.wanderGiven = false
        return
    end
    -- Conductor Sentinel: decision maker sw5_seville_dec sin primitiva -> perfil "mission".
    if not profiles[ped] then
        local token = api("acquirePedNativeEventProfile", ped, "mission")
        if token then profiles[ped] = token else logOnce("prep", "event_profile:" .. label(a)) end
    end
    -- CREATE_CHAR_INSIDE_CAR PEDTYPE_MISSION1 FAM1 sin SET_CHAR_SUFFERS_CRITICAL_HITS: critical
    -- hits activos y vida 100 (GTA por defecto). El daño lo corrige onSentinelDamage.
    Actors.applyCriticalHits(ped, true, "sentinel_drivers", logOnce, true)
    local veh = a.vehicle
    local health = getElementHealth(veh)
    if not a.healthInit then
        -- SET_CAR_HEALTH 2500: el paquete de creacion la corta en 2047.5; el syncer la repone.
        a.healthInit = true
        setElementHealth(veh, SW5.SENTINEL.health)
    elseif a.lastHealth and a.lastHealth > VEHICLE_HEALTH_PACKET_CAP + 0.1
        and math.abs(health - VEHICLE_HEALTH_PACKET_CAP) < 0.6 then
        setElementHealth(veh, a.lastHealth) -- volvio a entrar en streaming con la vida cortada
    end
    a.nextDrive = 0
    a.wanderGiven = false
    a.reversing = false
end

local function startPrepare(a)
    a.prepared = false
    a.prepGen = (a.prepGen or 0) + 1
    local gen = a.prepGen
    local windowStart = getTickCount()
    local timer
    local function poll()
        if actors[a.ped] ~= a or a.prepGen ~= gen or isDead(a.ped) then
            if isTimer(timer) then killTimer(timer) end
            return
        end
        if not a.actorDone then
            local veh = (a.kind == "sentinel" or copOnBike(a)) and a.vehicle or false
            local ok, problems = false, "prep=export_failed"
            local called, r1, r2 = pcall(function() return exports.speedrun:prepareActor(a.ped, veh, true) end)
            if called then ok, problems = r1, r2 end
            if problems and problems ~= "prep=ok" then logOnce("prep", label(a) .. ":" .. tostring(problems)) end
            if ok then a.actorDone = true end
        end
        if a.actorDone and nativeReady(a) then
            if isTimer(timer) then killTimer(timer) end
            onPrepared(a)
            return
        end
        if getTickCount() - windowStart >= READY_TIMEOUT_MS then
            logOnce("ready_timeout", label(a))
            windowStart = getTickCount() -- sigue esperando (puede estar fuera de streaming)
        end
    end
    timer = setTimer(poll, PREP_POLL_MS, 0)
    a.prepTimer = timer
    poll()
end

---------------------------------------------------------------------------
-- Sweet y la novia: emulacion del grupo del jugador
---------------------------------------------------------------------------
-- Una orden con clave; se renueva cada `every` ms mientras la clave no cambie.
local function order(a, key, now, every, fn)
    if a.order == key and now - (a.orderAt or 0) < every then return end
    a.order, a.orderAt = key, now
    if fn() ~= true then logOnce("task_refused", label(a) .. ":" .. key) end
end

local function freeSeat(veh, preferred, self)
    local max = getVehicleMaxPassengers(veh) or 0
    local function free(seat)
        local occupant = getVehicleOccupant(veh, seat)
        return not occupant or occupant == self
    end
    if preferred >= 1 and preferred <= max and free(preferred) then return preferred end
    for seat = 1, max do
        if free(seat) then return seat end
    end
    return nil
end

local function nearest(kind, x, y, z, range)
    local best, bestD = nil, range
    for ped, b in pairs(actors) do
        if b.kind == kind and not isDead(ped) and isElementStreamedIn(ped)
            and (kind ~= "sentinel" or not carDead(b.vehicle)) then
            local bx, by, bz = getElementPosition(ped)
            local d = getDistanceBetweenPoints3D(x, y, z, bx, by, bz)
            if d < bestD then best, bestD = ped, d end
        end
    end
    return best
end

-- Drive-by de Sweet contra los conductores (IA de grupo; sin parametros del SCM).
local function sweetDriveBy(a, now)
    local x, y, z = getElementPosition(a.ped)
    local target = nearest("sentinel", x, y, z, SWEET_DRIVEBY_RANGE)
    if not target then
        a.dbTarget = nil
        return
    end
    if a.dbTarget == target and now - (a.dbAt or 0) < SWEET_DRIVEBY_REISSUE_MS then return end
    a.dbTarget, a.dbAt = target, now
    local seat = getPedOccupiedVehicleSeat(a.ped)
    local rhs = seat == 1 or seat == 3
    if api("setPedDriveBy", a.ped, target, SWEET_DRIVEBY_RANGE, "ai_all_directions", rhs, SWEET_DRIVEBY_RATE) ~= true then
        logOnce("task_refused", "sweet:drive_by")
    end
end

local function updateMember(a, now)
    if a.lost then return end -- fuera del grupo: sin ordenes hasta que el servidor lo recupere
    local ped = a.ped
    local pveh = getPedOccupiedVehicle(localPlayer)
    local myVeh = getPedOccupiedVehicle(ped)
    if pveh then
        if myVeh == pveh then
            a.order = nil
            if a.role == "sweet" then sweetDriveBy(a, now) end
            return
        end
        if myVeh then
            order(a, "exit", now, EXIT_REISSUE_MS, function() return api("setPedExitVehicle", ped) end)
            return
        end
        -- Jugador en un auto con lugar: TASK_ENTER_CAR_AS_PASSENGER (asiento SCM + 1)
        local seat = freeSeat(pveh, a.seat, ped)
        if seat then
            order(a, "enter" .. seat, now, ENTER_REISSUE_MS, function()
                return api("setPedEnterVehicle", ped, pveh, seat)
            end)
        end
        return
    end
    -- Jugador a pie: bajar y seguirlo
    if myVeh then
        order(a, "exit", now, EXIT_REISSUE_MS, function() return api("setPedExitVehicle", ped) end)
        return
    end
    local px, py, pz = getElementPosition(localPlayer)
    local x, y, z = getElementPosition(ped)
    local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
    if d <= FOLLOW_STOP_DIST then
        a.order = nil
        return
    end
    local move = d > SPRINT_DIST and "sprint" or "run"
    order(a, "follow", now, FOLLOW_REISSUE_MS, function()
        return api("setPedGoTo", ped, Vector3(px, py, pz), move, 1.5, 3.0, -2)
    end)
end

---------------------------------------------------------------------------
-- Sentinels
---------------------------------------------------------------------------
local function driveAt(a, x, y, z, speed)
    speed = speed or L.SENTINEL.cruiseSpeed
    local ok = false
    if not a.intArgs then
        ok = api("setPedDriveTo", a.ped, a.vehicle, Vector3(x, y, z), speed, DRIVE_MODE, DRIVE_STYLE)
        if ok ~= true then
            a.intArgs = true
            logOnce("chase", "drive_names_refused:" .. label(a))
        end
    end
    if a.intArgs then
        ok = api("setPedDriveTo", a.ped, a.vehicle, Vector3(x, y, z), speed, DRIVE_MODE_INT, DRIVE_STYLE_INT)
    end
    if ok ~= true then logOnce("task_refused", label(a) .. ":drive_to") end
    return ok == true
end

-- IS_POINT_ON_SCREEN x y z 8.0: el centro o algun extremo de la esfera en pantalla.
local SCREEN_OFFSETS = { { 0, 0, 0 }, { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }

local function pointOnScreen(x, y, z, r)
    for _, o in ipairs(SCREEN_OFFSETS) do
        if getScreenFromWorldPosition(x + o[1] * r, y + o[2] * r, z + o[3] * r, 0, false) then return true end
    end
    return false
end

local function upsideDown(car)
    local m = getElementMatrix(car)
    return m ~= nil and m ~= false and m[3][3] < 0
end

-- Alcance del Sentinel [1] (lineas 1572-1605). La condicion del nodo (GET_NTH_CLOSEST_CAR_NODE
-- con globales que la mision no actualiza) se toma como cumplida (pendiente 8).
local function catchUp(a, now)
    local ped, car = a.ped, a.vehicle
    local px, py, pz, ph = playerPose()
    local x, y, z = getElementPosition(ped)
    local C = L.CATCHUP
    local inRange = L.inLocate3D(px, py, pz, { x = x, y = y, z = z, rx = C.rx, ry = C.ry, rz = C.rz })
    local step = L.catchupStep(a.chase, now, inRange)
    if step == "save" then
        a.saved = { x = px, y = py, z = pz, h = ph }
    elseif step == "try" then
        local s = a.saved
        if s and not pointOnScreen(s.x, s.y, s.z, SCREEN_RADIUS) and not upsideDown(car)
            and getPedOccupiedVehicle(ped) == car then
            -- SET_CAR_COORDINATES (suma la base del modelo), SET_CAR_HEADING, SET_CAR_FORWARD_SPEED 25
            local okBase, base = pcall(getElementDistanceFromCentreOfMassToBaseOfModel, car)
            if not okBase or type(base) ~= "number" then base = 0 end
            setElementPosition(car, s.x, s.y, s.z + base)
            setElementRotation(car, 0, 0, s.h)
            local fx, fy = L.forwardFromHeading(s.h)
            local v = C.forwardSpeed / 50
            setElementVelocity(car, fx * v, fy * v, 0)
            L.catchupDone(a.chase)
            a.nextDrive = 0
            catchups = catchups + 1
            if catchups <= 5 and Sw5Client and Sw5Client.log then Sw5Client.log("chase", "catchup:" .. catchups) end
        end
    end
end

-- Rafaga de drive-by del conductor hacia Sweet o la novia (TASK_SIMPLE_GANG_DRIVEBY del SCM).
local function driverDriveBy(a, now)
    if now < (a.nextDriveBy or 0) then return false end
    local x, y, z = getElementPosition(a.vehicle)
    local target = nearest("member", x, y, z, DRIVER_DRIVEBY_RANGE)
    if not target then return false end
    a.nextDriveBy = now + DRIVER_DRIVEBY_EVERY_MS
    if api("setPedDriveBy", a.ped, target, DRIVER_DRIVEBY_ABORT, "ai_all_directions", false, 100) == true then
        a.driveByUntil = now + DRIVER_DRIVEBY_MS
        return true
    end
    logOnce("task_refused", label(a) .. ":drive_by")
    return false
end

local function updateSentinel(a, now)
    local ped, car = a.ped, a.vehicle
    if carDead(car) or getPedOccupiedVehicle(ped) ~= car then
        releaseReverse(a)
        return
    end
    a.lastHealth = getElementHealth(car)
    if a.leaving then
        releaseReverse(a)
        if not a.wanderGiven then
            a.wanderGiven = true
            if api("setPedDriveWander", ped, car, a.leaveSpeed or 20.0) ~= true then
                logOnce("task_refused", label(a) .. ":drive_wander")
            end
        end
        return
    end
    if a.role == 1 then catchUp(a, now) end
    local phase = L.sentinelPhase(a.role, now - a.t0)
    if phase == "wait" then return end -- TEMPACT_WAIT 1500
    if phase == "reverse" then
        -- TEMPACT_REVERSE_RIGHT 1000: controles del conductor (sin probar en un ped nativo)
        if not a.reversing then
            a.reversing = true
            api("setPedControlState", ped, "brake_reverse", true)
            api("setPedControlState", ped, "vehicle_right", true)
        end
        return
    end
    releaseReverse(a)
    if now < (a.driveByUntil or 0) then return end
    if driverDriveBy(a, now) then return end
    if now >= (a.nextDrive or 0) then
        a.nextDrive = now + L.SENTINEL.reissueMs
        local x, y, z = playerPose()
        driveAt(a, x, y, z)
    end
end

---------------------------------------------------------------------------
-- Policia en moto (SW5.COP)
---------------------------------------------------------------------------
-- Velocidad del vehiculo en km/h (getElementVelocity da unidades por 1/50 s: x 50 x 3.6).
local function bikeKmh(veh)
    local vx, vy, vz = getElementVelocity(veh)
    return math.sqrt(vx * vx + vy * vy + vz * vz) * 180
end

local function updateCop(a, now)
    local C = SW5.COP
    local ped, bike = a.ped, a.vehicle
    local bikeOk = not carDead(bike)
    local myVeh = getPedOccupiedVehicle(ped)
    local onBike = myVeh ~= false and myVeh ~= nil and myVeh == bike

    if a.leaving then
        if a.wanderGiven then return end
        a.wanderGiven = true
        local ok
        if onBike and bikeOk then
            ok = api("setPedDriveWander", ped, bike, a.leaveSpeed or C.leaveSpeed)
        else
            ok = api("setPedWander", ped, "walk", 0, true)
        end
        if ok ~= true then logOnce("task_refused", "cop:leave") end
        return
    end

    local px, py, pz = getElementPosition(localPlayer)
    local x, y, z = getElementPosition(ped)
    local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
    local playerInVeh = getPedOccupiedVehicle(localPlayer) and true or false

    if onBike then
        if not bikeOk then
            a.stopSince = nil
            order(a, "exit", now, EXIT_REISSUE_MS, function() return api("setPedExitVehicle", ped) end)
            return
        end
        if not playerInVeh and d <= C.exitDist then
            -- Frena antes de bajarse (si se baja en movimiento, salta de la moto).
            a.stopSince = a.stopSince or now
            if bikeKmh(bike) <= C.stopKmh or now - a.stopSince >= C.stopMaxMs then
                order(a, "exit", now, EXIT_REISSUE_MS, function() return api("setPedExitVehicle", ped) end)
            elseif now >= (a.nextDrive or 0) then
                a.nextDrive = now + C.reissueMs
                local bx, by, bz = getElementPosition(bike)
                -- Objetivo = su propia posicion a velocidad minima: frena y se queda. Velocidad 1 y no
                -- 0 para que setPedDriveTo no la rechace (y driveAt no cambie a argumentos numericos).
                driveAt(a, bx, by, bz, C.stopDriveSpeed)
            end
            return
        end
        a.stopSince = nil
        if now >= (a.nextDrive or 0) then
            a.nextDrive = now + C.reissueMs
            local tx, ty, tz = playerPose()
            local speed = (not playerInVeh and d <= C.slowDist) and C.slowSpeed or C.driveSpeed
            driveAt(a, tx, ty, tz, speed)
        end
        return
    end
    a.stopSince = nil
    if myVeh then return end -- subido a otro vehiculo: sin ordenes

    -- A pie: vuelve a la moto si el jugador se escapa en un vehiculo o se aleja; si no, lo ataca.
    if bikeOk and (playerInVeh or d > C.reenterDist) then
        local bx, by, bz = getElementPosition(bike)
        if getDistanceBetweenPoints3D(x, y, z, bx, by, bz) <= C.bikeReachDist then
            order(a, "enter", now, ENTER_REISSUE_MS, function() return api("setPedEnterVehicle", ped, bike, 0) end)
            a.nextDrive = 0
            return
        end
    end
    order(a, "kill", now, C.killReissueMs, function() return api("setPedKillOnFoot", ped, localPlayer) end)
end

---------------------------------------------------------------------------
-- Bucle y registro
---------------------------------------------------------------------------
local function loop()
    local now = getTickCount()
    for ped, a in pairs(actors) do
        if isDead(ped) then
            if a.kind == "sentinel" then releaseReverse(a) end
        elseif a.prepared and owned(ped) then
            if a.kind == "member" then
                updateMember(a, now)
            elseif a.kind == "cop" then
                updateCop(a, now)
            else
                updateSentinel(a, now)
            end
        end
    end
end

local function onStreamIn()
    local a = actors[source]
    if a and a.actorDone and not isDead(a.ped) then startPrepare(a) end
end

local function onStreamOut()
    local a = actors[source]
    if a then
        a.prepared = false
        if a.kind == "sentinel" then releaseReverse(a) end
    end
end

-- Daño como en GTA (Actors.applyGtaDamage, session B fix 1): conductores Sentinel y Sweet / novia.
-- Sweet y la novia conservan critical hits FALSE del SCM; solo cambia el multiplicador.
local function onPedDamage(attacker, weapon, bodypart, loss)
    local a = actors[source]
    if not a then return end
    -- Solo el dueño de la copia daña a sus peds (Actors.rejectForeignDamage, revision final I4).
    local damageLabel = a.kind == "sentinel" and "sentinel_drivers" or (a.kind == "cop" and "cop" or "members")
    if Actors.rejectForeignDamage(attacker, damageLabel) then return end
    if a.kind == "cop" then
        Actors.applyGtaDamage(source, attacker, weapon, bodypart, loss, { label = "cop", criticalHits = true })
    elseif a.kind == "sentinel" then
        Actors.applyGtaDamage(source, attacker, weapon, bodypart, loss,
            { label = "sentinel_drivers", criticalHits = true })
    else
        local def = a.role == "sweet" and SW5.SWEET or SW5.GIRL
        Actors.applyGtaDamage(source, attacker, weapon, bodypart, loss,
            { label = "members", criticalHits = false, defendWeakness = def.defendWeakness })
    end
end

local function register(a)
    actors[a.ped] = a
    addEventHandler("onClientElementStreamIn", a.ped, onStreamIn, false)
    addEventHandler("onClientElementStreamOut", a.ped, onStreamOut, false)
    Actors.seedHealth(a.ped)
    addEventHandler("onClientPedDamage", a.ped, onPedDamage, false)
    startPrepare(a)
    if not loopTimer then loopTimer = setTimer(loop, LOOP_MS, 0) end
end

function Chase.handles(taskName)
    return TASKS[taskName] == true
end

function Chase.dispatch(ped, taskName, args)
    if type(args) ~= "table" then
        logOnce("task", "bad_args:" .. tostring(taskName))
        return false
    end
    local a = actors[ped]
    if taskName == "group_member" then
        local seat = tonumber(args.seat)
        if a or (args.role ~= "sweet" and args.role ~= "girl") or not seat then
            logOnce("task", "bad_args:" .. taskName)
            return false
        end
        local speaker = tonumber(args.speaker)
        if speaker then TextAudio.setSpeaker(speaker, ped) end -- audio_actor[2] / [3]
        register({ ped = ped, kind = "member", role = args.role, seat = seat, lost = false })
    elseif taskName == "sentinel_driver" then
        local veh, role = args.vehicle, tonumber(args.role)
        if a or (role ~= 0 and role ~= 1) or not isElement(veh) or getElementType(veh) ~= "vehicle" then
            logOnce("task", "bad_args:" .. taskName)
            return false
        end
        -- T0 del cliente = llegada de la orden (el servidor la manda en el tick de T0).
        register({ ped = ped, kind = "sentinel", role = role, vehicle = veh, t0 = getTickCount(), chase = { chase = 1 } })
    elseif taskName == "member_state" then
        if a and a.kind == "member" then
            a.lost = args.lost == true
            a.order = nil
        end
    elseif taskName == "police_bike" then
        local veh = args.vehicle
        if a or not isElement(veh) or getElementType(veh) ~= "vehicle" then
            logOnce("task", "bad_args:" .. taskName)
            return false
        end
        register({ ped = ped, kind = "cop", vehicle = veh })
    elseif taskName == "police_leave" then
        if a and a.kind == "cop" then
            a.leaving = true
            a.leaveSpeed = tonumber(args.speed) or SW5.COP.leaveSpeed
            a.order = nil
        end
    elseif taskName == "sentinel_leave" then
        if a and a.kind == "sentinel" then
            a.leaving = true
            a.leaveSpeed = tonumber(args.speed) or 20.0
            releaseReverse(a)
        end
    end
    return true
end

function Chase.reset()
    if loopTimer and isTimer(loopTimer) then killTimer(loopTimer) end
    loopTimer = nil
    for ped, a in pairs(actors) do
        if a.prepTimer and isTimer(a.prepTimer) then killTimer(a.prepTimer) end
        a.prepGen = (a.prepGen or 0) + 1
        if a.kind == "sentinel" then releaseReverse(a) end
        if isElement(ped) then
            removeEventHandler("onClientElementStreamIn", ped, onStreamIn)
            removeEventHandler("onClientElementStreamOut", ped, onStreamOut)
            removeEventHandler("onClientPedDamage", ped, onPedDamage)
        end
    end
    actors = {}
    for _, token in pairs(profiles) do api("releasePedNativeEventProfile", token) end
    profiles = {}
    logged = {}
    catchups = 0
end
