-- Texto, audio de mision y barra de vida de Sweet (cliente). COVERAGE.md §4 manda.
--   - Texto: acquireMissionText("SWEET5") al empezar la copia (sr5:begin), releaseMissionText al
--     terminar (sr5:end, reinicio o parada del resource). showMissionText usa el camino PRINT_NOW.
--     Las claves de la tabla MAIN (MOBRING, MSWE13A..G) siguen disponibles con el bloque arrendado
--     (guia story-runtime de Neon). R5: si una clave no se puede mostrar, se manda
--     SR5|text_missing|<clave> al log (una vez por clave y copia) y el audio suena igual.
--   - Audio (sweet5_audio CASE 1..4): una secuencia de claves a la vez (play_audio /
--     play_audio_for). Por linea: requestMissionAudio -> isMissionAudioLoaded -> playMissionAudio
--     -> CLEAR_PRINTS + showMissionText(clave, 10000) -> isMissionAudioFinished (o muerte del
--     hablante) -> CLEAR_PRINTS + releaseMissionAudio. La siguiente linea se precarga en otro slot
--     mientras suena la actual (como el SCM; a lo sumo 2 de los 4 slots de Neon).
--     Si el audio no esta (pedido rechazado, carga vencida o play rechazado): solo el subtitulo
--     (3 s) y SR5|audio_missing|<clave>:<motivo> (una vez por clave y copia).
--   - Hablante (audio_for_char): 1 = CJ (localPlayer), 2 = Sweet, 3 = novia (TextAudio.setSpeaker,
--     desde chase.lua). START_CHAR_FACIAL_TALK 15000 -> setPedFacialTalk; DISABLE/ENABLE_CHAR_SPEECH
--     -> setPedScriptedSpeechMuted. Sin ATTACH_MISSION_AUDIO_TO_CHAR (Neon no lo tiene) ni
--     IS_CHAR_TALKING (se silencia y se reproduce sin esperar): adapted.
--   - Cola (lo decide Sw5Logic.audioAdmit): opts.dropIfBusy = la linea se pierde si ya suena otra
--     (play_audio pisado en el SCM); si no, espera su turno.
--   - Barra: DISPLAY_ONSCREEN_COUNTER_WITH_STRING ... COUNTER_DISPLAY_BAR SW5_A3, con dxDraw.
TextAudio = {}

local L = Sw5Logic
local P = Sw5Logic.AUDIO_PLAYER
local POLL_MS = 100

local textOwned = false
local missingLogged = {}  -- [clave o "audio:"..clave] = true: un aviso por clave y por copia
local queue = {}          -- secuencias esperando
local current = nil       -- secuencia que suena
local pollTimer = nil
local pendingTimers = {}  -- textos en cola (SW5_A2 -> SW5_17, SW5_I despues de SWE5_CC)
local health = nil
local speakers = {}       -- [2] Sweet y [3] novia (chase.lua); [1] = CJ siempre

local function api(name, ...)
    local fn = _G[name]
    if type(fn) ~= "function" then return false, "api" end
    local ok, result = pcall(fn, ...)
    if not ok then return false, "error" end
    return result
end

local function report(kind, detail)
    if Sw5Client and Sw5Client.log then Sw5Client.log(kind, detail) end
end

---------------------------------------------------------------------------
-- Texto
---------------------------------------------------------------------------
local function ensureText()
    if textOwned then return true end
    textOwned = api("acquireMissionText", SW5.TEXT_BLOCK) == true
    if not textOwned and not missingLogged["#block"] then
        missingLogged["#block"] = true
        report("text_block_missing", SW5.TEXT_BLOCK)
    end
    return textOwned
end

function TextAudio.showText(key, duration)
    local ok = ensureText() and api("showMissionText", key, duration or 4000, 1) == true
    if not ok and not missingLogged[key] then
        missingLogged[key] = true
        report("text_missing", key) -- R5
    end
    return ok
end

function TextAudio.showHelp(key)
    local ok = ensureText() and api("showMissionHelp", key, false) == true
    if not ok and not missingLogged[key] then
        missingLogged[key] = true
        report("text_missing", key)
    end
    return ok
end

local function clearPrints()
    if textOwned then api("clearMissionTexts") end
end

-- Textos en cola, como PRINT: cada uno cuando vence el anterior.
function TextAudio.queueTexts(list)
    local delay = 0
    for _, item in ipairs(list) do
        local key, duration = item[1], item[2]
        if type(key) == "string" and SW5.TEXT_KEYS[key] and type(duration) == "number" then
            if delay == 0 then
                TextAudio.showText(key, duration)
            else
                local t
                t = setTimer(function()
                    pendingTimers[t] = nil
                    TextAudio.showText(key, duration)
                end, delay, 1)
                pendingTimers[t] = true
            end
            delay = delay + duration
        end
    end
end

---------------------------------------------------------------------------
-- Hablantes
---------------------------------------------------------------------------
function TextAudio.setSpeaker(id, ped)
    if id == 2 or id == 3 then speakers[id] = ped end
end

local function speakerFor(info)
    if not info or info.speaker == 0 then return nil end
    if info.speaker == 1 then return localPlayer end
    local ped = speakers[info.speaker]
    if isElement(ped) then return ped end
    return nil
end

-- CASE 2: DOES_CHAR_EXIST this_actor + IS_CHAR_DEAD this_actor.
local function speakerDead(line)
    local ped = line.speaker
    return ped ~= nil and isElement(ped) and isPedDead(ped)
end

local function startTalk(line)
    local ped = speakerFor(line.info)
    line.speaker = ped
    if not ped or isPedDead(ped) then return end
    api("setPedScriptedSpeechMuted", ped, true) -- DISABLE_CHAR_SPEECH
    api("setPedFacialTalk", ped, 15000)          -- START_CHAR_FACIAL_TALK 15000
end

local function stopTalk(line)
    local ped = line and line.speaker
    if not ped or not isElement(ped) or isPedDead(ped) then return end
    api("stopPedFacialTalk", ped)                -- STOP_CHAR_FACIAL_TALK
    api("setPedScriptedSpeechMuted", ped, false) -- ENABLE_CHAR_SPEECH
end

---------------------------------------------------------------------------
-- Audio
---------------------------------------------------------------------------
local function releaseHandle(handle)
    if handle then api("releaseMissionAudio", handle) end
end

local function requestHandle(key)
    local info = SW5.AUDIO[key]
    if not info then return nil, "no_entry" end
    local handle, why = api("requestMissionAudio", info.event)
    if not handle then return nil, why == "api" and "api" or "request_refused" end
    return handle
end

local function stopPoll()
    if pollTimer and isTimer(pollTimer) then killTimer(pollTimer) end
    pollTimer = nil
end

local startSequence -- forward

local function finishSequence()
    local seq = current
    current = nil
    stopPoll()
    if seq then
        releaseHandle(seq.preload and seq.preload.handle)
        seq.preload = nil
        if seq.onDone then seq.onDone(seq) end
    end
    if not current and queue[1] then startSequence(table.remove(queue, 1)) end
end

-- Solo subtitulo: el audio no esta. Se registra una vez por clave y copia.
local function missingAudio(line, why)
    local k = "audio:" .. line.key
    if not missingLogged[k] then
        missingLogged[k] = true
        report("audio_missing", line.key .. ":" .. tostring(why))
    end
    releaseHandle(line.handle)
    line.handle = nil
    line.phase = "subtitle"
    line.since = getTickCount()
    clearPrints()
    TextAudio.showText(line.key, P.subtitleOnlyMs)
end

local function nextLine()
    local seq = current
    if not seq then return end
    seq.idx = seq.idx + 1
    local key = seq.keys[seq.idx]
    if not key then return finishSequence() end
    local line = { key = key, info = SW5.AUDIO[key], phase = "loading", since = getTickCount() }
    seq.line = line
    if seq.preload and seq.preload.key == key then
        line.handle = seq.preload.handle
        seq.preload = nil
        return
    end
    releaseHandle(seq.preload and seq.preload.handle)
    seq.preload = nil
    local handle, why = requestHandle(key)
    if not handle then return missingAudio(line, why) end
    line.handle = handle
end

-- CASE 3: CLEAR_MISSION_AUDIO, CLEAR_PRINTS, STOP_CHAR_FACIAL_TALK, ENABLE_CHAR_SPEECH; CASE 4.
local function endLine(line)
    clearPrints()
    stopTalk(line)
    releaseHandle(line.handle)
    line.handle = nil
    nextLine()
end

local function startLine(seq, line, now)
    if api("playMissionAudio", line.handle) ~= true then
        return missingAudio(line, "play_refused")
    end
    line.phase = "playing"
    line.since = now
    clearPrints()                                -- CLEAR_PRINTS
    TextAudio.showText(line.key, P.lineTextMs)   -- PRINT $audio_text 10000 1 (R5 si falla)
    startTalk(line)
    -- Precarga de la siguiente linea en otro slot (LOAD_MISSION_AUDIO del otro slot)
    local nextKey = seq.keys[seq.idx + 1]
    if nextKey and not seq.preload then
        local handle = requestHandle(nextKey)
        if handle then seq.preload = { key = nextKey, handle = handle } end
    end
end

local function poll()
    local seq = current
    if not seq then return stopPoll() end
    local line = seq.line
    if not line then return nextLine() end
    local now = getTickCount()
    local probe = {}
    if line.phase == "loading" then
        probe.loaded = api("isMissionAudioLoaded", line.handle) == true
    elseif line.phase == "playing" then
        probe.finished = api("isMissionAudioFinished", line.handle) == true
        probe.speakerDead = speakerDead(line)
    end
    local action = L.lineStep(line, now, probe)
    if action == "play" then
        startLine(seq, line, now)
    elseif action == "load_timeout" then
        missingAudio(line, "load_timeout")
    elseif action == "end" then
        endLine(line)
    end
end

startSequence = function(seq)
    current = seq
    seq.idx = 0
    if not pollTimer then pollTimer = setTimer(poll, POLL_MS, 0) end
    nextLine()
end

-- keys: lista de claves de SW5.AUDIO (no excluidas). opts.dropIfBusy: si ya suena otra, esta
-- se pierde (como play_audio pisado en el SCM). onDone(seq) al terminar la ultima linea.
-- Devuelve true si la secuencia empezo o quedo en cola; false si se perdio o es invalida.
function TextAudio.playSequence(id, keys, opts, onDone)
    if type(keys) ~= "table" or #keys == 0 then return false end
    for _, key in ipairs(keys) do
        local info = SW5.AUDIO[key]
        if not info or info.excluded then return false end
    end
    opts = opts or {}
    local seq = { id = id, keys = keys, opts = opts, onDone = onDone }
    local admit = L.audioAdmit(current ~= nil, opts.dropIfBusy == true)
    if admit == "drop" then
        report("audio_dropped", tostring(id) .. ":" .. tostring(keys[1]))
        return false
    elseif admit == "queue" then
        queue[#queue + 1] = seq
        return true
    end
    startSequence(seq)
    return true
end

---------------------------------------------------------------------------
-- Barra de vida de Sweet
---------------------------------------------------------------------------
local function drawHealth()
    if not health then return end
    local sw, sh = guiGetScreenSize()
    local w, h = math.floor(sw * 0.085), math.max(8, math.floor(sh * 0.016))
    -- Debajo del contador de dinero del HUD (termina cerca del 29% de la altura).
    local x, y = math.floor(sw * 0.97) - w, math.floor(sh * 0.315)
    local fill = math.max(0, math.min(100, health)) / 100
    local scale = math.max(0.5, sh / 1080) * 0.75
    dxDrawText(SW5.HEALTH_LABEL, x - 12 + 2, y + 2, x - 12 + 2, y + h + 2, tocolor(0, 0, 0, 255), scale, "bankgothic", "right", "center")
    dxDrawText(SW5.HEALTH_LABEL, x - 12, y, x - 12, y + h, tocolor(172, 203, 241, 255), scale, "bankgothic", "right", "center")
    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 255))
    dxDrawRectangle(x + 2, y + 2, w - 4, h - 4, tocolor(57, 74, 97, 255))
    dxDrawRectangle(x + 2, y + 2, math.floor((w - 4) * fill), h - 4, tocolor(172, 203, 241, 255))
end

local drawing = false
function TextAudio.setHealth(value)
    health = tonumber(value)
    if health and not drawing then
        drawing = true
        addEventHandler("onClientRender", root, drawHealth)
    elseif not health and drawing then
        drawing = false
        removeEventHandler("onClientRender", root, drawHealth)
    end
end

---------------------------------------------------------------------------
-- Ciclo: start en sr5:begin; stop en sr5:end, reinicio de la copia y parada del resource
---------------------------------------------------------------------------
function TextAudio.start()
    missingLogged = {}
    ensureText()
end

function TextAudio.stop()
    TextAudio.setHealth(nil)
    for t in pairs(pendingTimers) do
        if isTimer(t) then killTimer(t) end
    end
    pendingTimers = {}
    queue = {}
    local seq = current
    current = nil
    stopPoll()
    if seq then
        if seq.line then
            stopTalk(seq.line)
            releaseHandle(seq.line.handle)
            seq.line.handle = nil
        end
        releaseHandle(seq.preload and seq.preload.handle)
        seq.preload = nil
    end
    speakers = {}
    if textOwned then
        api("clearMissionTexts")
        api("clearMissionHelp")
        api("releaseMissionText")
        textOwned = false
    end
end
