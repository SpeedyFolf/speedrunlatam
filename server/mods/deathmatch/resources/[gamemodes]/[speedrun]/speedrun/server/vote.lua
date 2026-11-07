-- Votacion de la proxima mision tras los resultados, y al llegar desde race (Vote.startOnStart).
-- Las opciones llaman eventos locales (addEvent sin remoto) que dispara votemanager.
-- Las misiones de prueba (meta.xml <info speedrun_test="true"/> o def.test = true) no se ofrecen
-- ni se eligen solas: solo se cargan a mano (/changemode speedrun <mapa>, /srtest).
-- Nunca se detiene una votacion ajena (p. ej. un votekick): si hay una abierta se reintenta.
Vote = {}

local MAX_MISSIONS = 8
local FALLBACK_DELAY_MS = 5000
local RETRY_DELAY_MS = 5000
local MAX_RETRIES = 3
local ourPoll = false      -- true mientras la votacion abierta en votemanager es la nuestra
local fallbackTimer = nil
local retryTimer = nil

addEvent("sr:voteMission")
addEvent("sr:votePlayAgain")
addEvent("sr:voteRace")

local function vlog(...)
    local parts = { ... }
    for i = 1, #parts do parts[i] = tostring(parts[i]) end
    outputServerLog("SR|vote|" .. table.concat(parts, "|"))
end

local function missionName(map)
    return getResourceInfo(map, "name") or getResourceName(map)
end

local function shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(1, i)
        list[i], list[j] = list[j], list[i]
    end
end

-- Mision de prueba: por meta.xml (vale antes de que se registre) o por su def.
function Vote.isTestMission(map)
    if not map then return false end
    if getResourceInfo(map, "speedrun_test") == "true" then return true end
    local def = Missions.get(map)
    return def ~= nil and def.test == true
end

local function loadMap(map)
    if not map or not exports.mapmanager:changeGamemodeMap(map) then
        vlog("load_failed", tostring(map and getResourceName(map)))
        return false
    end
    return true
end

-- Las misiones compatibles que no son de prueba, sin la excluida (la que fallo al arrancar).
local function compatibleMissions(excluded)
    local list = {}
    for _, map in ipairs(exports.mapmanager:getMapsCompatibleWithGamemode(getThisResource()) or {}) do
        if map ~= excluded and not Vote.isTestMission(map) then list[#list + 1] = map end
    end
    return list
end

local function cancelTimers()
    if fallbackTimer and isTimer(fallbackTimer) then killTimer(fallbackTimer) end
    if retryTimer and isTimer(retryTimer) then killTimer(retryTimer) end
    fallbackTimer, retryTimer = nil, nil
end

-- Sin votacion posible: repite la mision (o una al azar si esa fallo) tras unos segundos.
-- currentMap tiene que ser una mision que no es de prueba (o nil).
local function scheduleFallback(currentMap, excluded)
    cancelTimers()
    vlog("fallback")
    fallbackTimer = setTimer(function()
        fallbackTimer = nil
        local target = currentMap
        if excluded or not target or getResourceState(target) ~= "running" then
            local list = compatibleMissions(excluded)
            target = list[math.random(1, math.max(#list, 1))]
        end
        if target then loadMap(target) else vlog("fallback_none") end
    end, FALLBACK_DELAY_MS, 1)
end

---------------------------------------------------------------------------
-- Votacion propia en votemanager
---------------------------------------------------------------------------
local onOurPollGone

local function trackOurPoll(active)
    if active == ourPoll then return end
    ourPoll = active
    if active then
        addEventHandler("onPollEnd", root, onOurPollGone)
        addEventHandler("onPollStop", root, onOurPollGone)
    else
        removeEventHandler("onPollEnd", root, onOurPollGone)
        removeEventHandler("onPollStop", root, onOurPollGone)
    end
end

-- votemanager tiene una sola votacion abierta a la vez: mientras la nuestra esta abierta, el
-- fin o la parada que llegue es el de la nuestra (los desempates de votemanager no la terminan).
onOurPollGone = function()
    trackOurPoll(false)
end

local function tryStartPoll(poll)
    local vm = getResourceFromName("votemanager")
    if not vm or getResourceState(vm) ~= "running" then return false, "votemanager_off" end
    local called, started, code = pcall(function() return exports.votemanager:startPoll(poll) end)
    if not called then return false, "call_failed" end
    if started ~= true then return false, code end
    trackOurPoll(true)
    return true
end

-- Abre la votacion; si no se puede (otra abierta, sin votemanager), reintenta y despues fallback().
local function openPoll(poll, attempt, retry, fallback, tag)
    local started, code = tryStartPoll(poll)
    if started then
        vlog(tag, "options=" .. #poll)
        return true
    end
    attempt = (attempt or 0) + 1
    if attempt <= MAX_RETRIES then
        vlog("busy", tag, "code=" .. tostring(code), "retry=" .. attempt)
        cancelTimers()
        retryTimer = setTimer(function()
            retryTimer = nil
            retry(attempt)
        end, RETRY_DELAY_MS, 1)
    else
        vlog("busy", tag, "code=" .. tostring(code), "give_up")
        fallback()
    end
    return false
end

local function missionOptions(missions)
    shuffle(missions)
    while #missions > MAX_MISSIONS do table.remove(missions) end
    local poll = {
        title = "Elige la próxima misión:",
        visibleTo = root,
        percentage = 51,
        timeout = 15,
        allowchange = true,
    }
    for _, map in ipairs(missions) do
        poll[#poll + 1] = { missionName(map), "sr:voteMission", root, map }
    end
    return poll
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------
-- currentMap: mapa recien jugado. failedMap: mapa que fallo al arrancar (se excluye, sin "Jugar de nuevo").
-- Un mapa de prueba no se repite ni se ofrece como "Jugar de nuevo": se pasa a las demas misiones.
function Vote.start(currentMap, failedMap, attempt)
    cancelTimers()
    local replay = (currentMap and not Vote.isTestMission(currentMap)) and currentMap or nil
    local missions = compatibleMissions(failedMap or replay)
    local total = #compatibleMissions(failedMap)

    if failedMap and #missions == 0 then
        vlog("no_alternative")
        noticeSafe("La misión no pudo arrancar y no hay otra disponible.")
        return false
    end
    -- Solo hay misiones de prueba: se repite la actual como ultimo recurso (no se queda trabado).
    if not failedMap and total == 0 then
        vlog("test_only", tostring(currentMap and getResourceName(currentMap)))
        if not loadMap(currentMap) then scheduleFallback(nil, nil) end
        return true
    end
    -- Una sola mision: se repite (o se pasa a ella) sin votar.
    if not failedMap and total == 1 then
        local target = replay or missions[1]
        if not loadMap(target) then scheduleFallback(target, nil) end
        return true
    end

    local poll = missionOptions(missions)
    -- Sin votos gana la opcion por defecto: "Jugar de nuevo", o la primera mision si no se ofrece.
    if not failedMap and replay then
        poll[#poll + 1] = { "Jugar de nuevo", "sr:voteMission", root, replay, default = true }
    elseif poll[1] then
        poll[1].default = true
    end
    local race = getResourceFromName("race")
    if race then
        poll[#poll + 1] = { "Cambiar a carreras", "sr:voteRace", root }
    end

    return openPoll(poll, attempt,
        function(n) Vote.start(currentMap, failedMap, n) end,
        function() scheduleFallback(replay, failedMap) end,
        "started")
end

-- Llegada desde race (race_modeswitch): en vez de jugar el mapa al azar que eligio mapmanager
-- (autoMap), se vota la mision entre las que no son de prueba. Devuelve false si no hay nada que
-- votar y quien llama debe empezar autoMap como siempre.
function Vote.startOnStart(autoMap, attempt)
    cancelTimers()
    local autoName = tostring(autoMap and getResourceName(autoMap))
    local missions = compatibleMissions(nil)
    if #missions == 0 then
        vlog("on_start", "no_missions", "auto_map=" .. autoName)
        return false
    end
    if #missions == 1 then
        if missions[1] == autoMap then
            vlog("on_start", "single", "auto_map=" .. autoName)
            return false
        end
        vlog("on_start", "single_load", getResourceName(missions[1]), "auto_map=" .. autoName)
        -- Diferido: esto corre dentro de onGamemodeMapStart y mapmanager recien fija su mapa actual
        -- cuando el evento vuelve; cambiar de mapa adentro deja dos mapas corriendo. cancelTimers
        -- (Vote.stop / cancelVote) lo cubre.
        local target = missions[1]
        fallbackTimer = setTimer(function()
            fallbackTimer = nil
            if not loadMap(target) then scheduleFallback(nil, nil) end
        end, 50, 1)
        return true
    end
    local poll = missionOptions(missions)
    if poll[1] then poll[1].default = true end
    local replay = (autoMap and not Vote.isTestMission(autoMap)) and autoMap or nil
    if attempt == nil then vlog("on_start", "auto_map=" .. autoName) end
    openPoll(poll, attempt,
        function(n) Vote.startOnStart(autoMap, n) end,
        function() scheduleFallback(replay, nil) end,
        "started_on_start")
    return true
end

function Vote.stop()
    cancelTimers()
    if ourPoll then
        trackOurPoll(false)
        local vm = getResourceFromName("votemanager")
        if vm and getResourceState(vm) == "running" then pcall(function() exports.votemanager:stopPoll() end) end
    end
end

function noticeSafe(text)
    triggerClientEvent(root, "sr:notice", resourceRoot, text)
end

addEventHandler("sr:voteMission", root, function(map)
    if type(map) ~= "userdata" or not getResourceName(map) then return end
    if not loadMap(map) then scheduleFallback(nil, map) end
end)

addEventHandler("sr:voteRace", root, function()
    local race = getResourceFromName("race")
    if not race or not exports.mapmanager:changeGamemode(race) then
        vlog("race_failed")
        scheduleFallback(nil, nil)
    end
end)
