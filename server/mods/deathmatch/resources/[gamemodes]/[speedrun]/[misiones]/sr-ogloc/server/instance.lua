-- Copias de "OG Loc" (SMOKE1): una por jugador, en la dimension que da la base.
-- El server/stages.lua contiene la mision (adaptada del test-resource og-loc); este
-- archivo solo maneja el ciclo de vida, la cola cliente y el registro.
Instance = {}

local instances = {}
local readyClients = {}
local logWindow = {}
local LOG_KINDS = {
    text_missing = true, text_block_missing = true, audio_missing = true, audio_dropped = true,
    prep = true, task_refused = true, task = true, chase = true, damage = true,
}
local LOG_WINDOW_MS, LOG_MAX_PER_WINDOW, LOG_MAX_LEN = 10000, 20, 200

local function clean(v)
    return (tostring(v):gsub("|", "/"):gsub("[%c]", " "))
end

function Instance.log(...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = clean(parts[i]) end
    outputServerLog("SROGLOC|" .. table.concat(parts, "|"))
end
local log = Instance.log

local function getBase()
    local base = getResourceFromName("speedrun")
    if base and getResourceState(base) == "running" then return base end
    return nil
end

local function isFromBase()
    local base = getResourceFromName("speedrun")
    return base ~= false and base ~= nil and sourceResource == base
end

function Instance.reportCompleted(inst)
    local base = getBase()
    if not base then return false end
    local ok, result = pcall(call, base, "reportCompleted", inst.player, inst.token)
    return ok and result == true
end

function Instance.reportFailed(inst, reasonKey)
    local base = getBase()
    if not base then return false end
    local ok, result = pcall(call, base, "reportFailed", inst.player, inst.token, reasonKey)
    return ok and result == true
end

function Instance.send(inst, eventName, ...)
    if not inst or inst.destroyed then return end
    if readyClients[inst.player] then
        triggerClientEvent(inst.player, eventName, resourceRoot, inst.token, ...)
    else
        inst.queue[#inst.queue + 1] = { name = eventName, n = select("#", ...), args = { ... } }
    end
end

local function flushQueue(inst)
    local queue = inst.queue
    inst.queue = {}
    for _, item in ipairs(queue) do
        triggerClientEvent(inst.player, item.name, resourceRoot, inst.token, unpack(item.args, 1, item.n))
    end
end

local function destroyFor(player, why)
    local inst = instances[player]
    if not inst then return end
    instances[player] = nil
    if inst.api then inst.api.destroy() end
    if isElement(player) and readyClients[player] then
        triggerClientEvent(player, "srogloc:end", resourceRoot, inst.token)
    end
    inst.destroyed = true
    log("cleanup", inst.nick, "token=" .. tostring(inst.token), "why=" .. tostring(why))
end

function Instance.get(player)
    return instances[player]
end

function srCreateInstance(player, dim, token)
    if not isFromBase() then return false end
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if type(dim) ~= "number" or token == nil then return false end
    destroyFor(player, "replaced")
    local inst = Stages.create(player, dim, token)
    if not inst then return false end
    instances[player] = inst
    log("create", getPlayerName(player), "dim=" .. dim, "token=" .. tostring(token))
    return true
end

function srDestroyInstance(player, token)
    if not isFromBase() then return false end
    local inst = instances[player]
    if not inst or inst.token ~= token then return false end
    destroyFor(player, "base")
    return true
end

function srInstanceGo(player, token, goTick)
    if not isFromBase() then return false end
    local inst = instances[player]
    if not inst or inst.token ~= token then return false end
    return Stages.onGo(inst) == true
end

addEvent("srogloc:clientReady", true)
addEventHandler("srogloc:clientReady", resourceRoot, function()
    local player = client
    if not isElement(player) then return end
    readyClients[player] = true
    local inst = instances[player]
    if inst then flushQueue(inst) end
end)

addEvent("srogloc:clientLog", true)
addEventHandler("srogloc:clientLog", resourceRoot, function(token, kind, detail)
    local player = client
    local inst = instances[player]
    if not inst or inst.token ~= token then return end
    if type(kind) ~= "string" or not LOG_KINDS[kind] then return end
    local now = getTickCount()
    local w = logWindow[player]
    if not w or now - w.start > LOG_WINDOW_MS then
        w = { start = now, count = 0 }
        logWindow[player] = w
    end
    w.count = w.count + 1
    if w.count > LOG_MAX_PER_WINDOW then return end
    log(kind, clean(tostring(detail or ""):sub(1, LOG_MAX_LEN)), inst.nick)
end)

addEventHandler("onPlayerQuit", root, function()
    destroyFor(source, "quit")
    readyClients[source] = nil
    logWindow[source] = nil
end)

local DEF = {
    id = "ogloc",
    title = "OG Loc",
    populationStage = "postCleaningTheHood",
    test = true,
    playerState = {
        skin = 0,
        x = 2072.9, y = -1690.6, z = 13.5, rot = 33.0,
        interior = 0,
        health = 80, armor = 0, maxHealthStat = 569, money = 410,
        stats = {},
        weapons = { { 28, 300 }, { 22, 100 } },
    },
}

local function register()
    local base = getBase()
    if base then call(base, "registerMission", DEF) end
end

addEventHandler("onResourceStart", resourceRoot, register)
addEventHandler("onResourceStart", root, function(startedResource)
    if getResourceName(startedResource) == "speedrun" then setTimer(register, 50, 1) end
end)
