-- Datos de "Sweet's Girl" (SWEET5 / hoods5), tomados de COVERAGE.md (la tabla manda).
-- Solo tablas: nada de APIs de MTA al cargar (los tests puros lo cargan igual).
-- Convenciones (COVERAGE §1): ped Z MTA = Z SCM + 1.0; Greenwood Z + 0.5; heading SCM = rotZ MTA.
SW5 = {}

SW5.MISSION_ID = "sweetsgirl"
SW5.TITLE = "Sweet's Girl"
SW5.TEXT_BLOCK = "SWEET5"
SW5.POPULATION_STAGE = "postCleaningTheHood" -- COVERAGE §3

-- Estado de CJ (COVERAGE §3): lo deja el final de sw5_cutscene_1 (cut_flag 8).
SW5.PLAYER_STATE = {
    skin = 0,
    x = 2518.4475, y = -1677.2240, z = 14.4109, -- SCM 13.4109 + 1.0
    rot = 90.6910,
    interior = 0,
    health = 100, armor = 0,
    maxHealthStat = 569,
    stats = {
        [21] = 200,  -- FAT
        [22] = 0,    -- STAMINA
        [23] = 50,   -- BODY_MUSCLE
        [160] = 0,   -- DRIVING_SKILL
        [165] = 800, -- ENERGY
        [69] = 0, [70] = 0, [71] = 0, [72] = 0, [73] = 0, [74] = 0,
        [75] = 0, [76] = 0, [77] = 0, [78] = 0, [79] = 0,
        [223] = 0, [225] = 0, [229] = 0, [230] = 0,
    },
    weapons = { { 22, 60 }, { 41, 1000 } },
}

-- LOAD_SCENE 2510.2844 -1674.0657 14.5338 (cliente: enginePreloadWorldAreaInDirection)
SW5.PRELOAD = { x = 2510.2844, y = -1674.0657, z = 14.5338, heading = 90.6910 }

SW5.MODEL = { SWEET = 270, BFYRI = 12, FAM1 = 105, FAM2 = 106, GREENWOO = 492, SENTINEL = 405 }
SW5.WEAPON = { PISTOL = 22, TEC9 = 32 }

-- Colores de blip del SCM (como drive-thru)
SW5.COLOR = {
    ENEMY = { 255, 0, 0, 255 },
    DESTINATION = { 226, 192, 99, 255 },
    FRIENDLY = { 0, 0, 255, 255 },
    -- Flecha 3D de ADD_BLIP_FOR_CHAR (BLIP_DISPLAY_BOTH): color BLIP_COLOUR_THREAT de GTA
    -- (CRadar::GetRadarTraceColour) = HUD_COLOUR_RED; con SET_BLIP_AS_FRIENDLY, HUD_COLOUR_BLUE.
    ARROW_ENEMY = { 180, 25, 29, 255 },
    ARROW_FRIENDLY = { 20, 25, 200, 255 },
}

-- Flecha sobre los peds con blip (CRadar::Draw3dMarkers, BLIP_CHAR: cono de tamaño 1.2). En MTA,
-- marcador "arrow" del servidor pegado al ped con attachElements, solo para el dueño. La altura
-- es una aproximacion de la de GTA (encima de la cabeza): se ajusta aqui si hace falta.
-- Sesion B (2026-11-05): con 1.4 la punta quedaba metida en la cabeza; el dueño pidio subirla.
SW5.CHAR_ARROW = { size = 1.2, zOffset = 2.2 }

-- Fin de sw5_cutscene_1 (COVERAGE §6.1)
SW5.HOUSE_BLIP = { x = 2775.7930, y = -1942.9087, z = 15.6576 }      -- COORD_BLIP_APPEARANCE_ENEMY
SW5.EMMET_BLIP = { x = 2444.8950, y = -1981.5243, z = 13.933, icon = 18 } -- RADAR_SPRITE_EMMETGUN
SW5.EMMET_PICKUP = { x = 2447.7732, y = -1975.6631, z = 13.0, weapon = 22, ammo = 16 }
SW5.EMMET_ARROW_OFFSET = 1.75 -- flecha 3D (MARKER_ONLY) sobre el pickup
SW5.SCENE_CAR = { x = 2745.5449, y = -1942.7405, z = 13.0394, rot = 90.0 } -- sw5_generatecar, SCM 12.5394 + 0.5

-- Policia en moto (agregado del servidor, no esta en el SCM). Aparece con la copia en Grove Street,
-- mirando hacia el inicio de CJ; lo persigue en la moto, frena y se baja para atacarlo a pie cuando
-- lo alcanza y se va al empezar la pelea en Seville (makeScene1).
SW5.COP = {
    model = 284,   -- lapdm1: policia en moto de Los Santos
    bike = 523,    -- HPV1000
    weapon = 22, ammo = 9999,
    -- Posicion que paso el dueño (/getpos, 2026-11-06). rotZ 259: mira hacia el inicio de CJ.
    x = 2436.47827, y = -1661.07385, z = 13.37212, rot = 259.0,
    driveSpeed = 40.0,    -- setPedDriveTo, renovado cada reissueMs
    reissueMs = 500,
    -- Llegada: jugador a pie a slowDist o menos -> va a slowSpeed; a exitDist o menos -> frena
    -- (setPedDriveTo a su propia posicion) y se baja cuando la moto va a stopKmh o menos, o tras
    -- stopMaxMs aunque no haya frenado del todo.
    slowDist = 30.0,
    slowSpeed = 12.0,
    stopKmh = 5.0,
    stopDriveSpeed = 1.0,
    stopMaxMs = 3000,
    exitDist = 12.0,      -- jugador a pie a esta distancia: frena y se baja
    reenterDist = 35.0,   -- jugador en un vehiculo o mas lejos que esto: vuelve a la moto
    bikeReachDist = 30.0, -- solo vuelve a la moto si la tiene a esta distancia
    killReissueMs = 3000, -- TASK_KILL_CHAR_ON_FOOT renovado
    leaveSpeed = 20.0,
}

-- sw5_scene1
SW5.SCENE1 = {
    -- LOCATE_CHAR_ANY_MEANS_3D scplayer 2775.7930 -1942.9087 15.6576 100.0 100.0 50.0
    locate = { x = 2775.7930, y = -1942.9087, z = 15.6576, rx = 100.0, ry = 100.0, rz = 50.0 },
    -- IS_CHAR_IN_AREA_3D scplayer 2782.6931 -1921.1246 11.7984 2746.0984 -1993.9053 16.9599
    helpArea = { x1 = 2782.6931, y1 = -1921.1246, z1 = 11.7984, x2 = 2746.0984, y2 = -1993.9053, z2 = 16.9599 },
    -- sw5_a_car: CREATE_CAR GREENWOO 2766.9231 -1974.3475 12.3783, heading 4.0 (Z + 0.5)
    car = { x = 2766.9231, y = -1974.3475, z = 12.8783, rot = 4.0 },
    -- TASK_SHOOT_AT_COORD 2750.9570 -1968.0157 17.9291 (la casa de la novia)
    houseTarget = { x = 2750.9570, y = -1968.0157, z = 17.9291 },
    -- red[0..4]: Z del SCM (el servidor suma 1.0 al crear; el regreso navega a Z + 1.0)
    reds = {
        { model = 105, weapon = 32, x = 2761.5156, y = -1972.0280, z = 12.5459 }, -- [0] FAM1 TEC9
        { model = 106, weapon = 22, x = 2761.5989, y = -1955.6726, z = 12.5469 }, -- [1] FAM2 PISTOL
        { model = 105, weapon = 22, x = 2768.4514, y = -1972.6053, z = 12.3837 }, -- [2] FAM1 PISTOL
        { model = 106, weapon = 32, x = 2761.551,  y = -1980.0991, z = 12.5478 }, -- [3] FAM2 TEC9
        { model = 106, weapon = 22, x = 2752.1594, y = -1979.5736, z = 14.0469 }, -- [4] FAM2 PISTOL
    },
    ammo = 99999,
    createAccuracy = 65, -- SET_CHAR_ACCURACY 65 al crear
}

-- sw5_cutscene_2 (etapa phone): pickup de la recogida
SW5.PICKUP_POINT = { x = 2764.2725, y = -1979.4939, z = 12.5394 }

---------------------------------------------------------------------------
-- sw5_scene2: compuerta del auto (COVERAGE, fila "compuerta del auto")
---------------------------------------------------------------------------
-- LOCATE_CHAR_ANY_MEANS_3D scplayer 2764.2725 -1979.4939 12.5394 4.0 4.0 4.0 TRUE
SW5.PICKUP_LOCATE = { x = 2764.2725, y = -1979.4939, z = 12.5394, rx = 4.0, ry = 4.0, rz = 4.0 }
SW5.PICKUP_MIN_PASSENGERS = 2 -- GET_MAXIMUM_NUMBER_OF_PASSENGERS < 2 -> SW5_G
SW5.WRONG_CLASS_REPEAT_MS = 500 -- PRINT_NOW sw5_16 1000 1 "cada frame": se renueva antes de que venza

-- Clases NORMAL_CAR, POOR_FAMILY_CAR, RICH_FAMILY_CAR y EXECUTIVE_CAR de vehicles.ide del dueño,
-- mas copcarla (596) y TAXI (420) por modelo (COVERAGE §2, lista bajo la tabla).
SW5.PICKUP_MODELS = {}
do
    local lists = {
        -- normal
        { 400, 418, 419, 431, 437, 442, 448, 458, 466, 467, 471, 475, 479, 482, 483, 485, 489, 491, 496,
          500, 505, 507, 518, 526, 529, 531, 540, 543, 545, 546, 547, 550, 554, 580, 582, 583, 585, 589,
          600, 603, 604, 605 },
        -- poorfamily
        { 401, 404, 410, 412, 436, 439, 440, 492, 516, 517, 527, 542, 549, 567, 575, 576 },
        -- richfamily
        { 405, 421, 426, 445, 457, 474, 477, 535, 551, 558, 559, 560, 561, 562, 565, 566, 579, 587 },
        -- executive
        { 402, 409, 411, 415, 424, 429, 434, 451, 480, 506, 533, 534, 536, 541, 555, 602 },
        -- por modelo
        { 596, 420 },
    }
    for _, list in ipairs(lists) do
        for _, model in ipairs(list) do SW5.PICKUP_MODELS[model] = true end
    end
end

---------------------------------------------------------------------------
-- sw5_cutscene_3 (excluida): estado del salto del SCM en T0 (COVERAGE §6.2, regla R3)
---------------------------------------------------------------------------
-- SET_CAR_COORDINATES sw5_playerscar 2763.9600 -1978.8977 12.5394 + SET_CAR_HEADING 0.0.
-- La Z de MTA suma la base del modelo (la calcula el cliente, acotada a 0..2; sin dato, 0.5).
SW5.PLAYER_CAR = { x = 2763.9600, y = -1978.8977, z = 12.5394, rot = 0.0 }
SW5.CAR_BASE_DEFAULT, SW5.CAR_BASE_MIN, SW5.CAR_BASE_MAX = 0.5, 0.0, 2.0

-- CLEAR_AREA_OF_CARS 2746.5037 -2001.6106 10.7750 2789.5623 -1927.1542 21.6330 (solo ambiente)
SW5.CLEAR_BOX = { x1 = 2746.5037, y1 = -2001.6106, z1 = 10.7750, x2 = 2789.5623, y2 = -1927.1542, z2 = 21.6330 }

-- CREATE_CHAR PEDTYPE_MISSION3 (Z del SCM; el servidor suma 1.0) y WARP_CHAR_INTO_CAR_AS_PASSENGER
-- con asiento SCM 0 / 1 = MTA 1 / 2.
-- defendWeakness (pedstats.dat, multiplicador del daño recibido): Sweet = SPECIAL01 ->
-- STAT_STD_MISSION 1.0; novia = BFYRI -> STAT_COWARD 1.1 (peds.ide). Ver Sw5Logic.gtaPedDamage.
SW5.SWEET = { model = 270, x = 2752.3408, y = -1948.8669, z = 16.3125, seat = 1, weapon = 22, ammo = 9999,
    defendWeakness = 1.0 }
SW5.GIRL = { model = 12, x = 2751.2817, y = -1948.8669, z = 16.3125, seat = 2, defendWeakness = 1.1 }

-- Sentinels Seville (ballascar[0..1]) en la pose final de las grabaciones 153 / 154 (carrec.img):
-- centro del auto, Z tal cual. Conductor FAM1 con pistola 99999. Vida 2500. dragCoeff x 0.1 (R1).
SW5.SENTINELS = {
    { x = 2770.5750, y = -1949.3113, z = 13.2325, rot = 182.7 }, -- [0] 153: bloquear
    { x = 2763.6440, y = -1950.2595, z = 13.3442, rot = 149.6 }, -- [1] 154: retroceder y embestir
}
SW5.SENTINEL = { model = 405, driverModel = 105, weapon = 22, ammo = 99999, health = 2500 }

-- SET_VEHICLE_AIR_RESISTANCE_MULTIPLIER (regla R1: dragCoeff x multiplicador)
SW5.DRAG = { playerCar = 5.0, sentinel = 0.1 }

---------------------------------------------------------------------------
-- sw5_scene3
---------------------------------------------------------------------------
-- ADD_BLIP_FOR_COORD 2509.0618 -1672.5270 12.3860 sw5_finish_blip + SET_BLIP_AS_FRIENDLY
SW5.FINISH = { x = 2509.0618, y = -1672.5270, z = 12.3860 }
-- Llegada: jugador 4/4/4; Sweet y la novia 8/8/4 (LOCATE_CHAR_ANY_MEANS_3D)
SW5.FINISH_PLAYER = { x = 2509.0618, y = -1672.5270, z = 12.3860, rx = 4.0, ry = 4.0, rz = 4.0 }
SW5.FINISH_PEDS = { x = 2509.0618, y = -1672.5270, z = 12.3860, rx = 8.0, ry = 8.0, rz = 4.0 }
-- Los Sentinels se van: 63/63/60 alrededor de la llegada (MISSION_CRUISE a 20)
SW5.LEAVE_LOCATE = { x = 2509.0618, y = -1672.5270, z = 12.3860, rx = 63.0, ry = 63.0, rz = 60.0 }
SW5.LEAVE_SPEED = 20.0
-- Insultos: LOCATE_CHAR_IN_CAR_CAR_3D scplayer ballascar 20.0 20.0 10.0
SW5.INSULT_RANGE = { rx = 20.0, ry = 20.0, rz = 10.0 }
-- "Que mal manejas": GET_CAR_HEALTH < 900
SW5.BAD_DRIVING_HEALTH = 900

-- Diálogos (COVERAGE §4). event = audio_sound[n] del bytecode; speaker: 0 nadie, 1 CJ, 2 Sweet, 3 novia.
-- excluded: "cut_4" (escena final, R2) o "unreachable" (el SCM nunca la pide). El cliente no las reproduce.
SW5.AUDIO = {
    MOBRING = { n = 29, event = 23000, gxt = "MAIN", speaker = 0 },
    MSWE13A = { n = 1, event = 29137, gxt = "MAIN", speaker = 1 },
    MSWE13B = { n = 2, event = 29138, gxt = "MAIN", speaker = 0 },
    MSWE13C = { n = 3, event = 29139, gxt = "MAIN", speaker = 0 },
    MSWE13D = { n = 4, event = 29140, gxt = "MAIN", speaker = 0 },
    MSWE13E = { n = 5, event = 29141, gxt = "MAIN", speaker = 0 },
    MSWE13F = { n = 6, event = 29142, gxt = "MAIN", speaker = 1 },
    MSWE13G = { n = 7, event = 29143, gxt = "MAIN", speaker = 0 },
    SWE5_FA = { n = 8, event = 38226, gxt = "SWEET5", speaker = 0 },
    SWE5_FB = { n = 9, event = 38227, gxt = "SWEET5", speaker = 0 },
    SWE5_GH = { n = 10, event = 38235, gxt = "SWEET5", speaker = 3, excluded = "unreachable" }, -- inalcanzable
    SWE5_CA = { n = 11, event = 38216, gxt = "SWEET5", speaker = 0, excluded = "unreachable" }, -- inalcanzable
    SWE5_CC = { n = 12, event = 38218, gxt = "SWEET5", speaker = 0 },
    SWE5_GA = { n = 13, event = 38228, gxt = "SWEET5", speaker = 2 },
    SWE5_GC = { n = 14, event = 38230, gxt = "SWEET5", speaker = 2 },
    SWE5_GD = { n = 15, event = 38231, gxt = "SWEET5", speaker = 2 },
    SWE5_GE = { n = 16, event = 38232, gxt = "SWEET5", speaker = 1 },
    SWE5_GF = { n = 17, event = 38233, gxt = "SWEET5", speaker = 1 },
    SWE5_GG = { n = 18, event = 38234, gxt = "SWEET5", speaker = 1 },
    SWE5_GJ = { n = 19, event = 38236, gxt = "SWEET5", speaker = 3, excluded = "unreachable" }, -- inalcanzable
    SWE5_GK = { n = 20, event = 38237, gxt = "SWEET5", speaker = 3, excluded = "unreachable" }, -- inalcanzable
    SWE5_GB = { n = 21, event = 38229, gxt = "SWEET5", speaker = 2 },
    SWE5_GL = { n = 22, event = 38238, gxt = "SWEET5", speaker = 3, excluded = "unreachable" }, -- inalcanzable
    SWE5_EA = { n = 23, event = 38221, gxt = "SWEET5", speaker = 2, excluded = "cut_4" }, -- cut_4, excluida (R2)
    SWE5_EB = { n = 24, event = 38222, gxt = "SWEET5", speaker = 2, excluded = "cut_4" }, -- cut_4, excluida (R2)
    SWE5_EC = { n = 25, event = 38223, gxt = "SWEET5", speaker = 2, excluded = "cut_4" }, -- cut_4, excluida (R2)
    SWE5_ED = { n = 26, event = 38224, gxt = "SWEET5", speaker = 1, excluded = "cut_4" }, -- cut_4, excluida (R2)
    SWE5_EE = { n = 27, event = 38225, gxt = "SWEET5", speaker = 2, excluded = "cut_4" }, -- cut_4, excluida (R2)
}

-- Secuencias de audio que manda el servidor (server/stages.lua; COVERAGE §4)
SW5.SEQ = {
    -- Llamada de la cinemática excluida sw5_cutscene_1 (R2): MOBRING y después MSWE13A..G.
    opening = { "MOBRING", "MSWE13A", "MSWE13B", "MSWE13C", "MSWE13D", "MSWE13E", "MSWE13F", "MSWE13G" },
    -- PRINT SW5_A2 6000 1 y PRINT SW5_17 6000 1 (en cola) al terminar la llamada.
    openingTexts = { { "SW5_A2", 6000 }, { "SW5_17", 6000 } },
    ring = { "MOBRING" },
    phoneCall = { "SWE5_FA", "SWE5_FB" },
    -- Recogida (R2): SWE5_CC sobre el juego en T0; ninguna etapa espera a que termine.
    pickup = { "SWE5_CC" },
    -- scene3: "que mal manejas", una vez
    badDriving = { "SWE5_GA" },
}

-- scene3: insult[0..4] = audio 14..18 y noninsult[0] = 21 (noninsult[1] queda en 0), de
-- mission_start_hood5. Se copian por copia (Sw5Logic.newScene3Lines): cada linea suena una vez.
SW5.INSULTS = { "SWE5_GC", "SWE5_GD", "SWE5_GE", "SWE5_GF", "SWE5_GG" }
SW5.NONINSULTS = { "SWE5_GB", false }

-- Etiqueta de la barra (equivalente de SW5_A3; no hay API para leer el GXT)
SW5.HEALTH_LABEL = "VIDA DE SWEET"

-- Claves de texto que el cliente puede pedir mostrar (lista cerrada)
SW5.TEXT_KEYS = {
    SW5_A2 = true, SW5_17 = true, SW5_J = true, SW5_19 = true, SW5_L = true, SW5_M = true,
    SW5_14 = true, SW5_G = true, sw5_16 = true, SW5_I = true, sw5_T = true, sw5_U = true,
}
