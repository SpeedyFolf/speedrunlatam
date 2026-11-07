-- Etapas de poblacion de peatones (estado de las zonas de GTA segun el punto de la historia).
--
-- Origen: Dryxio/san-andreas-online, commit 54d4054c35f3898ee27cd652a2ba63b41832599a,
-- official-resources/native-ped-traffic/population_world.lua (setGang, buildPostIntro,
-- buildPostCleaningTheHood, buildPostGreenSabre y sus constantes), copiado sin cambios de valores.
--
-- Como en el resource oficial, cada etapa trae solo las mutaciones de la campania sobre el
-- bootstrap de main.scm que ya trae Neon: el cliente hace resetAmbientPedPopulationZonesToBootstrap()
-- y despues setAmbientPedPopulationZoneState(label, zona) por cada zona (ver client/native.lua).
-- setAmbientPedPopulationZoneState solo toca los campos y los indices de gangStrengths presentes.
-- No se copian las armas de las bandas (gangWeapons): en el oficial las aplica el servidor, no la zona.
--
-- Nombres de etapa del speedrun (def.populationStage) -> constructor oficial:
--   postIntro            -> buildPostIntro           (preset oficial post_intro)
--   postCleaningTheHood  -> buildPostCleaningTheHood (preset oficial post_cleaning_the_hood)
--   postGreenSabre       -> buildPostGreenSabre      (preset oficial post_green_sabre)
PopulationStages = {}

-- main.scm zone strengths are 1-based family columns (copiado del oficial).
local GROVE_ZONE_INDEX = 2
local BALLAS_ZONE_INDEX = 1

local function setGang(zoneStates, label, gangIndex, strength)
    local state = zoneStates[label]
    if not state then
        state = {gangStrengths = {}}
        zoneStates[label] = state
    end
    state.gangStrengths[gangIndex] = strength
end

local function buildPostIntro()
    local zones = {}
    setGang(zones, "GAN1", GROVE_ZONE_INDEX, 10)
    setGang(zones, "GAN2", GROVE_ZONE_INDEX, 10)
    return zones
end

local function buildPostCleaningTheHood()
    local zones = {}
    setGang(zones, "GAN1", GROVE_ZONE_INDEX, 40)
    setGang(zones, "GAN2", GROVE_ZONE_INDEX, 40)
    return zones
end

local function buildPostGreenSabre()
    local zones = {}
    local territoryFamilies = {
        [BALLAS_ZONE_INDEX] = {
            SUN1 = 30, SUN3A = 30, SUN3B = 30, SUN3C = 30, SUN4 = 30,
            GAN1 = 10, GAN2 = 25, GLN1 = 40, GLN2A = 40,
            LIND1A = 20, LIND1B = 20, LIND2A = 20, LIND2B = 20, LIND3 = 20,
            IWD1 = 20, IWD2 = 20, IWD3A = 20, IWD3B = 20, IWD4 = 10, IWD5 = 20,
            JEF1A = 40, JEF1B = 40, JEF2 = 40, JEF3B = 40, JEF3C = 40,
            ELS1A = 30, ELS1B = 30, ELS2 = 30, ELS3A = 30, ELS3B = 30, ELS4 = 30,
            PLS = 10, SMB1 = 10, SMB2 = 10, VIN2 = 10,
            VERO1 = 10, VERO2 = 10, VERO3 = 10, VERO4A = 10, VERO4B = 10,
        },
        [3] = {
            CHC1A = 40, CHC1B = 40, CHC2A = 40, CHC2B = 40, CHC3 = 40, CHC4A = 40, CHC4B = 40,
            EBE1 = 30, EBE2A = 30, EBE2B = 30, EBE3C = 30,
            LFL1A = 40, LFL1B = 40,
        },
        [8] = {ELCO1 = 40, ELCO2 = 40, LMEX1A = 30, LMEX1B = 30},
    }
    local allTerritories = {}
    for gangIndex, territories in pairs(territoryFamilies) do
        for label, strength in pairs(territories) do
            setGang(zones, label, gangIndex, strength)
            allTerritories[label] = true
        end
    end
    for label in pairs(allTerritories) do
        setGang(zones, label, GROVE_ZONE_INDEX, 0)
    end
    -- Green Sabre explicitly clears Grove in the hospital sub-zone even though
    -- it deliberately assigns no replacement gang there.
    setGang(zones, "JEF3A", GROVE_ZONE_INDEX, 0)
    return zones
end

local builders = {
    postIntro = buildPostIntro,
    postCleaningTheHood = buildPostCleaningTheHood,
    postGreenSabre = buildPostGreenSabre,
}

function PopulationStages.has(name)
    return type(name) == "string" and builders[name] ~= nil
end

-- Tabla nueva { [label] = estado de zona } para la etapa, o nil si no existe.
function PopulationStages.build(name)
    if not PopulationStages.has(name) then return nil end
    return builders[name]()
end

-- Etiquetas de zona de la etapa, ordenadas (el oficial las aplica en orden).
function PopulationStages.sortedLabels(zones)
    local labels = {}
    for label in pairs(zones) do labels[#labels + 1] = label end
    table.sort(labels)
    return labels
end
