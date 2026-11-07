-- Actores de "Sweet's Girl" (cliente syncer). El servidor crea los peds y manda
-- sr5:task(token, ped, taskName, args); aqui se preparan (receta de la Fase 0: prepareActor,
-- isPedNativeTaskReady <= 10 s) y se les dan las tareas nativas que dice COVERAGE.md.
-- Task 9: los 5 Seville de sw5_scene1 ("seville_attacker") y su IA (sw5_ped_actions).
-- Task 10: Sweet, la novia y los Sentinels de scene3 van en client/chase.lua (Chase.dispatch).
-- Nada de aqui decide etapas: el servidor ve las muertes por sync.
Actors = {}

local L = Sw5Logic
local LOOP_MS = 50            -- sw5_red_check_time = TIMERA + 50
local PREP_POLL_MS = 250
local READY_TIMEOUT_MS = 10000
local KILL_GRACE_MS = 1000    -- tiempo para que GTA instale la tarea antes de preguntar si sigue
local DIVE_MS, DOWN_MS, GETUP_MS = 1000, 500, 1000 -- TASK_DIVE_AND_GET_UP ... 500 (sustituto)
local RETURN_TIMEOUT_MS = 6000 -- TASK_FOLLOW_PATH_NODES_TO_COORD ... PEDMOVE_RUN 6000
local RETURN_ARRIVE_DIST = 1.5

local reds = {}     -- [idx 0..4] = red
local byPed = {}    -- [ped] = red
local brain = nil   -- { this, spotted, nearest, timer }
local profiles = {} -- [ped] = token de acquirePedNativeEventProfile
local logged = {}

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

local function isRedDead(red)
    return not red or not isElement(red.ped) or isPedDead(red.ped) or getElementHealth(red.ped) <= 0
end

---------------------------------------------------------------------------
-- Daño como en GTA (session B, fix 1). Los peds de script son CPlayerPed: GTA les aplica el
-- factor 0.33 de jugador y nunca los mata de un tiro a la cabeza (Sw5Logic.gtaPedDamage).
-- Se corrige en onClientPedDamage, solo en el syncer: se pone la vida que habria dejado un CPed
-- comun. Si queda en 0, CClientGame::ApplyPedDamageFromGame relee la vida despues del evento y
-- manda el aviso de muerte con el atacante, el arma y la parte del cuerpo de este golpe (ver
-- fix-1-report). Respaldo: el servidor mata con killPed a los que ve con vida <= 0 sin morir.
-- "Antes del golpe" es la ultima vida conocida del ped (sembrada en la preparacion y puesta
-- despues de cada golpe), no la que da getElementHealth dentro del evento (revision, punto 2).
---------------------------------------------------------------------------
local known = setmetatable({}, { __mode = "k" }) -- [ped] = ultima vida conocida
local damageLogged = {}

-- GENERATE_RANDOM_INT_IN_RANGE lo hi: [lo, hi)
local function randRange(lo, hi) return math.random(lo, hi - 1) end

-- Politica de critical hits. `intended` es la del SCM para ese ped (la manda el que llama): si
-- falta el getter o falla, manda `intended`; un critical hits FALSE nunca se vuelve verdadero.
function Actors.suffersCriticalHits(ped, intended)
    if not intended then return false end
    local fn = getPedSuffersCriticalHits
    if type(fn) ~= "function" then return true end
    local ok, result = pcall(fn, ped)
    return not (ok and result == false)
end

-- SET_CHAR_SUFFERS_CRITICAL_HITS: se fija y se informa una vez por tipo de ped
-- ("SR5|prep|<tipo> critical_hits=<valor> gta_damage=<on|off>"). log = logOnce del archivo.
-- Tambien siembra la vida conocida del ped.
function Actors.applyCriticalHits(ped, value, label, log, gtaDamage)
    local set = api("setPedSuffersCriticalHits", ped, value) == true
    local read = api("getPedSuffersCriticalHits", ped)
    Actors.seedHealth(ped)
    log("prep", label .. " critical_hits=" .. tostring(Actors.suffersCriticalHits(ped, value))
        .. " read=" .. tostring(read) .. (set and "" or " set_refused")
        .. " gta_damage=" .. (gtaDamage and "on" or "off"))
    return set
end

function Actors.seedHealth(ped)
    if isElement(ped) and not isPedDead(ped) then known[ped] = getElementHealth(ped) end
end

-- Solo el dueño de la copia (este cliente: los handlers de daño existen solo en el suyo, el
-- syncer) puede dañar a los peds de la mision. Un jugador ajeno (espectador en la dimension de la
-- copia, aun con un cliente modificado que se salte el congelado) o un vehiculo que maneja: se
-- cancela el daño (revision final, I4). Devuelve true si lo cancelo.
function Actors.rejectForeignDamage(attacker, label)
    if not isElement(attacker) then return false end
    local who = attacker
    if getElementType(attacker) == "vehicle" then who = getVehicleController(attacker) end
    if not isElement(who) or getElementType(who) ~= "player" or who == localPlayer then return false end
    cancelEvent()
    local key = tostring(label) .. ":foreign_cancelled"
    if not damageLogged[key] then
        damageLogged[key] = true
        if Sw5Client and Sw5Client.log then Sw5Client.log("damage", tostring(label) .. " foreign_cancelled") end
    end
    return true
end

-- opts = { label, criticalHits (politica del SCM), defendWeakness (pedstat del modelo; nil = 1.0) }
function Actors.applyGtaDamage(ped, attacker, weapon, bodypart, loss, opts)
    if not isElement(ped) or not isElementSyncer(ped) or isPedDead(ped) then return end
    local after = getElementHealth(ped)
    local before = known[ped]
    local byPlayer = isElement(attacker) and getElementType(attacker) == "player"
    local health, why = L.gtaPedDamage({
        healthBefore = before, healthAfter = after, loss = loss, weapon = weapon, bodypart = bodypart,
        inVehicle = isPedInVehicle(ped), byPlayer = byPlayer,
        criticalHits = Actors.suffersCriticalHits(ped, opts.criticalHits), armor = getPedArmor(ped),
        defendWeakness = opts.defendWeakness,
    }, randRange)
    if health then setElementHealth(ped, health) end
    known[ped] = health or after
    -- Una linea por tipo de ped y motivo (SR5|damage|...): before = vida conocida, expected =
    -- before - loss (lo que deberia dar getElementHealth en el evento), mta_after = lo que dio.
    local key = opts.label .. ":" .. tostring(why or "unchanged")
    if not damageLogged[key] then
        damageLogged[key] = true
        if Sw5Client and Sw5Client.log then
            Sw5Client.log("damage", ("%s %s weapon=%s part=%s before=%s loss=%.2f expected=%s mta_after=%.2f new=%s by_player=%s"):format(
                opts.label, tostring(why or "unchanged"), tostring(weapon), tostring(bodypart),
                before and ("%.2f"):format(before) or "nil", loss or 0,
                before and ("%.2f"):format(before - (loss or 0)) or "nil", after,
                health and ("%.2f"):format(health) or "nil", tostring(byPlayer)))
        end
    end
end

local function houseVector()
    local h = SW5.SCENE1.houseTarget
    return Vector3(h.x, h.y, h.z)
end

---------------------------------------------------------------------------
-- Preparacion (Fase 0: prepareActor + isPedNativeTaskReady)
---------------------------------------------------------------------------
local function nativeReady(ped)
    if not isElement(ped) or not isElementStreamedIn(ped) or not isElementSyncer(ped) then return false end
    return api("isPedNativeTaskReady", ped) == true
end

local issue -- forward

local function onPrepared(red)
    local ped = red.ped
    red.prepared = true
    -- Decision maker sw5_seville_dec: sin primitiva (missing) -> perfil "mission" de Neon.
    if not profiles[ped] then
        local token = api("acquirePedNativeEventProfile", ped, "mission")
        if token then profiles[ped] = token else logOnce("prep", "event_profile:" .. red.idx) end
    end
    -- CREATE_CHAR PEDTYPE_MISSION1 sin SET_CHAR_SUFFERS_CRITICAL_HITS: critical hits activos (GTA
    -- por defecto). Vida 100 por defecto (createPed). El daño lo corrige onRedDamage.
    Actors.applyCriticalHits(ped, true, "reds", logOnce, true)
    if not red.initialized then
        red.initialized = true
        api("setPedWeaponAccuracy", ped, SW5.SCENE1.createAccuracy) -- SET_CHAR_ACCURACY 65
        -- TASK_TOGGLE_DUCK TRUE: sin primitiva (uncertain) -> control "crouch" antes del disparo.
        api("setPedControlState", ped, "crouch", true)
        -- SET_CHAR_KINDA_STAY_IN_SAME_PLACE TRUE -> setPedStayInSamePlace (variante sin "KINDA").
        if api("setPedStayInSamePlace", ped, true) ~= true then logOnce("prep", "stay_in_place:" .. red.idx) end
        red.appliedAcc = nil
        issue(red, red.task or "house") -- TASK_SHOOT_AT_COORD casa -2
    else
        -- Volvio a entrar en streaming: se repone la tarea que tenia.
        red.appliedAcc = nil
        red.divePhase = nil
        issue(red, red.task == "dive" and (red.prevTask or "house") or (red.task or "house"))
    end
end

local function startPrepare(red)
    red.prepared = false
    red.prepGen = (red.prepGen or 0) + 1
    local gen = red.prepGen
    local windowStart = getTickCount()
    local timer
    local function poll()
        if reds[red.idx] ~= red or red.prepGen ~= gen or isRedDead(red) then
            if isTimer(timer) then killTimer(timer) end
            return
        end
        if not red.actorDone then
            local ok, problems = false, "prep=export_failed"
            local called, r1, r2 = pcall(function() return exports.speedrun:prepareActor(red.ped, false, true) end)
            if called then ok, problems = r1, r2 end
            if problems and problems ~= "prep=ok" then logOnce("prep", red.idx .. ":" .. tostring(problems)) end
            if ok then red.actorDone = true end
        end
        if red.actorDone and nativeReady(red.ped) then
            if isTimer(timer) then killTimer(timer) end
            onPrepared(red)
            return
        end
        if getTickCount() - windowStart >= READY_TIMEOUT_MS then
            logOnce("ready_timeout", tostring(red.idx))
            windowStart = getTickCount() -- sigue esperando (puede estar fuera de streaming)
        end
    end
    timer = setTimer(poll, PREP_POLL_MS, 0)
    red.prepTimer = timer
    poll()
end

---------------------------------------------------------------------------
-- Tareas (nombres: house, shootChar, kill, returning, dive)
---------------------------------------------------------------------------
issue = function(red, name)
    local now = getTickCount()
    if name ~= "dive" then red.task = name end
    red.taskAt = now
    if not red.prepared or isRedDead(red) then return false end -- se da al quedar listo
    local ped = red.ped
    local ok
    if name == "house" then
        ok = api("setPedShootAt", ped, houseVector(), -1)
    elseif name == "shootChar" then
        -- TASK_SHOOT_AT_CHAR red scplayer -2: no existe; coordenada del jugador, renovada.
        local x, y, z = getElementPosition(localPlayer)
        ok = api("setPedShootAt", ped, Vector3(x, y, z), -1)
        red.nextRefresh = now + math.random(250, 500)
    elseif name == "kill" then
        ok = api("setPedKillOnFoot", ped, localPlayer) -- TASK_KILL_CHAR_ON_FOOT
    elseif name == "returning" then
        -- Secuencia: FOLLOW_PATH_NODES_TO_COORD a su punto de creacion (run, 6000) + disparar a la casa
        local h = red.home
        ok = api("setPedNavigateTo", ped, Vector3(h.x, h.y, h.z + 1.0), "run", 0.5, 3.0, 2.0, false, RETURN_TIMEOUT_MS)
        red.returnUntil = now + RETURN_TIMEOUT_MS
    end
    if ok ~= true then logOnce("task_refused", red.idx .. ":" .. name) end
    return ok == true
end

-- TASK_DIVE_AND_GET_UP red 1.0 0.0 500: no existe -> animacion EV_dive y levantarse (uncertain).
local function startDive(red)
    if not red.prepared then return false end
    red.prevTask = red.task
    red.task = "dive"
    red.diveAt = getTickCount()
    red.divePhase = 1
    api("setPedAnimation", red.ped, "ped", "EV_dive", -1, false, true, false, true)
    return true
end

local function updateDive(red, now)
    if red.divePhase == 1 and now - red.diveAt >= DIVE_MS + DOWN_MS then
        red.divePhase = 2
        api("setPedAnimation", red.ped, "ped", "getup_front", -1, false, true, false, false)
    elseif red.divePhase == 2 and now - red.diveAt >= DIVE_MS + DOWN_MS + GETUP_MS then
        red.divePhase = nil
        api("setPedAnimation", red.ped)
        -- Termino: se vuelve a dar la tarea anterior (COVERAGE, fila de esquivar).
        issue(red, red.prevTask or "house")
    end
end

-- Mantenimiento de las tareas en curso (cada vuelta, para todos los vivos y listos).
local function maintain(red, now)
    local ped = red.ped
    if red.task == "dive" then
        updateDive(red, now)
    elseif red.task == "shootChar" then
        if now >= (red.nextRefresh or 0) then
            local x, y, z = getElementPosition(localPlayer)
            api("setPedShootAt", ped, Vector3(x, y, z), -1)
            red.nextRefresh = now + math.random(250, 500)
        end
    elseif red.task == "kill" then
        if now - (red.taskAt or now) >= KILL_GRACE_MS then
            local ok, doing = pcall(isPedDoingTask, ped, "TASK_COMPLEX_KILL_PED_ON_FOOT")
            if ok and doing == false then red.task = nil end -- FINISHED_TASK
        end
    elseif red.task == "returning" then
        local x, y, z = getElementPosition(ped)
        local h = red.home
        local arrived = getDistanceBetweenPoints3D(x, y, z, h.x, h.y, h.z + 1.0) < RETURN_ARRIVE_DIST
        if arrived or now >= (red.returnUntil or 0) then issue(red, "house") end
    end
end

---------------------------------------------------------------------------
-- sw5_ped_actions: un red por vuelta, turno 1, 2, 3, 4, 0
---------------------------------------------------------------------------
local function turn(idx)
    local red = reds[idx]
    local n = brain.nearest
    if not red then return end -- su sr5:task todavia no llego
    if isRedDead(red) then
        brain.spotted = true
        L.nearestDead(n, idx)
        return
    end
    if not brain.spotted and red.damaged then brain.spotted = true end -- HAS_CHAR_BEEN_DAMAGED_BY_CHAR

    local rx, ry, rz = getElementPosition(red.ped)
    local px, py, pz = getElementPosition(localPlayer)
    L.nearestAlive(n, idx, L.distance2D(px, py, rx, ry))

    local veh = getPedOccupiedVehicle(localPlayer)
    if veh then
        local vx, vy, vz = getElementVelocity(veh)
        local speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 50 -- GET_CAR_SPEED
        if speed > L.DIVE_MIN_SPEED then
            local offset = math.random() * 0.4 - 0.2 -- GENERATE_RANDOM_FLOAT_IN_RANGE -0.2 0.2
            local _, _, heading = getElementRotation(veh)
            if L.shouldDive(px, py, pz, rx, ry, rz, speed, heading, offset) then
                brain.spotted = true
                red.action = 4
            end
        end
    end

    if red.action == 4 and red.task ~= "dive" then
        if startDive(red) then red.action = 5 end
    end
    if red.action == 5 and red.task ~= "dive" then red.action = 0 end

    if red.action == 0 and brain.spotted and L.isNearest(n, idx) then red.action = 1 end

    if red.action == 1 then
        if not L.isNearest(n, idx) then
            -- Ya no es de los dos mas cercanos: vuelve a su lugar y a disparar a la casa.
            issue(red, "returning")
            red.action = 0
        elseif red.task ~= "shootChar" and red.task ~= "kill" then
            if math.random(0, 1) == 0 then issue(red, "shootChar") else issue(red, "kill") end
        end
    end
end

local function loop()
    if not brain then return end
    local now = getTickCount()
    local dead = 0
    for idx = 0, L.RED_COUNT - 1 do
        if reds[idx] and isRedDead(reds[idx]) then dead = dead + 1 end
    end
    local acc = L.accuracyFor(dead)
    for idx = 0, L.RED_COUNT - 1 do
        local red = reds[idx]
        if red and red.prepared and not isRedDead(red) then
            if red.appliedAcc ~= acc then
                api("setPedWeaponAccuracy", red.ped, acc)     -- SET_CHAR_ACCURACY new_accuracy
                api("setPedWeaponShootingRate", red.ped, acc) -- SET_CHAR_SHOOT_RATE new_accuracy
                red.appliedAcc = acc
            end
            maintain(red, now)
        end
    end
    brain.this = L.nextRed(brain.this)
    turn(brain.this)
end

---------------------------------------------------------------------------
-- Registro
---------------------------------------------------------------------------
local function onRedDamage(attacker, weapon, bodypart, loss)
    local red = byPed[source]
    if not red then return end
    if Actors.rejectForeignDamage(attacker, "reds") then return end
    Actors.applyGtaDamage(source, attacker, weapon, bodypart, loss, { label = "reds", criticalHits = true })
    if attacker == localPlayer or (attacker and attacker == getPedOccupiedVehicle(localPlayer)) then
        red.damaged = true
    end
end

local function onRedStreamIn()
    local red = byPed[source]
    if red and red.initialized and not isRedDead(red) then startPrepare(red) end
end

local function registerRed(ped, args)
    if type(args) ~= "table" or type(args.index) ~= "number" or type(args.home) ~= "table" then return false end
    local idx = args.index
    if idx < 0 or idx >= L.RED_COUNT or idx ~= math.floor(idx) then return false end
    local h = args.home
    if type(h.x) ~= "number" or type(h.y) ~= "number" or type(h.z) ~= "number" then return false end
    if reds[idx] then return false end
    local red = { ped = ped, idx = idx, home = { x = h.x, y = h.y, z = h.z }, action = 0, damaged = false }
    reds[idx] = red
    byPed[ped] = red
    Actors.seedHealth(ped)
    addEventHandler("onClientPedDamage", ped, onRedDamage, false)
    addEventHandler("onClientElementStreamIn", ped, onRedStreamIn, false)
    startPrepare(red)
    -- sw5_initialise_stuff: sw5_target[] = 0, nearest_range_1/2 = 99999.0
    if not brain then
        brain = { this = 0, spotted = false, nearest = L.newNearest() }
        brain.timer = setTimer(loop, LOOP_MS, 0)
    end
    return true
end

function Actors.dispatch(el, taskName, args)
    if not isElement(el) or getElementType(el) ~= "ped" then return false end
    if taskName == "seville_attacker" then
        if not registerRed(el, args) then logOnce("task", "bad_args:" .. tostring(taskName)) end
        return true
    end
    if Chase and Chase.handles(taskName) then return Chase.dispatch(el, taskName, args) end
    logOnce("task", "unknown:" .. tostring(taskName))
    return false
end

-- Fin de sw5_scene1 (o de la copia): se deja de dar ordenes.
function Actors.stopScene1()
    if brain and brain.timer and isTimer(brain.timer) then killTimer(brain.timer) end
    brain = nil
    for _, red in pairs(reds) do
        if red.prepTimer and isTimer(red.prepTimer) then killTimer(red.prepTimer) end
        red.prepGen = (red.prepGen or 0) + 1
        if isElement(red.ped) then
            removeEventHandler("onClientPedDamage", red.ped, onRedDamage)
            removeEventHandler("onClientElementStreamIn", red.ped, onRedStreamIn)
        end
    end
    reds, byPed = {}, {}
end

function Actors.reset()
    Actors.stopScene1()
    if Chase then Chase.reset() end
    for ped, token in pairs(profiles) do
        api("releasePedNativeEventProfile", token)
        profiles[ped] = nil
    end
    profiles = {}
    logged = {}
    damageLogged = {}
    known = setmetatable({}, { __mode = "k" })
end
