-- Ambiente por copia (trafico y peatones): reglas puras, sin APIs de MTA. Lua 5.1.
-- Las usan server/ambient.lua (validar y crear) y client/ambient.lua (proponer).
AmbientLogic = {}

AmbientLogic.MAX_VEHICLES = 8
AmbientLogic.MAX_PEDS = 12
AmbientLogic.PROPOSE_RADIUS = 150   -- un candidato tiene que estar a esta distancia del jugador que lo propone
AmbientLogic.DESPAWN_RADIUS = 220   -- mas lejos que esto, se borra
AmbientLogic.MIN_SEPARATION = 5     -- candidatos a menos de esto de otro se descartan
AmbientLogic.VEHICLE_MIN_PLAYER_DIST = 25 -- un auto no puede aparecer pegado al jugador que lo propone
AmbientLogic.PED_MIN_PLAYER_DIST = 5
AmbientLogic.MAX_PROPOSAL_ITEMS = 16 -- una propuesta con mas elementos se recorta
AmbientLogic.MIN_SPEED = 5
AmbientLogic.MAX_SPEED = 40
AmbientLogic.DEFAULT_SPEED = 15

-- Lista permitida de autos de trafico: autos, camionetas, camiones y motos/bicis civiles de calle.
-- Todo lo que no esta aca se rechaza: aviones y helicopteros (incl. 417, 425, 487, 497, 520, 476...),
-- barcos (430, 446, 452, 453, 454, 472, 473, 484, 493, 539, 595), trenes y vagones (449, 537, 538,
-- 569, 570, 590), RC (441, 464, 465, 501, 564, 594), remolques (435, 450, 584, 591, 606-608, 610, 611),
-- policia/emergencias/militares (407, 416, 427, 432, 433, 470, 490, 523, 528, 544, 596-599, 601),
-- vehiculos de servicio fuera de calle (406, 457, 485, 486, 530-532, 571-573, 583, 568, 444, 556, 557)
-- y los superdeportivos y de carrera, que darian ventaja en un speedrun
-- (411 Infernus, 415 Cheetah, 429 Banshee, 451 Turismo, 477 ZR-350, 494/502/503 Hotring,
-- 504 Bloodring, 506 Super GT, 541 Bullet, 522 NRG-500).
local ALLOWED_VEHICLES = {}
for _, m in ipairs({
    -- autos
    400, 401, 402, 404, 405, 409, 410, 412, 418, 419, 420, 421, 422, 424, 426, 434, 436, 438, 439,
    442, 445, 458, 466, 467, 474, 475, 478, 479, 480, 489, 491, 492, 495, 496, 500, 505, 507, 516,
    517, 518, 526, 527, 529, 533, 534, 535, 536, 540, 542, 543, 545, 546, 547, 549, 550, 551, 554,
    555, 558, 559, 560, 561, 562, 565, 566, 567, 575, 576, 579, 580, 585, 587, 589, 600, 602, 603,
    604, 605,
    -- camionetas, camiones y buses
    403, 408, 413, 414, 423, 428, 431, 437, 440, 443, 455, 456, 459, 482, 483, 498, 499, 508, 514,
    515, 524, 525, 552, 574, 578, 582, 588, 609,
    -- motos y bicis
    448, 461, 462, 463, 468, 471, 481, 509, 510, 521, 581, 586,
}) do
    ALLOWED_VEHICLES[m] = true
end
local COP_PEDS = {
    [265] = true, [266] = true, [267] = true, [280] = true, [281] = true, [282] = true,
    [283] = true, [284] = true, [285] = true, [286] = true, [287] = true, [288] = true,
}

local function isFinite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
AmbientLogic.isFinite = isFinite

local function isInt(v, lo, hi)
    return isFinite(v) and v == math.floor(v) and v >= lo and v <= hi
end

function AmbientLogic.isAllowedVehicle(model) return ALLOWED_VEHICLES[model] == true end
function AmbientLogic.isCopPed(model) return COP_PEDS[model] == true end

local function inWorld(x, y, z)
    return math.abs(x) <= 3500 and math.abs(y) <= 3500 and z >= -100 and z <= 1500
end

local function dist3(ax, ay, az, bx, by, bz)
    local dx, dy, dz = ax - bx, ay - by, az - bz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
AmbientLogic.dist3 = dist3

local function civilianPedModel(m)
    -- Rango de modelos que el oficial acepta para peatones (7..288), sin policias.
    return isInt(m, 7, 288) and not COP_PEDS[m]
end

local function positionOk(c, px, py, pz, minDist)
    if not (isFinite(c.x) and isFinite(c.y) and isFinite(c.z)) then return false, "shape" end
    if not inWorld(c.x, c.y, c.z) then return false, "world" end
    local d = dist3(c.x, c.y, c.z, px, py, pz)
    if d > AmbientLogic.PROPOSE_RADIUS then return false, "far" end
    if d < minDist then return false, "near" end
    return true
end

-- Candidato de auto propuesto por el cliente -> tabla limpia, o nil y motivo.
function AmbientLogic.normalizeVehicle(c, px, py, pz)
    if type(c) ~= "table" then return nil, "shape" end
    local ok, why = positionOk(c, px, py, pz, AmbientLogic.VEHICLE_MIN_PLAYER_DIST)
    if not ok then return nil, why end
    if not isInt(c.model, 400, 611) or not ALLOWED_VEHICLES[c.model] then return nil, "model" end
    if not civilianPedModel(c.driverModel) then return nil, "driver" end
    local speed = isFinite(c.speed) and c.speed or AmbientLogic.DEFAULT_SPEED
    speed = math.min(math.max(speed, AmbientLogic.MIN_SPEED), AmbientLogic.MAX_SPEED)
    return {
        model = c.model, driverModel = c.driverModel,
        x = c.x, y = c.y, z = c.z,
        rotation = isFinite(c.rotation) and c.rotation or 0,
        speed = speed,
    }
end

-- Candidato de peaton. GTA da direction (0..7, de a 45 grados); heading solo viene en
-- miembros de bandas. Se usa heading si viene y si no direction * 45, como el oficial.
function AmbientLogic.normalizePed(c, px, py, pz)
    if type(c) ~= "table" then return nil, "shape" end
    local ok, why = positionOk(c, px, py, pz, AmbientLogic.PED_MIN_PLAYER_DIST)
    if not ok then return nil, why end
    if not civilianPedModel(c.model) then return nil, "model" end
    local direction = isInt(c.direction, 0, 7) and c.direction or 0
    local heading = (isFinite(c.heading) and math.abs(c.heading) <= 360) and c.heading or direction * 45
    return { model = c.model, x = c.x, y = c.y, z = c.z, direction = direction, heading = heading }
end

-- true si (x, y) esta a menos de minDist (2D) de algun punto { x, y } de la lista.
function AmbientLogic.tooClose(points, x, y, minDist)
    for _, p in ipairs(points) do
        local dx, dy = p.x - x, p.y - y
        if dx * dx + dy * dy < minDist * minDist then return true end
    end
    return false
end

-- Filtra una propuesta: normaliza, respeta el tope (current de cap) y la separacion minima
-- contra occupied (lista { x, y }, se le agregan los aceptados). Devuelve aceptados, rechazados.
function AmbientLogic.acceptBatch(list, normalize, current, cap, occupied, px, py, pz)
    local accepted, rejected = {}, 0
    if type(list) ~= "table" then return accepted, 0 end
    local room = cap - current
    for i = 1, math.min(#list, AmbientLogic.MAX_PROPOSAL_ITEMS) do
        local c = normalize(list[i], px, py, pz)
        if not c or room <= 0 or AmbientLogic.tooClose(occupied, c.x, c.y, AmbientLogic.MIN_SEPARATION) then
            rejected = rejected + 1
        else
            accepted[#accepted + 1] = c
            occupied[#occupied + 1] = { x = c.x, y = c.y }
            room = room - 1
        end
    end
    return accepted, rejected
end

-- Origen de busqueda de autos, como native-vehicle-traffic/server.lua (requestCandidate):
-- primero la posicion exacta del jugador; despues de STATIONARY_SEARCH_START fallos seguidos,
-- un anillo deterministico alrededor del jugador (15 m, +10 m cada 4 intentos, hasta 45 m),
-- porque las cuatro cachés de nodos iniciales de GTA pueden quedar apuntando a un cono de camara
-- improductivo ("no-path"). session cambia el angulo entre pedidos.
-- Devuelve x, y, z, radio (0 = origen exacto).
AmbientLogic.STATIONARY_SEARCH_START = 5
AmbientLogic.STATIONARY_SEARCH_MAX_OFFSET = 45
function AmbientLogic.vehicleSearchOrigin(px, py, pz, failStreak, session)
    if failStreak < AmbientLogic.STATIONARY_SEARCH_START then return px, py, pz, 0 end
    local step = failStreak - AmbientLogic.STATIONARY_SEARCH_START
    local radius = math.min(AmbientLogic.STATIONARY_SEARCH_MAX_OFFSET, 15 + math.floor(step / 4) * 10)
    local angle = (session * 137.507764 + step * 47) * math.pi / 180
    return px + math.cos(angle) * radius, py + math.sin(angle) * radius, pz, radius
end

-- Indices de entries ({ x, y, z }) a mas de radius del jugador, de mayor a menor
-- (para poder sacarlos con table.remove sin correr los demas).
function AmbientLogic.selectDespawn(entries, px, py, pz, radius)
    local out = {}
    for i = #entries, 1, -1 do
        local e = entries[i]
        if not (isFinite(e.x) and isFinite(e.y) and isFinite(e.z)) or dist3(e.x, e.y, e.z, px, py, pz) > radius then
            out[#out + 1] = i
        end
    end
    return out
end

-- true si algun ocupante es un jugador. occupants: tabla asiento -> elemento (getVehicleOccupants);
-- typeOf(el) devuelve el tipo del elemento (getElementType). Un auto de ambiente con un jugador
-- adentro deja de ser ambiente ("adoptado"): el mantenimiento no lo borra.
function AmbientLogic.hasPlayerOccupant(occupants, typeOf)
    if type(occupants) ~= "table" then return false end
    for _, el in pairs(occupants) do
        if el and typeOf(el) == "player" then return true end
    end
    return false
end
