-- Maquina de etapas de "Sweet's Girl" (servidor). COVERAGE.md manda.
-- inst.stage solo cambia aqui (Stages.setStage), siempre desde el tick del servidor o desde la
-- creacion de la copia, por condiciones que mide el servidor:
--   scene1 -> phone : los 5 Seville muertos (isPedDead en el servidor; la muerte llega por sync)
--   phone  -> scene2: tope del servidor K+29000, o aviso "audio terminado" del cliente aceptado
--                     solo desde el piso K+11000 (COVERAGE §5). El handler remoto solo anota la hora.
--   scene2 -> scene3: compuerta del auto (posicion, vehiculo, pasajeros y clase, todo en el
--                     servidor). En ese tick (T0) se arma el estado del salto de sw5_cutscene_3
--                     (COVERAGE §6.2, regla R3) sin esperar nada del cliente.
--   scene3 -> fin   : llegada (COVERAGE §5) verificada en el servidor + R6 (60000 ms desde la
--                     largada de la copia) -> complete (local) -> reportCompleted. Unico lugar.
-- Fallas: muerte del jugador (la base); barra de Sweet en 0 (sweet_dead, SW5_L); desde T0,
-- Sweet o la novia muertos (sweet_dead / girl_dead, sw5_fail_checks).
-- Dialogos (COVERAGE §4; los reproduce client/text_audio.lua). Disparadores, todos aqui:
--   largada (Stages.onGo)  : MOBRING + MSWE13A..G (R2), despues SW5_A2 y SW5_17
--   phone (tickPhone)      : MOBRING K+1500 (espera), MOBRING K+4000 (se pierde si suena otra),
--                            SWE5_FA + SWE5_FB K+9000
--   T0 (enterScene3)       : SWE5_CC (R2), despues SW5_I otra vez
--   scene3 (tickDialogue)  : SWE5_GA (una vez), SWE5_GC..GG / SWE5_GB (pickScene3Line)
-- SWE5_EA..EE (cut_4, despues del reloj) y GH/CA/GJ/GK/GL (el SCM nunca las pide) no se mandan.
Stages = {}

local L = Sw5Logic
local TICK_MS = 50

-- GENERATE_RANDOM_INT_IN_RANGE lo hi: [lo, hi)
local function rand(lo, hi) return math.random(lo, hi - 1) end

local function log(...) Instance.log(...) end

-- IS_CHAR_DEAD: tambien es verdadero si el ped no existe (gta-reversed: `!ped || ...`).
local function charDead(ped)
    return not isElement(ped) or isPedDead(ped) or getElementHealth(ped) <= 0
end

-- Respaldo de la muerte (revision, punto 1): el cliente syncer puede dejar un ped con vida <= 0
-- (correccion de daño de client/actors.lua). Lo normal es que MTA mande el aviso de muerte con
-- esa vida; si el servidor ve vida <= 0 y el ped todavia no esta muerto, lo mata aqui con
-- killPed (autoritativo, para todos), atribuido a `killer` si se da.
local function confirmDeath(inst, ped, killer, label)
    if not isElement(ped) or isPedDead(ped) or getElementHealth(ped) > 0 then return end
    local ok = killPed(ped, killer)
    log("kill_fallback", label, "ok=" .. tostring(ok), inst.nick)
end

Stages.TICK_MS = TICK_MS

function Stages.setStage(inst, name)
    inst.stage = name
    log("stage", name, inst.nick)
    Instance.send(inst, "sr5:stage", name)
end

---------------------------------------------------------------------------
-- Creacion: estado que deja sw5_cutscene_1 (COVERAGE §6.1) y etapa scene1
---------------------------------------------------------------------------
local function onEmmetPickupUse(inst, player)
    -- Solo el dueño de la copia: los espectadores que estan en la dimension no lo toman.
    if player ~= inst.player or inst.ended then
        cancelEvent()
        return
    end
    -- sw5_mission_checks: REMOVE_BLIP sw5_emmet_blip y sw5_emmet_marker
    Instance.destroyEl(inst, inst.emmetBlip)
    Instance.destroyEl(inst, inst.emmetArrow)
    inst.emmetBlip, inst.emmetArrow = nil, nil
    log("emmet_pickup", inst.nick)
    -- No reaparece dentro del mismo intento (pendiente 16): se borra despues de entregar el arma.
    local pickup = source
    setTimer(function()
        if isElement(pickup) then destroyElement(pickup) end
    end, 50, 1)
end

-- Policia en moto (SW5.COP): se crea quieto con la copia; la orden de perseguir sale en la largada.
-- No es imprescindible: si falla se informa y la mision sigue.
local function createCop(inst)
    local C = SW5.COP
    local bike = Instance.createVehicle(inst, C.bike, C.x, C.y, C.z, C.rot)
    if not bike then
        log("error", "create_cop_bike", inst.nick)
        return
    end
    local ped = Instance.createPed(inst, C.model, C.x, C.y, C.z + 1.0, C.rot)
    if not ped or not warpPedIntoVehicle(ped, bike, 0) then
        log("error", "create_cop", inst.nick)
        return
    end
    giveWeapon(ped, C.weapon, C.ammo, true)
    inst.cop = { ped = ped, bike = bike }
end

function Stages.setup(inst)
    local c = SW5.COLOR
    local H, E, P, G = SW5.HOUSE_BLIP, SW5.EMMET_BLIP, SW5.EMMET_PICKUP, SW5.SCENE_CAR

    -- ADD_BLIP_FOR_COORD (casa) con COORD_BLIP_APPEARANCE_ENEMY
    inst.houseBlip = Instance.createBlip(inst, H.x, H.y, H.z, 0, c.ENEMY)
    -- ADD_SPRITE_BLIP_FOR_COORD ... RADAR_SPRITE_EMMETGUN
    inst.emmetBlip = Instance.createBlip(inst, E.x, E.y, E.z, E.icon, { 255, 255, 255, 255 })
    -- CREATE_PICKUP_WITH_AMMO COLT45 PICKUP_ON_STREET_SLOW 16 + ADD_BLIP_FOR_PICKUP (MARKER_ONLY)
    inst.emmetPickup = Instance.createPickup(inst, P.x, P.y, P.z, P.weapon, P.ammo)
    inst.emmetArrow = Instance.createMarker(inst, P.x, P.y, P.z + SW5.EMMET_ARROW_OFFSET, "arrow", 1.0, c.DESTINATION)
    -- sw5_generatecar: Greenwood de la escena, sigue existiendo (pendiente 6)
    inst.sceneCar = Instance.createVehicle(inst, SW5.MODEL.GREENWOO, G.x, G.y, G.z, G.rot)

    if not (inst.houseBlip and inst.emmetBlip and inst.emmetPickup and inst.emmetArrow and inst.sceneCar) then
        log("error", "setup_create_failed", inst.nick)
        return false
    end
    addEventHandler("onPickupUse", inst.emmetPickup, function(player) onEmmetPickupUse(inst, player) end, false)
    createCop(inst)

    inst.reds = {}
    inst.sceneMade = false
    inst.helpShown = false
    inst.bar = nil -- la barra resta desde la largada
    Instance.send(inst, "sr5:begin", { health = L.HEALTH_START })
    Stages.setStage(inst, "scene1")
    return true
end

---------------------------------------------------------------------------
-- Falla (sw5_fail_checks / mission_hood5_failed)
---------------------------------------------------------------------------
function Stages.fail(inst, reasonKey, textKey)
    if inst.ended then return end
    inst.ended = true -- deja de correr el tick; la base destruye y recrea la copia
    if textKey then Instance.send(inst, "sr5:text", textKey, 4000) end
    local ok = Instance.reportFailed(inst, reasonKey)
    log("fail", reasonKey, inst.nick, "accepted=" .. tostring(ok))
end

---------------------------------------------------------------------------
-- Largada: la base llama al export srInstanceGo (server/instance.lua) cuando la copia empieza a
-- correr. Respaldo, solo si el hook nunca llega: el jugador lleva GO_FALLBACK_MS sin congelar
-- (la base lo congela durante la cuenta regresiva). La largada ocurre una sola vez por copia.
---------------------------------------------------------------------------
local GO_FALLBACK_MS = 500

function Stages.onGo(inst, now, via)
    if inst.goAt or inst.ended then return false end
    inst.goAt = now
    inst.bar = L.newHealthBar(now, rand)
    log("go", inst.nick, "via=" .. tostring(via))
    Instance.send(inst, "sr5:go")
    if inst.cop and not charDead(inst.cop.ped) then
        Instance.send(inst, "sr5:task", inst.cop.ped, "police_bike", { vehicle = inst.cop.bike })
    end
    -- R2: la llamada de la cinematica excluida suena sobre el juego, con control.
    Instance.send(inst, "sr5:audio", "opening", SW5.SEQ.opening, { thenTexts = SW5.SEQ.openingTexts })
    return true
end

---------------------------------------------------------------------------
-- sw5_scene1
---------------------------------------------------------------------------
local function makeScene1(inst)
    local S = SW5.SCENE1
    inst.sceneMade = true
    -- SET_CREATE_RANDOM_GANG_MEMBERS OFF: el ambiente de la base ya pide solo "civilian".
    Instance.send(inst, "sr5:text", "SW5_J", 4000)

    -- sw5_a_car
    inst.sceneCar2 = Instance.createVehicle(inst, SW5.MODEL.GREENWOO, S.car.x, S.car.y, S.car.z, S.car.rot)

    for i, def in ipairs(S.reds) do
        local ped = Instance.createPed(inst, def.model, def.x, def.y, def.z + 1.0, 0)
        local red = { idx = i - 1, ped = ped, blip = nil, arrow = nil, dead = false }
        if ped then
            giveWeapon(ped, def.weapon, S.ammo, true)
            -- ADD_BLIP_FOR_CHAR: blip rojo y flecha roja encima (BLIP_DISPLAY_BOTH)
            red.blip = Instance.createBlipFor(inst, ped, SW5.COLOR.ENEMY)
            red.arrow = Instance.createArrowFor(inst, ped, SW5.COLOR.ARROW_ENEMY)
        else
            -- IS_CHAR_DEAD es verdadero si el ped no existe: cuenta como muerto.
            log("error", "create_red", i - 1, inst.nick)
        end
        inst.reds[i] = red
    end

    -- REMOVE_BLIP sw5_house_blip
    Instance.destroyEl(inst, inst.houseBlip)
    inst.houseBlip = nil

    -- Empieza la pelea: el policia en moto deja de perseguir y se va.
    if inst.cop and not charDead(inst.cop.ped) then
        Instance.send(inst, "sr5:task", inst.cop.ped, "police_leave", { speed = SW5.COP.leaveSpeed })
        log("cop_leave", inst.nick)
    end

    -- Las tareas las corre el cliente syncer (client/actors.lua).
    for i, red in ipairs(inst.reds) do
        if red.ped then
            local def = S.reds[i]
            Instance.send(inst, "sr5:task", red.ped, "seville_attacker",
                { index = red.idx, home = { x = def.x, y = def.y, z = def.z } })
        end
    end
    log("scene1_made", inst.nick)
end

local function enterPhone(inst, now)
    inst.phoneK = now
    inst.phoneDone = 0
    inst.callHintAt = nil
    log("phone_k", inst.nick, "since_go=" .. (now - (inst.goAt or now)))
    Stages.setStage(inst, "phone")
end

local function tickScene1(inst, now)
    local player = inst.player
    -- Jugador muerto: la base ya maneja la falla y recrea la copia; la barra no sigue restando
    -- (evita un sweet_dead engañoso en la ventana de 3 s).
    if isPedDead(player) then return end
    -- Barra de vida de Sweet: solo en el servidor, mientras dura scene1.
    local changed, depleted = L.healthStep(inst.bar, now, rand)
    if changed then Instance.send(inst, "sr5:health", inst.bar.health) end
    if depleted then
        Stages.fail(inst, "sweet_dead", "SW5_L")
        return
    end

    if getElementDimension(player) ~= inst.dim then return end
    local px, py, pz = getElementPosition(player)
    local S = SW5.SCENE1

    if not inst.sceneMade then
        if not L.inLocate3D(px, py, pz, S.locate) then return end
        makeScene1(inst)
    end

    -- PRINT_HELP SW5_19, una vez, a pie dentro de la caja de la pelea
    if not inst.helpShown and L.inArea3D(px, py, pz, S.helpArea) and not getPedOccupiedVehicle(player) then
        inst.helpShown = true
        Instance.send(inst, "sr5:help", "SW5_19")
    end

    local dead = 0
    for _, red in ipairs(inst.reds) do
        if not red.dead and charDead(red.ped) then
            confirmDeath(inst, red.ped, inst.player, "red" .. red.idx)
            red.dead = true
            -- REMOVE_BLIP: se van el blip y su flecha
            Instance.destroyEl(inst, red.blip)
            Instance.destroyEl(inst, red.arrow)
            red.blip, red.arrow = nil, nil
            log("red_dead", red.idx, inst.nick)
        end
        if red.dead then dead = dead + 1 end
    end
    if dead >= L.RED_COUNT then enterPhone(inst, now) end
end

---------------------------------------------------------------------------
-- sw5_cutscene_2: llamada en juego (etapa phone)
---------------------------------------------------------------------------
local function enterScene2(inst, why, now)
    local P, c = SW5.PICKUP_POINT, SW5.COLOR
    -- ADD_BLIP_FOR_COORD 2764.2725 -1979.4939 12.5394 sw5_house_blip (aspecto por defecto)
    inst.pickupBlip = Instance.createBlip(inst, P.x, P.y, P.z, 0, c.DESTINATION)
    Instance.send(inst, "sr5:text", "SW5_14", 5000)
    log("phone_end", why, inst.nick, "since_k=" .. (now - inst.phoneK))
    Stages.setStage(inst, "scene2")
end

local function tickPhone(inst, now)
    local due
    due, inst.phoneDone = L.phoneDueCues(inst.phoneK, inst.phoneDone, now)
    for _, name in ipairs(due) do
        if name == "ring1" then
            -- Primer timbre: espera si suena otra linea (solo el segundo se pierde, COVERAGE §4 #9).
            Instance.send(inst, "sr5:audio", "ring1", SW5.SEQ.ring, {})
            Instance.send(inst, "sr5:health", false) -- CLEAR_ONSCREEN_COUNTER
        elseif name == "ring2" then
            Instance.send(inst, "sr5:audio", "ring2", SW5.SEQ.ring, { dropIfBusy = true })
        elseif name == "call" then
            Instance.send(inst, "sr5:audio", "phoneCall", SW5.SEQ.phoneCall, { report = true })
        end
        log("phone", name, inst.nick)
    end
    local advance, why = L.phoneShouldAdvance(inst.phoneK, now, inst.callHintAt)
    if advance then enterScene2(inst, why, now) end
end

-- Aviso del cliente: el par SWE5_FA/FB termino. Solo es una pista: se anota la hora si ya paso
-- el piso K+11000; antes del piso se ignora. Nunca cambia la etapa: lo hace tickPhone.
function Stages.onCallHint(inst)
    if inst.ended or inst.stage ~= "phone" or not inst.phoneK or inst.callHintAt then return end
    local now = getTickCount()
    if L.phoneHintAccepted(inst.phoneK, now) then
        inst.callHintAt = now
        log("call_hint", "accepted", inst.nick, "since_k=" .. (now - inst.phoneK))
    elseif not inst.earlyHintLogged then
        inst.earlyHintLogged = true -- una linea por copia: un cliente no puede llenar el log
        log("call_hint", "early_ignored", inst.nick, "since_k=" .. (now - inst.phoneK))
    end
end

---------------------------------------------------------------------------
-- Utilidades de scene2 / scene3
---------------------------------------------------------------------------
-- IS_CAR_DEAD
local function carDead(veh)
    return not isElement(veh) or isVehicleBlown(veh) or getElementHealth(veh) <= 0
end

-- Coordenadas "any means" (LOCATE_CHAR_ANY_MEANS_*): en un vehiculo, las del vehiculo.
local function posOf(ped)
    local veh = getPedOccupiedVehicle(ped)
    if veh then return getElementPosition(veh) end
    return getElementPosition(ped)
end

-- Posicion de Sweet o la novia. Sus bajadas y subidas son tareas del cliente y el estado de
-- vehiculo del servidor puede quedar viejo: solo se usa la posicion del auto si el servidor los
-- ve en el auto que usa el jugador ahora; si no, su propia posicion sincronizada.
local function memberPos(inst, ped)
    local veh = getPedOccupiedVehicle(ped)
    if veh and veh == getPedOccupiedVehicle(inst.player) then return getElementPosition(veh) end
    return getElementPosition(ped)
end

-- Regla R1: SET_VEHICLE_AIR_RESISTANCE_MULTIPLIER -> dragCoeff x factor (no se restaura).
local function scaleDrag(inst, veh, factor, who)
    local handling = getVehicleHandling(veh)
    local orig = handling and handling.dragCoeff
    if type(orig) ~= "number" then
        log("drag", who, "no_handling", inst.nick)
        return false
    end
    local ok = setVehicleHandling(veh, "dragCoeff", orig * factor)
    log("drag", who, ("%.3f"):format(orig), ("%.3f"):format(orig * factor), "ok=" .. tostring(ok), inst.nick)
    return ok
end

---------------------------------------------------------------------------
-- Cola de dialogo (play_audio = 0 del SCM, visto desde el servidor)
-- La cola es del cliente: el servidor la da por ocupada desde que manda una linea hasta el
-- aviso sr5:audioDone de esa misma linea, o hasta AUDIO_BUSY_CAP_MS. El aviso solo libera la
-- cola de dialogo: no toca etapas ni la llegada.
---------------------------------------------------------------------------
local AUDIO_BUSY_CAP_MS = 20000

local function audioIdle(inst, now)
    local busy = inst.audioBusy
    if busy and now >= busy.cap then inst.audioBusy = nil end
    return inst.audioBusy == nil
end

-- r2: la linea es SWE5_CC (regla R2, no suena en el salto del SCM).
local function playLine(inst, now, keys, opts, r2)
    inst.audioSeq = (inst.audioSeq or 0) + 1
    local id = "sc3_" .. inst.audioSeq
    opts.report = true
    inst.audioBusy = { id = id, cap = now + AUDIO_BUSY_CAP_MS, r2 = r2 or false }
    Instance.send(inst, "sr5:audio", id, keys, opts)
    log("line", keys[1], inst.nick)
end

function Stages.onAudioHint(inst, seqId)
    local busy = inst.audioBusy
    if busy and busy.id == seqId then inst.audioBusy = nil end
end

---------------------------------------------------------------------------
-- sw5_scene2: compuerta del auto
---------------------------------------------------------------------------
-- Pista del cliente: base del modelo del auto que usa (getElementDistanceFromCentreOfMassToBaseOfModel
-- es solo de cliente). Solo se usa para la altura de SET_CAR_COORDINATES en T0, acotada a 0..2.
function Stages.onCarBase(inst, veh, value)
    if inst.stage ~= "scene2" then return end
    inst.carBase = {
        veh = veh,
        value = L.clampCarBase(value, SW5.CAR_BASE_DEFAULT, SW5.CAR_BASE_MIN, SW5.CAR_BASE_MAX),
    }
end

local function createSentinel(inst, i, def)
    local S = SW5.SENTINEL
    local car = Instance.createVehicle(inst, S.model, def.x, def.y, def.z, def.rot)
    if not car then
        log("error", "create_sentinel", i - 1, inst.nick)
        return nil
    end
    local driver = Instance.createPed(inst, S.driverModel, def.x, def.y, def.z + 1.0, def.rot)
    if driver and warpPedIntoVehicle(driver, car, 0) then
        giveWeapon(driver, S.weapon, S.ammo, true)
    else
        log("error", "sentinel_driver", i - 1, inst.nick)
    end
    -- SET_CAR_HEALTH 2500 (el cliente syncer la repone: el paquete de creacion la corta en 2047.5)
    setElementHealth(car, S.health)
    scaleDrag(inst, car, SW5.DRAG.sentinel, "sentinel" .. (i - 1))
    return { idx = i - 1, car = car, driver = driver }
end

local function createMember(inst, def, veh, label)
    local ped = Instance.createPed(inst, def.model, def.x, def.y, def.z + 1.0, 0)
    if not ped then
        log("error", "create_" .. label, inst.nick)
        return nil
    end
    -- WARP_CHAR_INTO_CAR_AS_PASSENGER (asiento SCM + 1)
    if not warpPedIntoVehicle(ped, veh, def.seat) then log("error", "warp_" .. label, inst.nick) end
    return ped
end

-- T0: la compuerta paso. Estado del salto de sw5_cutscene_3 (COVERAGE §6.2), sin fundido y sin
-- quitar el control. Todo en este tick del servidor.
local function enterScene3(inst, veh, now)
    local player = inst.player
    local c = SW5.COLOR
    inst.t0 = now

    -- Auto del jugador: SET_CAR_COORDINATES + SET_CAR_HEADING 0.0, quieto (freno de mano en el SCM).
    local C = SW5.PLAYER_CAR
    local base = SW5.CAR_BASE_DEFAULT
    if inst.carBase and inst.carBase.veh == veh then base = inst.carBase.value end
    setElementVelocity(veh, 0, 0, 0)
    if type(setElementAngularVelocity) == "function" then pcall(setElementAngularVelocity, veh, 0, 0, 0) end
    setElementPosition(veh, C.x, C.y, C.z + base)
    setElementRotation(veh, 0, 0, C.rot)
    setElementVelocity(veh, 0, 0, 0)
    -- Asientos de pasajero SCM 0 y 1 (MTA 1 y 2) ocupados -> DELETE_CHAR
    for seat = 1, 2 do
        local occupant = getVehicleOccupant(veh, seat)
        if occupant and isElement(occupant) then
            if getElementType(occupant) == "ped" then destroyElement(occupant) else removePedFromVehicle(occupant) end
        end
    end

    -- CLEAR_AREA_OF_CARS (solo ambiente de la copia; el auto del jugador se queda)
    local B = SW5.CLEAR_BOX
    local cleared = Instance.clearAmbientCars(inst, function(x, y, z) return L.inArea3D(x, y, z, B) end, veh)

    -- Sentinels Seville quietos en la pose final de 153 / 154 (R3: no se piden las grabaciones)
    inst.sentinels = {}
    for i, def in ipairs(SW5.SENTINELS) do inst.sentinels[i] = createSentinel(inst, i, def) or false end

    -- Sweet y la novia, sentados (fin de la escena: grupo del jugador, pistola 9999 a Sweet)
    inst.sweet = createMember(inst, SW5.SWEET, veh, "sweet")
    inst.girl = createMember(inst, SW5.GIRL, veh, "girl")
    if inst.sweet then giveWeapon(inst.sweet, SW5.SWEET.weapon, SW5.SWEET.ammo, true) end
    inst.members = { sweet = { lost = false }, girl = { lost = false } }

    -- R1: GET_CAR_CHAR_IS_USING scplayer -> dragCoeff x 5.0 (si va a pie, ninguno)
    local using = getPedOccupiedVehicle(player)
    if using then scaleDrag(inst, using, SW5.DRAG.playerCar, "player") end

    -- REMOVE_BLIP sw5_house_blip (recogida) + ADD_BLIP_FOR_COORD llegada + SET_BLIP_AS_FRIENDLY
    Instance.destroyEl(inst, inst.pickupBlip)
    inst.pickupBlip = nil
    local F = SW5.FINISH
    inst.finishBlip = Instance.createBlip(inst, F.x, F.y, F.z, 0, c.FRIENDLY)

    -- Ordenes del cliente syncer (client/chase.lua). Los tiempos de los Sentinels cuentan desde
    -- que llega la orden (T0 + latencia).
    if inst.sweet then
        Instance.send(inst, "sr5:task", inst.sweet, "group_member", { role = "sweet", speaker = 2, seat = SW5.SWEET.seat })
    end
    if inst.girl then
        Instance.send(inst, "sr5:task", inst.girl, "group_member", { role = "girl", speaker = 3, seat = SW5.GIRL.seat })
    end
    for _, s in ipairs(inst.sentinels) do
        if s and s.driver then
            Instance.send(inst, "sr5:task", s.driver, "sentinel_driver", { role = s.idx, vehicle = s.car })
        end
    end

    -- CLEAR_PRINTS + PRINT SW5_I 5000 1. SWE5_CC suena encima (R2); su subtitulo tapa SW5_I, que
    -- se vuelve a mostrar cuando termina la linea.
    Instance.send(inst, "sr5:text", "SW5_I", 5000)
    inst.lines = L.newScene3Lines(SW5.INSULTS, SW5.NONINSULTS)
    inst.canPlayAt = now + L.DIALOGUE.firstDelayMs -- can_play_audio_now_time = TIMERA + 3000
    playLine(inst, now, SW5.SEQ.pickup, { thenTexts = { { "SW5_I", 5000 } } }, true)

    log("t0", inst.nick, "model=" .. getElementModel(veh), ("base=%.2f"):format(base), "cleared=" .. cleared,
        "since_go=" .. (now - (inst.goAt or now)))
    Stages.setStage(inst, "scene3")
end

function Stages.tickScene2(inst, now)
    local player = inst.player
    if isPedDead(player) or getElementDimension(player) ~= inst.dim then return end
    local veh = getPedOccupiedVehicle(player) -- IS_CHAR_IN_ANY_CAR + STORE_CAR_CHAR_IS_IN
    -- Solo como conductor: de pasajero, el asiento SCM 0 / 1 se vaciaria con el jugador adentro
    -- y el auto "que usa" quedaria sin dragCoeff x 5 (en el SCM el jugador siempre maneja).
    if not veh or getPedOccupiedVehicleSeat(player) ~= 0 then return end
    local x, y, z = getElementPosition(veh)
    if not L.inLocate3D(x, y, z, SW5.PICKUP_LOCATE) or carDead(veh) then return end
    local gate = L.pickupGate(getVehicleMaxPassengers(veh), getElementModel(veh), SW5.PICKUP_MODELS)
    if gate == "small" then
        if not inst.getNewCarShown then -- sw5_getNewCar: una sola vez
            inst.getNewCarShown = true
            Instance.send(inst, "sr5:text", "SW5_G", 5000)
        end
    elseif gate == "class" then
        if now >= (inst.wrongClassAt or 0) then -- PRINT_NOW sw5_16 1000 1, cada frame
            inst.wrongClassAt = now + SW5.WRONG_CLASS_REPEAT_MS
            Instance.send(inst, "sr5:text", "sw5_16", 1000)
        end
    else
        enterScene3(inst, veh, now)
    end
end

---------------------------------------------------------------------------
-- sw5_scene3
---------------------------------------------------------------------------
-- "Que mal manejas" (una vez) e insultos / comentarios (lineas 1437-1510).
local function tickDialogue(inst, now, pveh, px, py, pz)
    if not inst.badDrivingDone and pveh and getElementHealth(pveh) < SW5.BAD_DRIVING_HEALTH
        and audioIdle(inst, now) and now > inst.canPlayAt then
        inst.badDrivingDone = true -- youre_shit = 1
        inst.canPlayAt = now + L.DIALOGUE.badDrivingDelayMs
        playLine(inst, now, SW5.SEQ.badDriving, {})
    end
    if not (now > inst.canPlayAt) then return end

    local s0, s1 = inst.sentinels[1], inst.sentinels[2]
    local bothAlive = (s0 and s1 and not carDead(s0.car) and not carDead(s1.car)) and true or false
    local near = false
    if bothAlive and pveh then -- LOCATE_CHAR_IN_CAR_CAR_3D: a pie es falso
        local R = SW5.INSULT_RANGE
        for _, s in ipairs({ s0, s1 }) do
            local x, y, z = getElementPosition(s.car)
            if L.inLocate3D(px, py, pz, { x = x, y = y, z = z, rx = R.rx, ry = R.ry, rz = R.rz }) then near = true end
        end
    end
    local key = L.pickScene3Line(inst.lines, rand, bothAlive, near)
    inst.canPlayAt = now + L.DIALOGUE.retryMs
    if not key then return end
    if audioIdle(inst, now) then
        playLine(inst, now, { key }, { dropIfBusy = true })
    elseif inst.audioBusy.r2 then
        -- Suena SWE5_CC, que en el salto del SCM no existe (R2): la linea espera en la cola del
        -- cliente en lugar de perderse.
        playLine(inst, now, { key }, {})
    else
        log("line_lost", key, inst.nick) -- como en el SCM: se pierde y queda gastada
    end
end

-- Sweet o la novia perdidos y recuperados (lineas 1514-1569). No es una falla.
local MEMBER_ORDER = {
    { key = "sweet", other = "girl", text = "sw5_T" },
    { key = "girl", other = "sweet", text = "sw5_U" },
}

local function tickMembers(inst, px, py, pz)
    local c = SW5.COLOR
    for _, def in ipairs(MEMBER_ORDER) do
        local ped = inst[def.key]
        local m = inst.members[def.key]
        local x, y, z = memberPos(inst, ped)
        local event = L.memberStep(m, getDistanceBetweenPoints3D(px, py, pz, x, y, z), x - px, y - py)
        if event == "lost" then
            Instance.send(inst, "sr5:text", def.text, 4000)
            -- ADD_BLIP_FOR_CHAR + SET_BLIP_AS_FRIENDLY: blip y flecha azules
            if not m.blip then m.blip = Instance.createBlipFor(inst, ped, c.FRIENDLY) end
            if not m.arrow then m.arrow = Instance.createArrowFor(inst, ped, c.ARROW_FRIENDLY) end
            Instance.destroyEl(inst, inst.finishBlip)
            inst.finishBlip = nil
            Instance.send(inst, "sr5:task", ped, "member_state", { lost = true })
            log("member_lost", def.key, inst.nick)
        elseif event == "back" then
            Instance.destroyEl(inst, m.blip)
            Instance.destroyEl(inst, m.arrow)
            m.blip, m.arrow = nil, nil
            if not inst.members[def.other].lost and not inst.finishBlip then
                local F = SW5.FINISH
                -- Como el SCM: al volver Sweet el blip se crea sin SET_BLIP_AS_FRIENDLY.
                local color = def.key == "girl" and c.FRIENDLY or c.DESTINATION
                inst.finishBlip = Instance.createBlip(inst, F.x, F.y, F.z, 0, color)
            end
            Instance.send(inst, "sr5:task", ped, "member_state", { lost = false })
            log("member_back", def.key, inst.nick)
        end
    end
end

-- Los Sentinels se van (lineas 1607-1629): una vez, con Sweet y la novia vivos.
local function tickLeave(inst, px, py, pz)
    if inst.sentinelsLeft or not L.inLocate3D(px, py, pz, SW5.LEAVE_LOCATE) then return end
    inst.sentinelsLeft = true
    for i = 1, #SW5.SENTINELS do
        local s = inst.sentinels[i]
        if s and s.driver and not s.driverDead and not carDead(s.car) then
            Instance.send(inst, "sr5:task", s.driver, "sentinel_leave", { speed = SW5.LEAVE_SPEED })
        end
    end
    log("sentinels_leave", inst.nick)
end

-- Conductores Sentinel: el SCM no los revisa; solo se confirma su muerte (revision, punto 1).
local function tickSentinelDrivers(inst)
    for _, s in ipairs(inst.sentinels) do
        if s and s.driver and not s.driverDead and charDead(s.driver) then
            s.driverDead = true
            confirmDeath(inst, s.driver, nil, "sentinel_driver" .. s.idx)
        end
    end
end

-- mission_hood5_passed. Unico camino a reportCompleted: solo desde tickArrival (tick del servidor).
local function complete(inst, ms)
    if inst.ended then return end
    inst.ended = true
    local ok = Instance.reportCompleted(inst)
    log("complete", inst.nick, "since_go=" .. tostring(ms), "accepted=" .. tostring(ok))
    if ok then Instance.send(inst, "sr5:passed") end -- PLAY_MISSION_PASSED_TUNE 1
end

local function memberCtx(inst, key)
    local ped = inst[key]
    if charDead(ped) then return { alive = false } end
    local x, y, z = memberPos(inst, ped)
    return { alive = true, lost = inst.members[key].lost, x = x, y = y, z = z }
end

-- Llegada (COVERAGE §5): todo con datos del servidor; R6 aparte.
local function tickArrival(inst, now, px, py, pz)
    local ctx = {
        stage = inst.stage,
        player = { alive = not isPedDead(inst.player), x = px, y = py, z = pz },
        sweet = memberCtx(inst, "sweet"),
        girl = memberCtx(inst, "girl"),
    }
    if not L.arrivalReady(ctx, SW5.FINISH_PLAYER, SW5.FINISH_PEDS) then
        inst.tooFastLogged = false
        return
    end
    local ok, ms = L.minTimeOk(inst.goAt, now)
    if not ok then
        -- R6: no se completa ni se falla; el chequeo sigue corriendo.
        if not inst.tooFastLogged then
            inst.tooFastLogged = true
            log("too_fast", tostring(ms), inst.nick)
        end
        return
    end
    complete(inst, ms)
end

function Stages.tickScene3(inst, now)
    local player = inst.player
    if isPedDead(player) then return end -- la muerte del jugador la maneja la base
    -- sw5_fail_checks (sw5_sweet_alive = 1 desde T0): Sweet primero, como el SCM.
    if charDead(inst.sweet) then
        confirmDeath(inst, inst.sweet, nil, "sweet")
        Stages.fail(inst, "sweet_dead", "SW5_L")
        return
    end
    if charDead(inst.girl) then
        confirmDeath(inst, inst.girl, nil, "girl")
        Stages.fail(inst, "girl_dead", "SW5_M")
        return
    end
    if getElementDimension(player) ~= inst.dim then return end
    local px, py, pz = posOf(player)
    tickDialogue(inst, now, getPedOccupiedVehicle(player), px, py, pz)
    tickMembers(inst, px, py, pz)
    tickSentinelDrivers(inst)
    tickLeave(inst, px, py, pz)
    tickArrival(inst, now, px, py, pz)
end

---------------------------------------------------------------------------
-- Tick
---------------------------------------------------------------------------
function Stages.tick(inst)
    if inst.ended then return end
    local player = inst.player
    if not isElement(player) then return end
    local now = getTickCount()
    if not inst.goAt then
        -- Respaldo del hook srInstanceGo: cuenta regresiva = jugador congelado por la base.
        if isElementFrozen(player) then
            inst.unfrozenSince = nil
            return
        end
        inst.unfrozenSince = inst.unfrozenSince or now
        if now - inst.unfrozenSince < GO_FALLBACK_MS then return end
        Stages.onGo(inst, now, "fallback")
    end
    if inst.stage == "scene1" then
        tickScene1(inst, now)
    elseif inst.stage == "phone" then
        tickPhone(inst, now)
    elseif inst.stage == "scene2" then
        Stages.tickScene2(inst, now)
    elseif inst.stage == "scene3" then
        Stages.tickScene3(inst, now)
    end
end
