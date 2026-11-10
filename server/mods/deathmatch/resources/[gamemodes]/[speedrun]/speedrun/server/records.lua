-- Records por mision (SQLite del resource). Solo cuentas con sesion iniciada.
-- Tabla sr_records(mission, account, time_ms, date, country); un registro por (mision, cuenta).
-- country es el codigo ISO de 2 letras de ip2c al momento de guardar el record.

local DEFAULT_TOP = 10
local MAX_TOP = 30
local hasCountry = false

local function tableHasColumn(tableName, columnName)
    local rows = executeSQLQuery("PRAGMA table_info(" .. tableName .. ")")
    if type(rows) ~= "table" then return false end
    for _, row in ipairs(rows) do
        if row.name == columnName then return true end
    end
    return false
end

function initRecords()
    executeSQLQuery("CREATE TABLE IF NOT EXISTS sr_records (mission TEXT, account TEXT, time_ms INTEGER, date INTEGER, country TEXT, PRIMARY KEY(mission, account))")
    -- Bases viejas: la tabla ya existe sin country. ALTER es idempotente y se
    -- verifica despues por si el SQLite del server no lo permite.
    if not tableHasColumn("sr_records", "country") then
        pcall(executeSQLQuery, "ALTER TABLE sr_records ADD COLUMN country TEXT")
    end
    hasCountry = tableHasColumn("sr_records", "country")
end

-- Mejor tiempo de la cuenta en esa mision, o nil.
local function getAccountBest(missionId, accountName)
    local rows = executeSQLQuery("SELECT time_ms FROM sr_records WHERE mission = ? AND account = ?", missionId, accountName)
    if type(rows) == "table" and rows[1] then return tonumber(rows[1].time_ms) end
    return nil
end

-- Mejor tiempo de la cuenta para mostrarlo en el panel ("Tu mejor").
function getPersonalBest(missionId, accountName)
    if type(missionId) ~= "string" or type(accountName) ~= "string" then return nil end
    return getAccountBest(missionId, accountName)
end

-- true si timeMs mejora el mejor tiempo de la cuenta (o no habia): lo guarda.
-- country: codigo ISO de ip2c (ej. "ar") o nil si no se pudo resolver.
function saveIfBetter(missionId, accountName, timeMs, country)
    if type(missionId) ~= "string" or type(accountName) ~= "string" or type(timeMs) ~= "number" then return false end
    local previous = getAccountBest(missionId, accountName)
    if not Results.isNewRecord(previous, timeMs) then return false end
    local code = type(country) == "string" and country ~= "" and string.lower(country) or ""
    if hasCountry then
        executeSQLQuery("INSERT OR REPLACE INTO sr_records (mission, account, time_ms, date, country) VALUES (?, ?, ?, ?, ?)",
            missionId, accountName, math.floor(timeMs), getRealTime().timestamp, code)
    else
        executeSQLQuery("INSERT OR REPLACE INTO sr_records (mission, account, time_ms, date) VALUES (?, ?, ?, ?)",
            missionId, accountName, math.floor(timeMs), getRealTime().timestamp)
    end
    return true
end

-- Top N de una mision: { {account, time_ms, country}, ... }.
function getTop(missionId, limit)
    if type(missionId) ~= "string" or missionId == "" then return {} end
    local n = math.max(1, math.min(tonumber(limit) or DEFAULT_TOP, MAX_TOP))
    local sql = hasCountry
        and "SELECT account, time_ms, country FROM sr_records WHERE mission = ? ORDER BY time_ms ASC LIMIT " .. n
        or "SELECT account, time_ms FROM sr_records WHERE mission = ? ORDER BY time_ms ASC LIMIT " .. n
    local rows = executeSQLQuery(sql, missionId)
    if type(rows) ~= "table" then return {} end
    local out = {}
    for i, row in ipairs(rows) do
        out[i] = {
            account = row.account,
            time_ms = tonumber(row.time_ms) or 0,
            country = row.country or "",
        }
    end
    return out
end

-- Mejor tiempo de todas las misiones (una fila por mision): { {mission, account, time_ms, country}, ... }.
function getMissionBests()
    local sql = hasCountry
        and "SELECT mission, account, time_ms, country FROM sr_records ORDER BY mission ASC, time_ms ASC"
        or "SELECT mission, account, time_ms FROM sr_records ORDER BY mission ASC, time_ms ASC"
    local rows = executeSQLQuery(sql)
    if type(rows) ~= "table" then return {} end
    local out, seen = {}, {}
    for _, row in ipairs(rows) do
        local mission = row.mission
        if type(mission) == "string" and not seen[mission] then
            seen[mission] = true
            out[#out + 1] = {
                mission = mission,
                account = row.account,
                time_ms = tonumber(row.time_ms) or 0,
                country = row.country or "",
            }
        end
    end
    return out
end

-- Rellena el pais de un record existente sin tocar el tiempo (backfill de
-- records viejos cuando el jugador vuelve a estar online).
function updateCountry(missionId, accountName, country)
    if not hasCountry then return false end
    if type(missionId) ~= "string" or type(accountName) ~= "string" then return false end
    local code = type(country) == "string" and country ~= "" and string.lower(country) or nil
    if not code then return false end
    executeSQLQuery("UPDATE sr_records SET country = ? WHERE mission = ? AND account = ? AND (country IS NULL OR country = '')",
        code, missionId, accountName)
    return true
end

-- Mejor tiempo de todas las cuentas en la mision: { account, time_ms, country } o nil.
function getBest(missionId)
    local sql = hasCountry
        and "SELECT account, time_ms, country FROM sr_records WHERE mission = ? ORDER BY time_ms ASC LIMIT 1"
        or "SELECT account, time_ms FROM sr_records WHERE mission = ? ORDER BY time_ms ASC LIMIT 1"
    local rows = executeSQLQuery(sql, missionId)
    if type(rows) == "table" and rows[1] then
        return {
            account = rows[1].account,
            time_ms = tonumber(rows[1].time_ms),
            country = rows[1].country or "",
        }
    end
    return nil
end

initRecords()
