-- Configuracion compartida del drive-by custom (cliente + server).
-- MTA/SA:O desactiva el task nativo del jugador, asi que disparamos nosotros:
-- raycast en el cliente, validacion/dano/ammo en el server.
DriveBy = {
    -- Solo armas de una mano validas para drive-by (slot 4).
    weapons = {
        [28] = { damage = 20, vehicleDamage = 18, interval = 100, range = 55, sfx = { ids = {0, 1} } }, -- Micro SMG / Uzi
        [29] = { damage = 25, vehicleDamage = 22, interval = 90,  range = 60, sfx = { ids = {18} } },   -- SMG / MP5
        [32] = { damage = 20, vehicleDamage = 18, interval = 100, range = 55, sfx = { ids = {0, 1} } }, -- Tec9
    },
    -- Sector de apuntado. En autos, el objetivo tiene que estar al costado;
    -- en motos/bicis tambien se puede disparar hacia adelante.
    carMaxForwardDot = 0.65,
    bikeMinForwardDot = -0.20,
    -- Falloff simple por distancia: 100% cerca, 50% al alcance maximo.
    minDamageFactor = 0.50,
    -- Origen del disparo y del efecto, relativo al ped.
    fireOriginUp = 0.45,
    fireOriginSide = 1.60,
    fireOriginBikeForward = 0.80,
    muzzleSide = 1.20,
}
