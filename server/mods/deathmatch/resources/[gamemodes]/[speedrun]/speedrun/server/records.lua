-- Records por mision (SQLite del resource). Solo cuentas con sesion iniciada.
-- Tabla sr_records(mission, account, time_ms, date); un registro por (mision, cuenta).

function initRecords()
    executeSQLQuery("CREATE TABLE IF NOT EXISTS sr_records (mission TEXT, account TEXT, time_ms INTEGER, date INTEGER, PRIMARY KEY(mission, account))")
end

-- Mejor tiempo de la cuenta en esa mision, o nil.
local function getAccountBest(missionId, accountName)
    local rows = executeSQLQuery("SELECT time_ms FROM sr_records WHERE mission = ? AND account = ?", missionId, accountName)
    if type(rows) == "table" and rows[1] then return tonumber(rows[1].time_ms) end
    return nil
end

-- true si timeMs mejora el mejor tiempo de la cuenta (o no habia): lo guarda.
function saveIfBetter(missionId, accountName, timeMs)
    if type(missionId) ~= "string" or type(accountName) ~= "string" or type(timeMs) ~= "number" then return false end
    local previous = getAccountBest(missionId, accountName)
    if not Results.isNewRecord(previous, timeMs) then return false end
    executeSQLQuery("INSERT OR REPLACE INTO sr_records (mission, account, time_ms, date) VALUES (?, ?, ?, ?)",
        missionId, accountName, math.floor(timeMs), getRealTime().timestamp)
    return true
end

-- Mejor tiempo de todas las cuentas en la mision: { account, time_ms } o nil.
function getBest(missionId)
    local rows = executeSQLQuery("SELECT account, time_ms FROM sr_records WHERE mission = ? ORDER BY time_ms ASC LIMIT 1", missionId)
    if type(rows) == "table" and rows[1] then
        return { account = rows[1].account, time_ms = tonumber(rows[1].time_ms) }
    end
    return nil
end

initRecords()
