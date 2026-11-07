-- Logica pura de "Sweet's Girl" (sin APIs de MTA). Lua 5.1. La usan el servidor, el cliente y
-- los tests (speedrun/tests/run.js). Cada funcion reproduce un bloque del SCM (COVERAGE.md).
-- rand(lo, hi) = GENERATE_RANDOM_INT_IN_RANGE: entero en [lo, hi) (hi excluido).
Sw5Logic = {}

---------------------------------------------------------------------------
-- Barra de vida de Sweet (sw5_scene1, lineas 670-683; cut_flag 8, lineas 594-605)
---------------------------------------------------------------------------
Sw5Logic.HEALTH_START = 100
Sw5Logic.DROP_MIN, Sw5Logic.DROP_MAX = 2500, 6000 -- rand[2500, 6000) ms entre restas
Sw5Logic.LOSS_MIN, Sw5Logic.LOSS_MAX = 2, 4       -- rand[2, 4) por resta

-- Barra en 100; la primera resta en rand[2500, 6000) ms desde `now` (la largada).
function Sw5Logic.newHealthBar(now, rand)
    return { health = Sw5Logic.HEALTH_START, nextDrop = now + rand(Sw5Logic.DROP_MIN, Sw5Logic.DROP_MAX) }
end

-- Un chequeo (un frame del SCM). Devuelve changed, depleted.
-- Orden del SCM: primero el proximo drop_time (TIMERA + rand), despues la resta.
function Sw5Logic.healthStep(bar, now, rand)
    if not (now > bar.nextDrop) then return false, false end
    bar.nextDrop = now + rand(Sw5Logic.DROP_MIN, Sw5Logic.DROP_MAX)
    bar.health = bar.health - rand(Sw5Logic.LOSS_MIN, Sw5Logic.LOSS_MAX)
    if bar.health <= 0 then
        bar.health = 0
        return true, true
    end
    return true, false
end

---------------------------------------------------------------------------
-- Etapa phone (sw5_cutscene_2, lineas 862-931). Tiempos desde K = tick del 5.o Seville muerto.
---------------------------------------------------------------------------
Sw5Logic.PHONE = {
    cues = {
        { at = 1500, name = "ring1" }, -- MOBRING + CLEAR_ONSCREEN_COUNTER
        { at = 4000, name = "ring2" }, -- MOBRING
        { at = 6500, name = "phone" }, -- TASK_USE_MOBILE_PHONE TRUE (sin animacion: adapted)
        { at = 9000, name = "call" },  -- SWE5_FA, SWE5_FB
    },
    floor = 11000, -- desde aqui se acepta el aviso "audio terminado" del cliente
    cap = 29000,   -- sin aviso, el servidor avanza solo
}

-- Indices de las marcas que vencen en (done, now]: devuelve la lista de nombres y el nuevo `done`.
function Sw5Logic.phoneDueCues(K, done, now)
    local due = {}
    local cues = Sw5Logic.PHONE.cues
    local i = done + 1
    while cues[i] and now >= K + cues[i].at do
        due[#due + 1] = cues[i].name
        done = i
        i = i + 1
    end
    return due, done
end

-- El aviso del cliente solo vale si llega desde el piso.
function Sw5Logic.phoneHintAccepted(K, now)
    return now >= K + Sw5Logic.PHONE.floor
end

-- Avanza a scene2: aviso aceptado (llegado en o despues del piso) o tope del servidor.
function Sw5Logic.phoneShouldAdvance(K, now, hintAt)
    if now >= K + Sw5Logic.PHONE.cap then return true, "cap" end
    if hintAt and hintAt >= K + Sw5Logic.PHONE.floor and now >= hintAt then return true, "hint" end
    return false
end

---------------------------------------------------------------------------
-- sw5_ped_actions (lineas 1985-2162)
---------------------------------------------------------------------------
Sw5Logic.RED_COUNT = 5
Sw5Logic.FAR = 99999.0

-- Turno: sw5_this_red ++, y a 0 al llegar a 5 (orden 1, 2, 3, 4, 0).
function Sw5Logic.nextRed(this)
    this = this + 1
    if this == Sw5Logic.RED_COUNT then this = 0 end
    return this
end

-- nearest_red_1/2 empiezan en 0 (variables sin asignar) y nearest_range_1/2 en 99999.0.
function Sw5Logic.newNearest()
    return { red1 = 0, range1 = Sw5Logic.FAR, red2 = 0, range2 = Sw5Logic.FAR }
end

-- Algoritmo incremental del SCM, tal cual (lineas 2009-2032), para un red vivo.
function Sw5Logic.nearestAlive(n, idx, dist)
    if n.red1 ~= idx then
        if dist < n.range1 then
            n.red2 = n.red1
            n.range2 = n.range1
            n.range1 = dist
            n.red1 = idx
        end
    else
        n.range1 = dist
    end
    if n.red2 ~= idx then
        if n.red1 ~= idx then
            if dist < n.range2 then
                n.red2 = idx
                n.range2 = dist
            end
        end
    else
        n.range2 = dist
    end
end

-- Red muerto (lineas 2149-2161).
function Sw5Logic.nearestDead(n, idx)
    if idx == n.red1 then
        n.red1 = n.red2
        n.range1 = n.range2
        n.red2 = 0
        n.range2 = Sw5Logic.FAR
    end
    if idx == n.red2 then
        n.red2 = 0
        n.range2 = Sw5Logic.FAR
    end
end

function Sw5Logic.isNearest(n, idx)
    return idx == n.red1 or idx == n.red2
end

-- GET_HEADING_FROM_VECTOR_2D: 0 = +Y, sentido antihorario, en [0, 360).
local atan2 = math.atan2 or math.atan -- Lua 5.1 (MTA) / 5.3 (fengari, tests)

function Sw5Logic.headingFromVector(x, y)
    local h = math.deg(atan2(-x, y))
    if h < 0 then h = h + 360.0 end
    if h >= 360.0 then h = h - 360.0 end
    return h
end

function Sw5Logic.distance2D(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

Sw5Logic.DIVE_MIN_SPEED = 5.0

-- Esquivar el auto (lineas 2034-2079). carSpeed en unidades de GET_CAR_SPEED (|v| MTA x 50).
-- randOffset = GENERATE_RANDOM_FLOAT_IN_RANGE -0.2 0.2 (solo se usa si la velocidad pasa de 5).
-- La resta de headings va sin normalizar, como en el SCM (el ajuste a 180 esta comentado).
function Sw5Logic.shouldDive(px, py, pz, rx, ry, rz, carSpeed, carHeading, randOffset)
    if not (carSpeed > Sw5Logic.DIVE_MIN_SPEED) then return false end
    local threshold = carSpeed * 1.6 + randOffset
    local dist = Sw5Logic.distance2D(px, py, rx, ry)
    if not (dist < threshold) then return false end
    if not (math.abs(pz - rz) < 1.0) then return false end
    local angle = Sw5Logic.headingFromVector(rx - px, ry - py)
    return math.abs(angle - carHeading) < 5.0
end

-- SET_CHAR_ACCURACY / SET_CHAR_SHOOT_RATE = 60 + 6 x muertos (lineas 803-819).
function Sw5Logic.accuracyFor(deadCount)
    return 60 + 6 * deadCount
end

---------------------------------------------------------------------------
-- Zonas (LOCATE_CHAR_ANY_MEANS_3D e IS_CHAR_IN_AREA_3D)
---------------------------------------------------------------------------
-- LOCATE_*_3D: |d| < radio en cada eje.
function Sw5Logic.inLocate3D(px, py, pz, c)
    return math.abs(px - c.x) < c.rx and math.abs(py - c.y) < c.ry and math.abs(pz - c.z) < c.rz
end

-- IS_CHAR_IN_AREA_3D: dentro de la caja entre las dos esquinas (en cualquier orden).
function Sw5Logic.inArea3D(px, py, pz, a)
    local function between(v, p, q)
        if p > q then p, q = q, p end
        return v >= p and v <= q
    end
    return between(px, a.x1, a.x2) and between(py, a.y1, a.y2) and between(pz, a.z1, a.z2)
end

---------------------------------------------------------------------------
-- sw5_scene2: compuerta del auto (lineas 1035-1057)
---------------------------------------------------------------------------
-- "small": menos de 2 pasajeros (SW5_G, una vez); "class": clase no admitida (sw5_16);
-- "ok": pasa la compuerta. allowed = SW5.PICKUP_MODELS.
function Sw5Logic.pickupGate(maxPassengers, model, allowed)
    if type(maxPassengers) ~= "number" or maxPassengers < 2 then return "small" end
    if allowed[model] then return "ok" end
    return "class"
end

-- Base del auto del jugador para SET_CAR_COORDINATES: dato del cliente, acotado; sin dato, el defecto.
function Sw5Logic.clampCarBase(value, default, lo, hi)
    if type(value) ~= "number" or value ~= value then return default end
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

---------------------------------------------------------------------------
-- Sentinels desde T0 (salto del SCM, COVERAGE §6.2 y filas de conductores y ataque)
---------------------------------------------------------------------------
Sw5Logic.SENTINEL = {
    waitMs = 1500,      -- TASK_CAR_TEMP_ACTION ... TEMPACT_WAIT 1500 (los dos)
    reverseMs = 1000,   -- [1]: TEMPACT_REVERSE_RIGHT 1000 despues de la espera
    reissueMs = 500,    -- sustituto de BLOCKPLAYER/RAMPLAYER: setPedDriveTo renovado cada 500 ms
    cruiseSpeed = 60.0, -- SET_CAR_CRUISE_SPEED 60.0
}

-- Fase de un Sentinel a `elapsed` ms de T0: "wait", "reverse" (solo [1]) o "attack".
function Sw5Logic.sentinelPhase(role, elapsed)
    local S = Sw5Logic.SENTINEL
    if elapsed < S.waitMs then return "wait" end
    if role == 1 and elapsed < S.waitMs + S.reverseMs then return "reverse" end
    return "attack"
end

-- Alcance del Sentinel [1] (lineas 1572-1605). st = { chase = 1 } desde T0.
-- inRange: jugador dentro de 50/50/20 del conductor [1]. Devuelve "save" (guardar posicion y
-- heading del jugador ahora), "try" (vencieron los 800 ms: probar el teletransporte) o nil.
Sw5Logic.CATCHUP = { rx = 50.0, ry = 50.0, rz = 20.0, delayMs = 800, forwardSpeed = 25.0 }

function Sw5Logic.catchupStep(st, now, inRange)
    if st.chase == 1 then
        if not inRange then
            st.chase = 2
            st.at = now + Sw5Logic.CATCHUP.delayMs
            return "save"
        end
    elseif st.chase == 2 then
        if now > st.at then return "try" end
    end
    return nil
end

-- Teletransporte hecho: sw5_chase_car_created = 1.
function Sw5Logic.catchupDone(st)
    st.chase = 1
    st.at = nil
end

-- Direccion de avance para un heading GTA (0 = +Y, antihorario).
function Sw5Logic.forwardFromHeading(h)
    local r = math.rad(h)
    return -math.sin(r), math.cos(r)
end

---------------------------------------------------------------------------
-- Grupo del jugador (emulado): perdido a mas de 60 m en 3D; vuelve dentro de 6 x 6 en 2D
---------------------------------------------------------------------------
Sw5Logic.GROUP = { lostDist = 60.0, regain = 6.0 }

-- m = { lost = false }. Devuelve "lost", "back" o nil.
function Sw5Logic.memberStep(m, dist3D, dx, dy)
    local G = Sw5Logic.GROUP
    if not m.lost then
        if dist3D > G.lostDist then
            m.lost = true
            return "lost"
        end
    elseif math.abs(dx) < G.regain and math.abs(dy) < G.regain then
        m.lost = false
        return "back"
    end
    return nil
end

---------------------------------------------------------------------------
-- Dialogo de scene3 (lineas 1437-1510)
---------------------------------------------------------------------------
Sw5Logic.DIALOGUE = { firstDelayMs = 3000, retryMs = 7500, badDrivingDelayMs = 6000 }

-- Copias de insult[] y noninsult[] (cada linea se gasta al elegirse).
function Sw5Logic.newScene3Lines(insults, noninsults)
    local st = { insult = {}, noninsult = {} }
    for i = 1, 5 do st.insult[i] = insults[i] or false end
    for i = 1, 2 do st.noninsult[i] = noninsults[i] or false end
    return st
end

-- WHILE list[ab_int] = 0: ab_int++, ab_count++, vuelta a 0 pasado wrapMax, salida pasado countMax.
-- list es 1-based (list[i + 1] = SCM [i]); false = 0.
local function pickFrom(list, start, wrapMax, countMax)
    local i, count = start, 0
    while not list[i + 1] do
        i = i + 1
        count = count + 1
        if i > wrapMax then i = 0 end
        if count > countMax then return nil end
    end
    local key = list[i + 1]
    list[i + 1] = false
    return key
end

-- Una eleccion (TIMERA > can_play_audio_now_time). bothAlive: los dos Sentinels vivos;
-- near: jugador en un auto y a menos de 20/20/10 de alguno. Devuelve la clave o nil; el que
-- llama pone can_play_audio_now_time = ahora + 7500 en todos los casos.
function Sw5Logic.pickScene3Line(st, rand, bothAlive, near)
    if bothAlive then
        if near then return pickFrom(st.insult, rand(0, 5), 4, 4) end
        return pickFrom(st.noninsult, rand(0, 1), 1, 2)
    end
    return pickFrom(st.noninsult, rand(0, 2), 1, 2)
end

---------------------------------------------------------------------------
-- Reproductor de dialogos (sweet5_audio CASE 1..4, lineas 2525-2637). Lo usa client/text_audio.lua.
---------------------------------------------------------------------------
Sw5Logic.AUDIO_PLAYER = {
    loadTimeoutMs = 5000,    -- sin HAS_MISSION_AUDIO_LOADED en 5 s -> solo subtitulo
    finishTimeoutMs = 30000, -- tope de seguridad si HAS_MISSION_AUDIO_FINISHED nunca llega
    subtitleOnlyMs = 3000,   -- linea sin audio: subtitulo 3 s
    lineTextMs = 10000,      -- PRINT $audio_text 10000 1
}

-- Una secuencia nueva (play_audio = N): "start" si no suena nada, "drop" si suena otra y la
-- linea se pierde (play_audio pisado: CASE 4 lo deja en 0), "queue" si espera su turno.
function Sw5Logic.audioAdmit(busy, dropIfBusy)
    if not busy then return "start" end
    if dropIfBusy then return "drop" end
    return "queue"
end

-- Un paso de la linea en curso. line = { phase = "loading"|"playing"|"subtitle", since = ms }.
-- probe = { loaded, finished, speakerDead } (lo que el cliente pregunto a Neon en este paso).
-- Devuelve "play" (cargada: PLAY_MISSION_AUDIO + PRINT), "load_timeout" (pasar a solo
-- subtitulo), "end" (CASE 2 -> 3: termino, o murio el hablante, o vencio el subtitulo) o nil.
function Sw5Logic.lineStep(line, now, probe)
    local P = Sw5Logic.AUDIO_PLAYER
    local elapsed = now - line.since
    if line.phase == "loading" then
        if probe.loaded then return "play" end
        if elapsed >= P.loadTimeoutMs then return "load_timeout" end
    elseif line.phase == "playing" then
        -- CASE 2: HAS_MISSION_AUDIO_FINISHED, o DOES_CHAR_EXIST + IS_CHAR_DEAD del hablante.
        if probe.finished or probe.speakerDead or elapsed >= P.finishTimeoutMs then return "end" end
    elseif line.phase == "subtitle" then
        if elapsed >= P.subtitleOnlyMs then return "end" end
    end
    return nil
end

---------------------------------------------------------------------------
-- Llegada (COVERAGE §5, exito) y regla R6
---------------------------------------------------------------------------
Sw5Logic.MIN_FINISH_MS = 60000

-- ctx = { stage, player = { alive, x, y, z }, sweet = { alive, lost, x, y, z }, girl = { ... } }.
-- Devuelve true, o false y el motivo. No mira el tiempo (R6 aparte).
function Sw5Logic.arrivalReady(ctx, playerBox, pedsBox)
    if ctx.stage ~= "scene3" then return false, "stage" end
    local p = ctx.player
    if not (p and p.alive) then return false, "player_dead" end
    for _, who in ipairs({ "sweet", "girl" }) do
        local c = ctx[who]
        if not (c and c.alive) then return false, who .. "_dead" end
        if c.lost then return false, who .. "_lost" end
    end
    if not Sw5Logic.inLocate3D(p.x, p.y, p.z, playerBox) then return false, "player_far" end
    for _, who in ipairs({ "sweet", "girl" }) do
        local c = ctx[who]
        if not Sw5Logic.inLocate3D(c.x, c.y, c.z, pedsBox) then return false, who .. "_far" end
    end
    return true
end

-- R6: tiempo desde la largada de la copia. Devuelve ok y los ms transcurridos.
function Sw5Logic.minTimeOk(goAt, now)
    if type(goAt) ~= "number" then return false, nil end
    local ms = now - goAt
    return ms >= Sw5Logic.MIN_FINISH_MS, ms
end

---------------------------------------------------------------------------
-- Respuesta de daño de GTA para los peds de la mision (session B, fix 1)
-- MTA/Neon construye los peds de script como CPlayerPed, asi que la calculadora de daño de GTA
-- los trata como jugadores (gta-reversed, CPedDamageResponseCalculator):
--   AccountForPedDamageStats (0x4AD430): dano x 0.33 (jugador) en lugar de x defendWeakness
--     (STAT_GANG2 de FAM1/FAM2 = 1.0, pedstats.dat);
--   ComputeWillForceDeath (0x4AD610): `IsPlayer() || bNoCriticalHits` -> el tiro a la cabeza
--     nunca mata. Neon no redirige esos IsPlayer (solo los de tareas, peleas y eventos).
-- El cliente syncer pasa la vida que tenia el ped antes del golpe (healthBefore: la ultima que
-- conoce, sembrada en la preparacion y actualizada despues de cada golpe), la que dejo GTA
-- (healthAfter) y lo que GTA dice que aplico (loss, ya con el x 0.33). Aqui se calcula la vida
-- que habria dejado GTA con un CPed comun (CREATE_CHAR):
--   - golpe critico (cabeza con arma de fuego, critical hits activos): en un vehiculo, siempre;
--     a pie, si dispara un jugador (se asume mira libre o apuntando a la cabeza); si dispara
--     otro ped, rifles siempre y el resto 1 de cada 8 (GetRandomNumber() % 8 == 0);
--   - si no, solo para armas de fuego (22-34, 38) y cuerpo a cuerpo (0-15):
--     healthBefore - loss / 0.33 x defendWeakness; menos de 1 de vida = muerto. Explosiones,
--     caidas, fuego, choques de vehiculo y ahogo quedan como los informa MTA (revision).
-- Con chaleco no se reescala (los peds de la mision no tienen): solo el golpe critico.
-- Devuelve la vida nueva y el motivo ("critical" | "scaled"), o nil si no hay nada que cambiar.
---------------------------------------------------------------------------
Sw5Logic.PLAYER_DAMAGE_FACTOR = 0.33
Sw5Logic.PED_DEFEND_WEAKNESS = 1.0
Sw5Logic.BODYPART_HEAD = 9
-- PISTOL..MINIGUN de ComputeWillForceDeath (ids de arma de MTA; UZI_DRIVEBY usa 28/32)
Sw5Logic.CRITICAL_WEAPONS = {
    [22] = true, [23] = true, [24] = true, [25] = true, [26] = true, [27] = true, [28] = true,
    [29] = true, [30] = true, [31] = true, [32] = true, [33] = true, [34] = true, [38] = true,
}
Sw5Logic.CRITICAL_RIFLES = { [33] = true, [34] = true } -- COUNTRYRIFLE, SNIPERRIFLE

-- Armas cuyo daño se reescala: armas de fuego de CRITICAL_WEAPONS y cuerpo a cuerpo (0-15).
function Sw5Logic.isRescaledWeapon(weapon)
    if Sw5Logic.CRITICAL_WEAPONS[weapon] then return true end
    return type(weapon) == "number" and weapon >= 0 and weapon <= 15 and weapon == math.floor(weapon)
end

function Sw5Logic.gtaPedDamage(h, rand)
    local loss, after = h.loss or 0, h.healthAfter or 0
    if loss <= 0 or after <= 0 then return nil end
    if h.criticalHits and h.bodypart == Sw5Logic.BODYPART_HEAD and Sw5Logic.CRITICAL_WEAPONS[h.weapon] then
        if h.inVehicle or h.byPlayer then return 0, "critical" end
        if Sw5Logic.CRITICAL_RIFLES[h.weapon] or rand(0, 8) == 0 then return 0, "critical" end
    end
    if (h.armor or 0) > 0 or not Sw5Logic.isRescaledWeapon(h.weapon) then return nil end
    local before = h.healthBefore or (after + loss)
    if before <= 0 then return nil end
    local damage = loss / Sw5Logic.PLAYER_DAMAGE_FACTOR * (h.defendWeakness or Sw5Logic.PED_DEFEND_WEAKNESS)
    if before - damage < 1.0 then return 0, "scaled" end
    local health = before - damage
    if health > after then return nil end -- nunca cura (healthBefore viejo): queda lo de GTA
    return health, "scaled"
end
