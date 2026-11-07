-- Estado de CJ definido por la mision: spawn, stats, vida, chaleco y armas.
-- Los stats van siempre sobre la base de partida nueva (logic/player_stats.lua).
PlayerState = {}

-- Pone los stats de PlayerStats.merge(stats, maxHealthStat). La vida maxima (24) se pone ahi
-- tambien: hay que llamarla antes de setElementHealth, si no la vida se recorta al maximo anterior.
function PlayerState.applyStats(player, stats, maxHealthStat)
    if not isElement(player) then return false end
    for id, value in pairs(PlayerStats.merge(stats, maxHealthStat)) do
        setPedStat(player, id, value)
    end
    return true
end

-- Solo la base (lobby y parada del gamemode).
function PlayerState.applyBaseline(player)
    return PlayerState.applyStats(player, nil, nil)
end

function applyPlayerState(player, ps, dim)
    if not isElement(player) or type(ps) ~= "table" then return false end
    local ok = spawnPlayer(player, ps.x, ps.y, ps.z, ps.rot or 0, ps.skin or 0, ps.interior or 0, dim or 0)
    if not ok then return false end

    setPlayerWantedLevel(player, 0)
    takeAllWeapons(player)

    PlayerState.applyStats(player, ps.stats, ps.maxHealthStat)
    setElementHealth(player, ps.health or 100)
    setPedArmor(player, ps.armor or 0)

    if type(ps.weapons) == "table" then
        for i, w in ipairs(ps.weapons) do
            local id = tonumber(w[1] or w.id)
            local ammo = tonumber(w[2] or w.ammo) or 1
            if id then giveWeapon(player, id, ammo, i == 1) end
        end
    end

    setCameraTarget(player, player)
    fadeCamera(player, true)
    return true
end

PlayerState.apply = applyPlayerState
