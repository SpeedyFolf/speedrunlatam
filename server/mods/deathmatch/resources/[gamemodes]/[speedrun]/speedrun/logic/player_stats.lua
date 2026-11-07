-- Stats base de CJ (sin APIs de MTA). Lua 5.1.
-- Se aplican antes de los stats de cada mision, al volver al lobby y al detener el gamemode, para
-- que ni el lobby ni race hereden los stats de una mision (revision final, I3).
PlayerStats = {}

-- Valores de partida nueva de GTA SA. Grasa, musculo, energia y manejo son los SET_FLOAT_STAT de
-- inicio de main.sc (bytecode del dueño 0xDAF3..0xDB0F, ver COVERAGE.md de sr-sweetsgirl §3); el
-- resto no aparece en el inicio: el 0 del motor. Vida maxima 569 = 100 de vida en MTA.
PlayerStats.BASELINE = {
    [21] = 200,  -- FAT
    [22] = 0,    -- STAMINA
    [23] = 50,   -- BODY_MUSCLE
    [24] = 569,  -- MAX_HEALTH (100 de vida)
    [69] = 0, [70] = 0, [71] = 0, [72] = 0, [73] = 0, [74] = 0, -- habilidad de armas
    [75] = 0, [76] = 0, [77] = 0, [78] = 0, [79] = 0,
    [160] = 0,   -- DRIVING_SKILL
    [165] = 800, -- ENERGY
    [223] = 0,   -- FLYING_SKILL
    [225] = 0,   -- LUNG_CAPACITY
    [229] = 0,   -- BIKE_SKILL
    [230] = 0,   -- CYCLE_SKILL
}

-- Tabla nueva [id numerico] = valor: la base, encima los stats de la mision (ids numericos o en
-- texto; se ignoran los que no son numeros) y al final maxHealthStat (stat 24) si es un numero.
function PlayerStats.merge(stats, maxHealthStat)
    local out = {}
    for id, value in pairs(PlayerStats.BASELINE) do out[id] = value end
    if type(stats) == "table" then
        for statId, value in pairs(stats) do
            local id = tonumber(statId)
            if id and type(value) == "number" then out[id] = value end
        end
    end
    if type(maxHealthStat) == "number" then out[24] = maxHealthStat end
    return out
end

return PlayerStats
