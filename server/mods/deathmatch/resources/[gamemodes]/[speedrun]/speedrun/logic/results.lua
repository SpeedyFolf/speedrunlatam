-- Pure results helpers (no MTA APIs). Lua 5.1 compatible.
Results = {}

function Results.formatTime(ms)
    ms = math.floor(ms)
    local minutes = math.floor(ms / 60000)
    local seconds = math.floor((ms % 60000) / 1000)
    local millis = ms % 1000
    return string.format("%d:%02d.%03d", minutes, seconds, millis)
end

-- players: id -> {finishedMs, failures}; order: ids in server arrival order
function Results.rank(players, order)
    local finished, unfinished = {}, {}
    for idx, id in ipairs(order) do
        local p = players[id]
        if p then
            local entry = {id = id, finishedMs = p.finishedMs, failures = p.failures or 0, idx = idx}
            if p.finishedMs ~= nil then
                finished[#finished + 1] = entry
            else
                unfinished[#unfinished + 1] = entry
            end
        end
    end
    table.sort(finished, function(a, b)
        if a.finishedMs ~= b.finishedMs then return a.finishedMs < b.finishedMs end
        return a.idx < b.idx
    end)
    local out = {}
    for i, e in ipairs(finished) do
        out[#out + 1] = {id = e.id, finishedMs = e.finishedMs, failures = e.failures, position = i}
    end
    for _, e in ipairs(unfinished) do
        out[#out + 1] = {id = e.id, finishedMs = nil, failures = e.failures, position = nil}
    end
    return out
end

function Results.isNewRecord(previousBestMs, timeMs)
    return previousBestMs == nil or timeMs < previousBestMs
end

-- Tiempo que ya mejoro el personal de su cuenta: "mission" si ademas baja el record de la mision
-- (missionBestMs = el mejor de todas las cuentas antes de guardar), si no "personal".
function Results.recordKind(missionBestMs, timeMs)
    return Results.isNewRecord(missionBestMs, timeMs) and "mission" or "personal"
end

return Results
