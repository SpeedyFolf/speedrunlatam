-- Smoke test v1.6.3: deploy manual debe hacer refresh sin arrancar speedrun.
-- Ronda del gamemode speedrun: carga, cuenta regresiva, en curso y resultados.
-- La interfaz va por eventos sr:* hacia el cliente (client/hud.lua, results.lua, spectate.lua).
-- Tras los resultados (12 s) se abre la votacion de la proxima mision (server/vote.lua).

local LOBBY = { x = 2488.0, y = -1666.0, z = 13.35, rot = 0 } -- Grove Street, dimension 0
local LOADING_DELAY_MS = 1000
local COUNTDOWN_SECONDS = 3
local RESTART_DELAY_MS = 5000
local RESPAWN_NOW_MS = 50
local LOBBY_RESPAWN_MS = 3000
local RESULTS_MS = 12000
local FINISH_TO_LOBBY_MS = 2000
-- Aviso de un solo uso que deja race_modeswitch (getTickCount() en element data de root) antes de
-- cambiar a speedrun: el primer mapa abre la votacion de mision. Se ignora si es viejo.
local VOTE_ON_START_KEY = "speedrun.voteOnStart"
local VOTE_ON_START_MAX_AGE_MS = 60000
local TICK_MS = 250
local SPECTATE_SYNC_MS = 500
local CLEANUP_TYPES = { "vehicle", "ped", "object", "marker", "pickup", "colshape", "blip" }

local srLog = Instances.log

local round = nil          -- RoundLogic de la ronda actual
local roundInfo = nil      -- { resource, def, order = {}, names = {}, ended }
local currentMap = nil     -- resource de mapa que dio mapmanager
local awaitingMap = nil    -- mapa iniciado cuya mision todavia no se registro / sin jugadores
local timers = {}          -- loading, countdown, tick
local playerTimers = {}    -- [player] = timer de reinicio o de vuelta al lobby
local stoppedDefaultStats = false
local spectators = {}      -- [player] = jugador al que mira
local voteOnStart = false  -- llegada desde race: el primer onGamemodeMapStart vota la mision

addEvent("sr:spectateNext", true)
addEvent("sr:clientReady", true)
addEvent("sr:requestRecords", true)

local function now() return getTickCount() end

local function killTimerSafe(t)
    if t and isTimer(t) then killTimer(t) end
end

local function nameOf(player)
    if isElement(player) then return getPlayerName(player) end
    if roundInfo and roundInfo.names[player] then return roundInfo.names[player] end
    return "?"
end

local function roundRunning()
    return round ~= nil and roundInfo ~= nil and not roundInfo.ended
end

-- En la ronda, sin terminar y sin abandonar.
local function isActive(player)
    if not roundRunning() then return false end
    local p = round.players[player]
    return p ~= nil and p.finishedMs == nil and not p.dnf
end

-- Ambiente por copia (server/ambient.lua): solo con la ronda en marcha y el jugador jugando.
Ambient.canRun = function(player)
    return roundRunning() and round.state == "running" and isActive(player) and Instances.has(player)
end

local function setFrozen(player, frozen)
    if not isElement(player) then return end
    setElementFrozen(player, frozen)
    toggleAllControls(player, not frozen, true, false)
end

local function sendTo(player, eventName, ...)
    if isElement(player) then triggerClientEvent(player, eventName, resourceRoot, ...) end
end

-- Deja de espectar: devuelve visibilidad, colisiones y control. No mueve al jugador.
local function stopSpectate(player)
    if spectators[player] == nil then return end
    spectators[player] = nil
    if not isElement(player) then return end
    setElementAlpha(player, 255)
    setElementCollisionsEnabled(player, true)
    setElementFrozen(player, false)
    toggleAllControls(player, true, true, false)
    setPlayerNametagShowing(player, true)
    setCameraTarget(player, player)
    sendTo(player, "sr:spectate", nil)
end

local function spawnInLobby(player)
    if not isElement(player) then return end
    stopSpectate(player)
    spawnPlayer(player, LOBBY.x + math.random(-3, 3), LOBBY.y + math.random(-3, 3), LOBBY.z, LOBBY.rot, 0, 0, 0)
    -- Ni los stats ni las armas de la mision pasan al lobby (defaultstats esta detenido).
    takeAllWeapons(player)
    PlayerState.applyBaseline(player)
    setElementHealth(player, 100)
    setFrozen(player, false)
    setCameraTarget(player, player)
    fadeCamera(player, true)
end

-- Evento hacia todos los jugadores de la ronda.
local function tellRound(eventName, ...)
    if not roundInfo then return end
    for _, player in ipairs(roundInfo.order) do
        sendTo(player, eventName, ...)
    end
end

local function noticeAll(text)
    triggerClientEvent(root, "sr:notice", resourceRoot, text)
end

-- Jugadores de la ronda que siguen jugando (candidatos a ser mirados).
local function activeTargets()
    local list = {}
    if not roundRunning() then return list end
    for _, p in ipairs(roundInfo.order) do
        if isElement(p) and isActive(p) and Instances.has(p) then list[#list + 1] = p end
    end
    return list
end

-- Siguiente objetivo respecto de current (dir = 1 o -1). nil si no hay.
local function nextTarget(current, dir)
    local list = activeTargets()
    if #list == 0 then return nil end
    local idx
    for i, p in ipairs(list) do
        if p == current then idx = i break end
    end
    if not idx then return list[1] end
    local n = idx + (dir < 0 and -1 or 1)
    if n < 1 then n = #list elseif n > #list then n = 1 end
    return list[n]
end

local function followTarget(player, target)
    setElementDimension(player, getElementDimension(target))
    setElementInterior(player, getElementInterior(target))
    local x, y, z = getElementPosition(target)
    setElementPosition(player, x, y, z)
end

-- Mantiene al espectador junto a su objetivo; si el objetivo ya no juega, pasa al siguiente o al lobby.
local function syncSpectators()
    local any = false
    for player, target in pairs(spectators) do
        if not isElement(player) then
            spectators[player] = nil
        else
            if not (isElement(target) and isActive(target) and Instances.has(target)) then
                target = nextTarget(target, 1)
                if target then
                    spectators[player] = target
                    sendTo(player, "sr:spectate", target)
                else
                    spawnInLobby(player)
                end
            end
            if spectators[player] then
                followTarget(player, spectators[player])
                any = true
            end
        end
    end
    if not any then
        killTimerSafe(timers.spectate)
        timers.spectate = nil
    end
end

local function startSpectate(player, target)
    if not isElement(player) or not isElement(target) then return false end
    local fresh = spectators[player] == nil
    spectators[player] = target
    -- Sin armas: el espectador esta en la dimension de la copia de otro jugador.
    takeAllWeapons(player)
    if fresh then
        setElementFrozen(player, true)
        toggleAllControls(player, false, true, false)
        setElementAlpha(player, 0)
        setElementCollisionsEnabled(player, false)
        setPlayerNametagShowing(player, false)
        fadeCamera(player, true)
    end
    followTarget(player, target)
    sendTo(player, "sr:spectate", target)
    if not timers.spectate then timers.spectate = setTimer(syncSpectators, SPECTATE_SYNC_MS, 0) end
    return true
end

local function releaseSpectators()
    for player in pairs(spectators) do
        spawnInLobby(player)
    end
end

-- skipInUse: no cuenta las dimensiones que ya tienen una copia nueva asignada.
local function countRemainingElements(skipInUse)
    local n = 0
    for _, elementType in ipairs(CLEANUP_TYPES) do
        for _, el in ipairs(getElementsByType(elementType)) do
            local dim = getElementDimension(el)
            if Instances.isInstanceDimension(dim) and not (skipInUse and Instances.isDimensionInUse(dim)) then
                n = n + 1
            end
        end
    end
    return n
end

local function stopRoundTimers()
    killTimerSafe(timers.countdown)
    killTimerSafe(timers.tick)
    killTimerSafe(timers.spectate)
    timers.countdown, timers.tick, timers.spectate = nil, nil, nil
    for player, t in pairs(playerTimers) do
        killTimerSafe(t)
        playerTimers[player] = nil
    end
end

local function cancelLoading()
    killTimerSafe(timers.loading)
    timers.loading = nil
end

local function cancelVote()
    killTimerSafe(timers.vote)
    timers.vote = nil
    Vote.stop()
end

-- Cuenta que puede tener record: sesion iniciada (no invitada). nil si no.
local function recordAccountName(player)
    if not isElement(player) then return nil end
    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return nil end
    return getAccountName(account)
end

-- Pais del jugador via ip2c (codigo ISO de 2 letras, ej. "ar"). nil si no
-- esta disponible; el record se guarda igual sin bandera.
local function resolveCountry(player)
    if not isElement(player) then return nil end
    local res = getResourceFromName("ip2c")
    if not res or getResourceState(res) ~= "running" then return nil end
    local ok, country = pcall(function() return exports.ip2c:getPlayerCountry(player) end)
    if not ok or type(country) ~= "string" or country == "" or country == "ZZ" then return nil end
    return string.lower(country)
end

---------------------------------------------------------------------------
-- Fin de ronda
---------------------------------------------------------------------------
-- stopping = true cuando el propio gamemode se esta deteniendo (no hay timers ni lobby).
local function endRound(reason, stopping)
    if not roundRunning() then return false end
    roundInfo.ended = true
    stopRoundTimers()
    round.state = "results"
    srLog("round", "results", "reason=" .. reason)

    local ranking = Results.rank(round.players, roundInfo.order)
    local rows = {}
    for _, r in ipairs(ranking) do
        local name = roundInfo.names[r.id] or nameOf(r.id)
        local timeText = r.finishedMs and Results.formatTime(r.finishedMs) or "DNF"
        srLog("round", "result", r.position or "-", name, timeText, "fails=" .. r.failures)
        rows[#rows + 1] = {
            position = r.position,
            name = name,
            timeText = r.finishedMs and timeText or "No terminó",
            finishedMs = r.finishedMs,
            failures = r.failures,
        }
    end
    local missionTitle = roundInfo.def.title
    local order = roundInfo.order
    local missionId = roundInfo.def.id
    local missionRes = roundInfo.resource

    -- Records: solo cuentas con sesion iniciada. Se anuncia a todos solo el record de la mision
    -- (comparado con el mejor de todas las cuentas antes de guardar); el mejor tiempo personal se
    -- le avisa solo a ese jugador. El ranking va del mas rapido al mas lento.
    for _, r in ipairs(ranking) do
        if r.finishedMs then
            local accountName = roundInfo.accounts[r.id]
            local best = accountName and getBest(missionId)
            local country = (roundInfo.countries and roundInfo.countries[r.id]) or resolveCountry(r.id)
            if accountName and country then updateCountry(missionId, accountName, country) end
            if accountName and saveIfBetter(missionId, accountName, r.finishedMs, country) then
                local name = roundInfo.names[r.id] or nameOf(r.id)
                local timeText = Results.formatTime(r.finishedMs)
                if Results.recordKind(best and best.time_ms, r.finishedMs) == "mission" then
                    srLog("record", missionId, accountName, timeText)
                    noticeAll(("¡Nuevo récord de la misión! %s: %s"):format(name, timeText))
                else
                    srLog("pb", missionId, accountName, timeText)
                    sendTo(r.id, "sr:notice", ("Nuevo mejor tiempo personal: %s"):format(timeText))
                end
            end
        end
    end
    local best = getBest(missionId)
    local recordRow = best and { name = best.account, timeText = Results.formatTime(best.time_ms) } or nil
    triggerClientEvent(root, "sr:results", resourceRoot, rows, missionTitle, recordRow)

    -- Votacion despues de los resultados (tambien tras una ronda de /srtest, para que la rotacion
    -- siga), salvo un /srtest nuevo, cambios de mapa y parada del gamemode.
    if not stopping and (reason == "all_done" or reason == "time_limit" or reason == "start_failed" or reason == "mission_stopped") then
        local playedMap = missionRes
        local failedMap = (reason == "start_failed" or reason == "mission_stopped") and missionRes or nil
        killTimerSafe(timers.vote)
        timers.vote = setTimer(function()
            timers.vote = nil
            if roundRunning() then return end
            Vote.start(playedMap, failedMap)
        end, RESULTS_MS, 1)
    end
    for _, player in ipairs(order) do
        Instances.endInstance(player)
        if isElement(player) then
            if stopping then
                stopSpectate(player)
                setFrozen(player, false)
                setElementDimension(player, 0)
            else
                spawnInLobby(player)
            end
        end
    end
    if stopping then
        for player in pairs(spectators) do
            stopSpectate(player)
            if isElement(player) then setElementDimension(player, 0) end
        end
    else
        releaseSpectators()
    end
    round, roundInfo = nil, nil

    local function logCleanup(skipInUse)
        srLog("cleanup", "mission=" .. tostring(missionId), "remaining=" .. countRemainingElements(skipInUse))
    end
    -- Con la mision corriendo, srDestroyInstance ya borro todo: se cuenta ahora, antes de que
    -- una ronda nueva (p. ej. /srtest) cree copias. Si la mision se esta deteniendo, sus elementos
    -- se borran despues de este evento: se cuenta mas tarde, sin las dimensiones ya reasignadas.
    if stopping or (missionRes and getResourceState(missionRes) == "running") then
        logCleanup(false)
    else
        setTimer(logCleanup, 100, 1, true)
    end
    return true
end

local function tick()
    if not roundRunning() then return end
    local t = now()
    if round:tick(t) == "results" then
        local deadline = round:deadline()
        endRound((deadline and t >= deadline) and "time_limit" or "all_done")
    end
end

-- La copia no se pudo crear: el jugador queda como "no termino" y vuelve al lobby.
local function dropPlayer(player)
    if roundRunning() and round.players[player] then round:quit(player, now()) end
    Instances.endInstance(player)
    if isElement(player) then
        spawnInLobby(player)
        sendTo(player, "sr:notice", "No se pudo crear tu copia de la misión: quedás fuera de esta ronda.")
    end
end

-- Vuelve a crear la copia en el inicio. Quieto solo si todavia es la cuenta regresiva.
local function respawnAtStart(player)
    if not Instances.restartInstance(player) then
        dropPlayer(player)
        return false
    end
    setFrozen(player, round.state == "countdown")
    -- Con la ronda en curso la copia nueva corre ya: hook opcional de la mision.
    if round.state == "running" then Instances.notifyGo(player, now()) end
    return true
end

---------------------------------------------------------------------------
-- Inicio de ronda
---------------------------------------------------------------------------
local function go()
    timers.countdown = nil
    if not roundRunning() then return end
    round:go(now())
    roundInfo.goTick = now()
    srLog("round", "running", "mission=" .. roundInfo.def.id, "limitMs=" .. round.timeLimitMs)
    for _, player in ipairs(roundInfo.order) do
        if isActive(player) then setFrozen(player, false) end
    end
    -- Hook opcional de la mision: srInstanceGo(player, token, goTick) por cada copia que larga.
    for _, player in ipairs(roundInfo.order) do
        if isActive(player) and Instances.has(player) then Instances.notifyGo(player, roundInfo.goTick) end
    end
    Ambient.activateAll()
    local missionName = getResourceName(roundInfo.resource)
    local respect = roundInfo.def.respect or 5
    tellRound("sr:go", roundInfo.goTick, 0, missionName, respect)
    for player in pairs(spectators) do sendTo(player, "sr:go", roundInfo.goTick, 0, missionName, respect) end
    timers.tick = setTimer(tick, TICK_MS, 0)
end

local function startRound(players, missionResource, def, isTest)
    cancelLoading()
    cancelVote()
    awaitingMap = nil
    round = RoundLogic.new({ timeLimitMs = def.timeLimitMs, extraAfterFirstMs = def.extraAfterFirstMs })
    roundInfo = { resource = missionResource, def = def, order = {}, names = {}, ended = false, accounts = {}, countries = {},
                  test = isTest and true or false }
    Instances.setMission(missionResource, def)
    -- Los stats de cada copia son la base de partida nueva + los de la mision (player_state.lua).
    local overrides = 0
    for _ in pairs(type(def.playerState.stats) == "table" and def.playerState.stats or {}) do overrides = overrides + 1 end
    srLog("stats", "baseline", "mission=" .. def.id, "overrides=" .. overrides)

    local started = 0
    for _, player in ipairs(players) do
        if isElement(player) then
            round:addPlayer(player)
            roundInfo.order[#roundInfo.order + 1] = player
            roundInfo.names[player] = getPlayerName(player)
            if Instances.startInstance(player) then
                started = started + 1
                setFrozen(player, true)
            else
                dropPlayer(player)
            end
        end
    end

    if #roundInfo.order == 0 then
        round, roundInfo = nil, nil
        srLog("round", "waiting", "reason=no_players")
        return false
    end
    if started == 0 then
        endRound("start_failed")
        return false
    end

    round:start(now())
    srLog("round", "countdown", "mission=" .. def.id, "players=" .. #roundInfo.order)
    tellRound("sr:notice", ("Misión: %s"):format(def.title))
    local remaining = COUNTDOWN_SECONDS
    roundInfo.countdownValue = remaining
    tellRound("sr:countdown", remaining)
    timers.countdown = setTimer(function()
        remaining = remaining - 1
        if remaining > 0 then
            roundInfo.countdownValue = remaining
            tellRound("sr:countdown", remaining)
        else
            go()
        end
    end, 1000, COUNTDOWN_SECONDS)
    return true
end

-- Ronda para todos los jugadores con la mision de un mapa, despues de un momento de carga.
local function scheduleMapRound(mapResource)
    local def = Missions.get(mapResource)
    if not def then
        awaitingMap = mapResource
        srLog("round", "waiting", "reason=mission_not_registered")
        return
    end
    if #getElementsByType("player") == 0 then
        awaitingMap = mapResource
        srLog("round", "waiting", "reason=no_players")
        return
    end
    awaitingMap = nil
    cancelLoading()
    srLog("round", "loading", "mission=" .. def.id)
    timers.loading = setTimer(function()
        timers.loading = nil
        local d = Missions.get(mapResource)
        if d and getResourceState(mapResource) == "running" and not roundRunning() then
            startRound(getElementsByType("player"), mapResource, d)
        end
    end, LOADING_DELAY_MS, 1)
end

Missions.onRegistered = function(res, def)
    if res == awaitingMap and res == currentMap and not roundRunning() then
        scheduleMapRound(res)
    end
end

---------------------------------------------------------------------------
-- Falla y fin de copia
---------------------------------------------------------------------------
local function handleFailure(player, reason)
    if not isActive(player) or not Instances.isAccepting(player) then return false end
    local state = round.state
    if state ~= "countdown" and state ~= "running" then return false end
    Instances.suspend(player)
    killTimerSafe(playerTimers[player])

    if state ~= "running" then
        -- Antes de la largada no hay falla: no se cuenta ni se avisa, se reaparece en el inicio.
        -- El timer minimo saca el respawn del evento de muerte / de la llamada de la mision.
        srLog("respawn", nameOf(player), state)
        playerTimers[player] = setTimer(function()
            playerTimers[player] = nil
            if isElement(player) and isActive(player) then respawnAtStart(player) end
        end, RESPAWN_NOW_MS, 1)
        return true
    end

    round:fail(player, now())
    srLog("fail", nameOf(player), reason)
    -- Al morir, el GXT de falla termina un poco antes del respawn para que no quede en pantalla.
    sendTo(player, "sr:failed", reason, reason == "death" and (RESTART_DELAY_MS - 500) or nil)

    playerTimers[player] = setTimer(function()
        playerTimers[player] = nil
        if isElement(player) and isActive(player) then respawnAtStart(player) end
    end, RESTART_DELAY_MS, 1)
    return true
end

-- Arresto del wanted dimension-aware (server/wanted.lua): falla la corrida en
-- vez del outcome por defecto (comisaria, multa, armas). Devolver false cancela
-- ese outcome; el speedrun ya reinicia la copia.
addEventHandler("onNativePlayerArrested", root, function()
    local player = source
    if not isElement(player) then return false end
    handleFailure(player, "arrested")
    return false
end)

local function finishPlayer(player)
    local ms = round:finish(player, now())
    if not ms then return false end
    Instances.suspend(player)
    local position = 0
    for _, p in pairs(round.players) do
        if p.finishedMs ~= nil then position = position + 1 end
    end
    roundInfo.accounts[player] = recordAccountName(player)
    roundInfo.countries[player] = resolveCountry(player)
    srLog("finish", nameOf(player), Results.formatTime(ms))
    sendTo(player, "sr:finished", ms, position)
    noticeAll(("%s terminó en %s (%dº)"):format(nameOf(player), Results.formatTime(ms), position))

    -- Se libera fuera de la llamada de la mision (evita reentrar en su export).
    local token = Instances.getToken(player)
    killTimerSafe(playerTimers[player])
    playerTimers[player] = setTimer(function()
        playerTimers[player] = nil
        if isElement(player) and Instances.getToken(player) == token then
            Instances.endInstance(player)
            -- Quien termina pasa a espectar a otro jugador activo; sin nadie, vuelve al lobby.
            local target = roundRunning() and nextTarget(nil, 1) or nil
            -- Murio despues de terminar: primero reaparece (en el lobby) y despues mira. El timer de
            -- onPlayerWasted ya no lo encuentra muerto y no lo saca de espectar.
            if target and isPedDead(player) then spawnInLobby(player) end
            if not (target and startSpectate(player, target)) then spawnInLobby(player) end
        end
    end, FINISH_TO_LOBBY_MS, 1)
    return true
end

---------------------------------------------------------------------------
-- Exports de servidor para las misiones
---------------------------------------------------------------------------
function reportCompleted(player, token)
    if not roundRunning() then
        srLog("complete_reject", nameOf(player), "no_round")
        return false
    end
    if sourceResource ~= roundInfo.resource then
        local caller = (sourceResource and getResourceName(sourceResource)) or tostring(sourceResource)
        srLog("complete_reject", nameOf(player), "wrong_res", "caller=" .. caller)
        return false
    end
    if not isElement(player) then
        srLog("complete_reject", "?", "no_player")
        return false
    end
    if not Instances.isCurrentToken(player, token) then
        srLog("complete_reject", nameOf(player), "token")
        return false
    end
    if not isActive(player) then
        srLog("complete_reject", nameOf(player), "inactive")
        return false
    end
    return finishPlayer(player)
end

function reportFailed(player, token, reasonKey)
    if not roundRunning() or sourceResource ~= roundInfo.resource then return false end
    if not isElement(player) or not Instances.isCurrentToken(player, token) then return false end
    local reason = type(reasonKey) == "string" and reasonKey ~= "" and reasonKey:gsub("|", "/") or "mission"
    return handleFailure(player, reason)
end

-- Panel de records del cliente (F5 / /records). Sin argumento usa la mision
-- de la ronda actual o la ultima registrada; si no hay ninguna, manda el
-- resumen de todas las misiones con su mejor tiempo.
addEventHandler("sr:requestRecords", resourceRoot, function(missionId)
    if not isElement(client) then return end
    local requested = type(missionId) == "string" and missionId ~= "" and missionId or nil
    local def = requested and Missions.getById(requested) or nil
    if not requested and roundInfo and roundInfo.def then
        requested = roundInfo.def.id
        def = roundInfo.def
    end
    if not requested then
        local _, current = Missions.getCurrent()
        if current then requested, def = current.id, current end
    end
    if not requested then
        local summary = getMissionBests()
        for _, row in ipairs(summary) do
            local rowDef = Missions.getById(row.mission)
            row.title = rowDef and rowDef.title or row.mission
        end
        triggerClientEvent(client, "sr:records", resourceRoot, { mode = "summary", rows = summary })
        return
    end
    local rows = getTop(requested, 10)
    -- Backfill de records viejos: si el que tiene el top esta online, resolver
    -- su pais ahora y guardarlo.
    for _, row in ipairs(rows) do
        if type(row.account) == "string" and (row.country == nil or row.country == "") then
            local account = getAccount(row.account)
            local holder = account and getAccountPlayer(account)
            local country = holder and resolveCountry(holder) or nil
            if country then
                updateCountry(requested, row.account, country)
                row.country = country
            end
        end
    end
    local accountName = recordAccountName(client)
    triggerClientEvent(client, "sr:records", resourceRoot, {
        mode = "mission",
        missionId = requested,
        title = def and def.title or requested,
        rows = rows,
        personal = accountName and getPersonalBest(requested, accountName) or nil,
    })
end)

---------------------------------------------------------------------------
-- Jugadores
---------------------------------------------------------------------------
addEventHandler("onPlayerWasted", root, function()
    local player = source
    if isActive(player) and Instances.has(player) then
        handleFailure(player, "death")
        return
    end
    if isActive(player) then return end
    -- Solo si sigue muerto: si termino y ya reaparecio para espectar (finishPlayer), no se toca.
    setTimer(function()
        if isElement(player) and isPedDead(player) and not isActive(player) then spawnInLobby(player) end
    end, LOBBY_RESPAWN_MS, 1)
end)

addEventHandler("onPlayerQuit", root, function()
    local player = source
    killTimerSafe(playerTimers[player])
    playerTimers[player] = nil
    spectators[player] = nil
    if roundRunning() and round.players[player] then
        round:quit(player, now())
    end
    Instances.endInstance(player)
end)

addEventHandler("onPlayerJoin", root, function()
    spawnInLobby(source)
    if awaitingMap and awaitingMap == currentMap and not roundRunning() and not timers.loading then
        scheduleMapRound(awaitingMap)
    end
end)

---------------------------------------------------------------------------
-- Mapas (mapmanager) y misiones que se detienen
---------------------------------------------------------------------------
addEventHandler("onGamemodeMapStart", root, function(mapResource)
    if roundRunning() then endRound("map_changed") end
    cancelLoading()
    cancelVote()
    currentMap = mapResource
    -- Llegada desde race: se vota la mision (solo las que no son de prueba) en lugar de jugar el
    -- mapa al azar de mapmanager. Los jugadores esperan en el lobby; el ganador carga como siempre.
    -- Sin nada que votar, se juega este mapa como antes.
    if voteOnStart then
        voteOnStart = false
        if Vote.startOnStart(mapResource) then return end
    end
    scheduleMapRound(mapResource)
end)

addEventHandler("onGamemodeMapStop", root, function(mapResource)
    if roundRunning() and roundInfo.resource == mapResource then endRound("mission_stopped") end
    if currentMap == mapResource then
        cancelLoading()
        currentMap = nil
        awaitingMap = nil
    end
end)

addEventHandler("onResourceStop", root, function(stoppedResource)
    if stoppedResource == getThisResource() then return end
    if not Missions.get(stoppedResource) then return end
    if roundRunning() and roundInfo.resource == stoppedResource then endRound("mission_stopped") end
    Missions.unregister(stoppedResource)
end)

---------------------------------------------------------------------------
-- Espectador: eventos del cliente (siempre se usa `client`, nunca un jugador pasado)
---------------------------------------------------------------------------
-- El cliente avisa que cargo. Si la ronda ya empezo y no esta en ella (entro a mitad): espectador.
addEventHandler("sr:clientReady", resourceRoot, function()
    local player = client
    if not isElement(player) or not roundRunning() then return end
    -- Si su copia arranco antes de que cargara, se le reenvia el ambiente (etapa y pedidos).
    Ambient.resend(player)
    -- Reenvia el estado del reloj (sirve a quien esta en la ronda pero cargo tarde, y a espectadores).
    if round.state == "running" and roundInfo.goTick then
        sendTo(player, "sr:go", roundInfo.goTick, now() - roundInfo.goTick,
            getResourceName(roundInfo.resource), roundInfo.def.respect or 5)
    elseif round.state == "countdown" and roundInfo.countdownValue then
        sendTo(player, "sr:countdown", roundInfo.countdownValue)
    end
    if spectators[player] or round.players[player] then return end
    local target = nextTarget(nil, 1)
    if target then startSpectate(player, target) end
end)

addEventHandler("sr:spectateNext", resourceRoot, function(dir)
    local player = client
    if not isElement(player) or spectators[player] == nil then return end
    if dir ~= 1 and dir ~= -1 then return end
    local target = nextTarget(spectators[player], dir)
    if target then
        spectators[player] = target
        followTarget(player, target)
        sendTo(player, "sr:spectate", target)
    end
end)

-- /kill: matarse a uno mismo. Cuenta como una muerte normal (falla en curso, respawn en la cuenta).
addCommandHandler("kill", function(player)
    if getElementType(player) == "player" and not isPedDead(player) then killPed(player) end
end)

---------------------------------------------------------------------------
-- /srtest: ronda de un solo jugador (admin); al terminar sigue la rotacion (votacion o repeticion)
---------------------------------------------------------------------------
local function isAdmin(player)
    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return false end
    local group = aclGetGroup("Admin")
    return group ~= false and group ~= nil and isObjectInACLGroup("user." .. getAccountName(account), group)
end

addCommandHandler("srtest", function(player)
    -- Solo jugadores (no la consola): la ronda es para quien la pide.
    if not isElement(player) or getElementType(player) ~= "player" then return end
    if not isAdmin(player) then
        outputChatBox("Solo los administradores pueden usar /srtest.", player, 255, 120, 120)
        return
    end
    local res, def = Missions.getCurrent(currentMap)
    if not res or getResourceState(res) ~= "running" then
        outputChatBox("No hay ninguna misión cargada.", player, 255, 120, 120)
        return
    end
    if roundRunning() then endRound("srtest") end
    cancelLoading()
    cancelVote()
    srLog("round", "srtest", "mission=" .. def.id, "admin=" .. getPlayerName(player))
    startRound({ player }, res, def, true)
end)

---------------------------------------------------------------------------
-- Arranque y parada del gamemode
---------------------------------------------------------------------------
addEventHandler("onResourceStart", resourceRoot, function()
    -- Aviso de race_modeswitch (un solo uso): se lee y se borra ya, aunque el mapa tarde.
    local flag = getElementData(root, VOTE_ON_START_KEY)
    if flag ~= nil and flag ~= false then removeElementData(root, VOTE_ON_START_KEY) end
    voteOnStart = type(flag) == "number" and getTickCount() - flag >= 0 and getTickCount() - flag <= VOTE_ON_START_MAX_AGE_MS
    if flag ~= nil and flag ~= false then srLog("vote", "on_start_flag", "accepted=" .. tostring(voteOnStart)) end
    local ds = getResourceFromName("defaultstats")
    if ds and getResourceState(ds) == "running" then
        stoppedDefaultStats = stopResource(ds) and true or false
        outputServerLog("speedrun: defaultstats detenido=" .. tostring(stoppedDefaultStats))
    end
    for _, player in ipairs(getElementsByType("player")) do
        spawnInLobby(player)
    end
    -- defaultstats puede aplicar sus stats en este mismo frame (su onResourceStart de root): la base
    -- del lobby se vuelve a poner un momento despues para que quede.
    setTimer(function()
        for _, player in ipairs(getElementsByType("player")) do
            if not Instances.has(player) and spectators[player] == nil then PlayerState.applyBaseline(player) end
        end
    end, 50, 1)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if roundRunning() then endRound("gamemode_stopped", true) end
    cancelVote()
    -- Nadie se lleva a race los stats ni las armas de una mision: base de partida nueva y sin armas
    -- (despues defaultstats, si se reinicia, pone sus propios valores encima).
    local players = getElementsByType("player")
    for _, player in ipairs(players) do
        stopSpectate(player)
        setFrozen(player, false)
        setElementDimension(player, 0)
        takeAllWeapons(player)
        PlayerState.applyBaseline(player)
    end
    srLog("stats", "baseline", "gamemode_stop", "players=" .. #players)
    if stoppedDefaultStats then
        local ds = getResourceFromName("defaultstats")
        -- persistent = true: si no, MTA lo detiene junto con speedrun (quien lo inicio).
        if ds and getResourceState(ds) == "loaded" then
            local ok = startResource(ds, true)
            outputServerLog("speedrun: defaultstats reiniciado=" .. tostring(ok and true or false))
        end
        stoppedDefaultStats = false
    end
end)
