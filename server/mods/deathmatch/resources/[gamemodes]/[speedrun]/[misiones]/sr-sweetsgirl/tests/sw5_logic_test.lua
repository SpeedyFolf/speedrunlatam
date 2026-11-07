-- Tests de la logica pura de sr-sweetsgirl (los corre speedrun/tests/run.js).
local L = Sw5Logic

-- rand falso: devuelve los valores de la lista en orden y anota los rangos pedidos.
local function fakeRand(values)
  local i, calls = 0, {}
  local fn = function(lo, hi)
    i = i + 1
    calls[#calls + 1] = lo .. ".." .. hi
    local v = values[i]
    assert(v ~= nil, "fakeRand sin valores")
    assert(v >= lo and v < hi, "valor fuera de rango " .. v .. " en [" .. lo .. "," .. hi .. ")")
    return v
  end
  return fn, calls
end

test("health bar starts at 100 with first drop in [2500,6000) from go", function()
  local rand, calls = fakeRand({ 3000 })
  local bar = L.newHealthBar(1000, rand)
  assertEq(bar.health, 100)
  assertEq(bar.nextDrop, 4000)
  assertEq(calls[1], "2500..6000")
end)

test("health bar does not drop until strictly after drop time", function()
  local rand = fakeRand({ 3000 })
  local bar = L.newHealthBar(0, rand)
  local changed = L.healthStep(bar, 3000, rand)
  assertEq(changed, false)
  assertEq(bar.health, 100)
end)

test("health step: next drop from now, then loss rand[2,4)", function()
  local rand, calls = fakeRand({ 3000, 5999, 3 })
  local bar = L.newHealthBar(0, rand)
  local changed, depleted = L.healthStep(bar, 3001, rand)
  assertEq(changed, true)
  assertEq(depleted, false)
  assertEq(bar.health, 97)
  assertEq(bar.nextDrop, 3001 + 5999)
  assertEq(calls[2], "2500..6000")
  assertEq(calls[3], "2..4")
end)

test("health clamps at 0 and reports depleted", function()
  local rand = fakeRand({ 2500, 2500, 3 })
  local bar = L.newHealthBar(0, rand)
  bar.health = 2
  local changed, depleted = L.healthStep(bar, 2501, rand)
  assertEq(changed, true)
  assertEq(depleted, true)
  assertEq(bar.health, 0)
end)

test("health bar range: fastest ~85 s, slowest ~300 s", function()
  -- mas rapido: siempre 2500 ms y 3 de vida
  local fast = function(lo, hi) if lo == 2 then return 3 end return 2500 end
  local bar, now = L.newHealthBar(0, fast), 0
  local done = false
  while not done do now = now + 1; local _, d = L.healthStep(bar, now, fast); done = d end
  assert(now > 80000 and now < 90000, "rapido " .. now)
  local slow = function(lo, hi) if lo == 2 then return 2 end return 5999 end
  bar, now, done = L.newHealthBar(0, slow), 0, false
  while not done do now = now + 1; local _, d = L.healthStep(bar, now, slow); done = d end
  assert(now > 295000 and now < 305000, "lento " .. now)
end)

test("phone cues fire in order at K+1500/4000/6500/9000", function()
  local K = 10000
  local due, done = L.phoneDueCues(K, 0, K + 1499)
  assertEq(#due, 0); assertEq(done, 0)
  due, done = L.phoneDueCues(K, done, K + 1500)
  assertEq(due[1], "ring1"); assertEq(done, 1)
  due, done = L.phoneDueCues(K, done, K + 9000)
  assertEq(#due, 3); assertEq(due[1], "ring2"); assertEq(due[2], "phone"); assertEq(due[3], "call"); assertEq(done, 4)
  due, done = L.phoneDueCues(K, done, K + 50000)
  assertEq(#due, 0); assertEq(done, 4)
end)

test("phone hint is ignored before the K+11000 floor", function()
  local K = 5000
  assertEq(L.phoneHintAccepted(K, K + 10999), false)
  assertEq(L.phoneHintAccepted(K, K + 11000), true)
  assertEq(L.phoneShouldAdvance(K, K + 10999, nil), false)
  -- un aviso anotado antes del piso no adelanta nada
  assertEq(L.phoneShouldAdvance(K, K + 12000, K + 10000), false)
end)

test("phone advances with accepted hint or at the K+29000 cap", function()
  local K = 0
  local adv, why = L.phoneShouldAdvance(K, 11000, 11000)
  assertEq(adv, true); assertEq(why, "hint")
  adv = L.phoneShouldAdvance(K, 28999, nil)
  assertEq(adv, false)
  adv, why = L.phoneShouldAdvance(K, 29000, nil)
  assertEq(adv, true); assertEq(why, "cap")
end)

test("red turn order is 1,2,3,4,0", function()
  local t, seq = 0, {}
  for _ = 1, 6 do t = L.nextRed(t); seq[#seq + 1] = t end
  assertEq(table.concat(seq, ","), "1,2,3,4,0,1")
end)

test("nearest tracker: incremental SCM algorithm", function()
  local n = L.newNearest()
  assertEq(n.red1, 0); assertEq(n.red2, 0); assertEq(n.range1, 99999.0)
  L.nearestAlive(n, 1, 50)   -- 1 pasa a ser el mas cercano; el 2.o hereda (0, 99999)
  assertEq(n.red1, 1); assertEq(n.range1, 50); assertEq(n.red2, 0); assertEq(n.range2, 99999.0)
  L.nearestAlive(n, 2, 30)
  assertEq(n.red1, 2); assertEq(n.red2, 1); assertEq(n.range2, 50)
  L.nearestAlive(n, 3, 40)   -- entre los dos: pasa a ser el 2.o
  assertEq(n.red1, 2); assertEq(n.red2, 3); assertEq(n.range2, 40)
  L.nearestAlive(n, 2, 80)   -- el 1.o se aleja: solo se actualiza su rango (tal cual el SCM)
  assertEq(n.red1, 2); assertEq(n.range1, 80)
  L.nearestAlive(n, 4, 60)   -- menor que range1 (80): pasa a 1.o, el viejo 1.o baja a 2.o
  assertEq(n.red1, 4); assertEq(n.red2, 2); assertEq(n.range2, 80)
  assertEq(L.isNearest(n, 4), true); assertEq(L.isNearest(n, 3), false)
end)

test("nearest tracker: dead red", function()
  local n = { red1 = 3, range1 = 10, red2 = 1, range2 = 20 }
  L.nearestDead(n, 3)
  assertEq(n.red1, 1); assertEq(n.range1, 20); assertEq(n.red2, 0); assertEq(n.range2, 99999.0)
  n = { red1 = 3, range1 = 10, red2 = 1, range2 = 20 }
  L.nearestDead(n, 1)
  assertEq(n.red1, 3); assertEq(n.red2, 0); assertEq(n.range2, 99999.0)
end)

test("heading from vector: GTA convention (0 = north, CCW)", function()
  assertEq(L.headingFromVector(0, 1), 0)
  assertEq(math.floor(L.headingFromVector(-1, 0) + 0.5), 90)
  assertEq(math.floor(L.headingFromVector(0, -1) + 0.5), 180)
  assertEq(math.floor(L.headingFromVector(1, 0) + 0.5), 270)
end)

test("dive: car heading straight at the red, close and fast", function()
  -- jugador en (0,0,0), red 10 m al norte, auto mirando al norte (0) a 20 (umbral 32)
  assertEq(L.shouldDive(0, 0, 0, 0, 10, 0.5, 20, 0, 0), true)
  -- lento (<= 5)
  assertEq(L.shouldDive(0, 0, 0, 0, 3, 0, 5.0, 0, 0), false)
  -- lejos: umbral 20*1.6 - 0.2 = 31.8 < 40
  assertEq(L.shouldDive(0, 0, 0, 0, 40, 0, 20, 0, -0.2), false)
  -- desnivel >= 1
  assertEq(L.shouldDive(0, 0, 0, 0, 10, 1.0, 20, 0, 0), false)
  -- angulo fuera de 5 grados
  assertEq(L.shouldDive(0, 0, 0, 0, 10, 0, 20, 10, 0), false)
  -- sin normalizar: 359 vs 1 no cuenta (como el SCM)
  assertEq(L.shouldDive(0, 0, 0, -0.01, 10, 0, 20, 359.5, 0), false)
end)

test("accuracy = 60 + 6 x dead", function()
  assertEq(L.accuracyFor(0), 60)
  assertEq(L.accuracyFor(4), 84)
end)

test("locate 3D and area 3D", function()
  local c = SW5.SCENE1.locate
  assertEq(L.inLocate3D(c.x + 99.9, c.y - 99.9, c.z + 49.9, c), true)
  assertEq(L.inLocate3D(c.x + 100.0, c.y, c.z, c), false)
  local a = SW5.SCENE1.helpArea
  assertEq(L.inArea3D(2760, -1960, 13, a), true)
  assertEq(L.inArea3D(2760, -1960, 18, a), false)
  assertEq(L.inArea3D(2740, -1960, 13, a), false)
end)

test("data: 5 Seville attackers as in the SCM", function()
  local reds = SW5.SCENE1.reds
  assertEq(#reds, 5)
  local models, weapons = {}, {}
  for i, r in ipairs(reds) do models[i] = r.model; weapons[i] = r.weapon end
  assertEq(table.concat(models, ","), "105,106,105,106,106")
  assertEq(table.concat(weapons, ","), "32,22,22,32,22")
end)

test("data: 28 active audio entries with events in 2000..45400", function()
  local count = 0
  for key, a in pairs(SW5.AUDIO) do
    count = count + 1
    assert(a.event >= 2000 and a.event <= 45400, key)
  end
  assertEq(count, 28)
  for _, key in ipairs(SW5.SEQ.opening) do assert(SW5.AUDIO[key], key) end
  for _, key in ipairs(SW5.SEQ.phoneCall) do assert(SW5.AUDIO[key], key) end
end)

test("data: player state from COVERAGE section 3", function()
  local ps = SW5.PLAYER_STATE
  assertEq(ps.z, 14.4109); assertEq(ps.rot, 90.6910)
  assertEq(ps.weapons[1][1], 22); assertEq(ps.weapons[1][2], 60)
  assertEq(ps.weapons[2][1], 41); assertEq(ps.weapons[2][2], 1000)
  assertEq(ps.stats[165], 800); assertEq(ps.stats[21], 200); assertEq(ps.stats[23], 50)
end)

---------------------------------------------------------------------------
-- Task 10: scene2 / salto de cut_3 / scene3
---------------------------------------------------------------------------
test("pickup gate: passengers first, then class list (and 596/420)", function()
  local A = SW5.PICKUP_MODELS
  assertEq(L.pickupGate(1, 492, A), "small")     -- Greenwood con 1 pasajero (hipotetico)
  assertEq(L.pickupGate(nil, 492, A), "small")
  assertEq(L.pickupGate(3, 492, A), "ok")        -- Greenwood, poorfamily
  assertEq(L.pickupGate(3, 405, A), "ok")        -- Sentinel, richfamily
  assertEq(L.pickupGate(3, 585, A), "ok")        -- Emperor (linea 198 sin coma), normal
  assertEq(L.pickupGate(3, 596, A), "ok")        -- copcarla
  assertEq(L.pickupGate(3, 420, A), "ok")        -- taxi
  assertEq(L.pickupGate(3, 416, A), "class")     -- ambulancia
  assertEq(L.pickupGate(3, 598, A), "class")     -- policia LV (no es copcarla)
end)

test("pickup gate: class list sizes match COVERAGE", function()
  local n = 0
  for _ in pairs(SW5.PICKUP_MODELS) do n = n + 1 end
  assertEq(n, 42 + 16 + 18 + 16 + 2)
end)

test("player car base: clamped to 0..2, default 0.5", function()
  assertEq(L.clampCarBase(nil, 0.5, 0, 2), 0.5)
  assertEq(L.clampCarBase(0 / 0, 0.5, 0, 2), 0.5)
  assertEq(L.clampCarBase(-3, 0.5, 0, 2), 0)
  assertEq(L.clampCarBase(9, 0.5, 0, 2), 2)
  assertEq(L.clampCarBase(0.71, 0.5, 0, 2), 0.71)
end)

test("sentinel timing from T0: [0] waits 1500, [1] reverses 1500..2500", function()
  assertEq(L.sentinelPhase(0, 0), "wait")
  assertEq(L.sentinelPhase(0, 1499), "wait")
  assertEq(L.sentinelPhase(0, 1500), "attack")
  assertEq(L.sentinelPhase(1, 1499), "wait")
  assertEq(L.sentinelPhase(1, 1500), "reverse")
  assertEq(L.sentinelPhase(1, 2499), "reverse")
  assertEq(L.sentinelPhase(1, 2500), "attack")
end)

test("catch-up: save when out of 50/50/20, try strictly after 800 ms, back to 1", function()
  local st = { chase = 1 }
  assertEq(L.catchupStep(st, 1000, true), nil)
  assertEq(L.catchupStep(st, 1000, false), "save")
  assertEq(st.chase, 2)
  assertEq(L.catchupStep(st, 1800, false), nil)
  assertEq(L.catchupStep(st, 1801, true), "try") -- en 2 ya no mira la distancia (como el SCM)
  L.catchupDone(st)
  assertEq(st.chase, 1)
end)

test("forward from heading: 0 = +Y, 90 = -X", function()
  local fx, fy = L.forwardFromHeading(0)
  assert(math.abs(fx) < 1e-9 and math.abs(fy - 1) < 1e-9)
  fx, fy = L.forwardFromHeading(90)
  assert(math.abs(fx + 1) < 1e-9 and math.abs(fy) < 1e-9)
end)

test("group: lost beyond 60 m 3D, back within 6 x 6 2D, not a fail", function()
  local m = { lost = false }
  assertEq(L.memberStep(m, 60.0, 50, 0), nil)
  assertEq(L.memberStep(m, 60.1, 60, 0), "lost")
  assertEq(L.memberStep(m, 80, 80, 0), nil)       -- una vez por perdida
  assertEq(L.memberStep(m, 7, 5.9, 6.0), nil)     -- |dy| no es < 6
  assertEq(L.memberStep(m, 7, 5.9, 5.9), "back")
  assertEq(m.lost, false)
end)

test("scene3 lines: insults once each, wrap and exhaustion as in the SCM", function()
  local st = L.newScene3Lines(SW5.INSULTS, SW5.NONINSULTS)
  local seen = {}
  for _ = 1, 5 do
    local key = L.pickScene3Line(st, function() return 4 end, true, true)
    assert(key and not seen[key], "repetida " .. tostring(key))
    seen[key] = true
  end
  -- start 4: GG, then wraps to 0 (GC), 1 (GD)...
  assertEq(L.pickScene3Line(st, function() return 4 end, true, true), nil)
  local st2 = L.newScene3Lines(SW5.INSULTS, SW5.NONINSULTS)
  assertEq(L.pickScene3Line(st2, function() return 4 end, true, true), "SWE5_GG")
  assertEq(L.pickScene3Line(st2, function() return 4 end, true, true), "SWE5_GC")
end)

test("scene3 lines: noninsult GB once (far, rand[0,1)), also with a Sentinel dead (rand[0,2))", function()
  local st, calls = L.newScene3Lines(SW5.INSULTS, SW5.NONINSULTS), {}
  local rand = function(lo, hi) calls[#calls + 1] = lo .. ".." .. hi; return hi - 1 end
  assertEq(L.pickScene3Line(st, rand, true, false), "SWE5_GB")
  assertEq(calls[1], "0..1")
  assertEq(L.pickScene3Line(st, rand, false, false), nil)
  assertEq(calls[2], "0..2")
  local st2 = L.newScene3Lines(SW5.INSULTS, SW5.NONINSULTS)
  assertEq(L.pickScene3Line(st2, function() return 1 end, false, true), "SWE5_GB") -- [1]=0 -> vuelve a [0]
  -- con un Sentinel muerto no hay insultos aunque este cerca
  assertEq(st2.insult[1], "SWE5_GC")
end)

local function arrivalCtx()
  local F = SW5.FINISH
  return {
    stage = "scene3",
    player = { alive = true, x = F.x + 3.9, y = F.y - 3.9, z = F.z + 1.0 },
    sweet = { alive = true, lost = false, x = F.x + 7.9, y = F.y, z = F.z + 1.0 },
    girl = { alive = true, lost = false, x = F.x, y = F.y - 7.9, z = F.z + 1.5 },
  }
end

test("arrival: player 4/4/4, Sweet and girl 8/8/4, alive and not lost", function()
  local ok = L.arrivalReady(arrivalCtx(), SW5.FINISH_PLAYER, SW5.FINISH_PEDS)
  assertEq(ok, true)
  local c = arrivalCtx(); c.stage = "scene2"
  local r; ok, r = L.arrivalReady(c, SW5.FINISH_PLAYER, SW5.FINISH_PEDS); assertEq(ok, false); assertEq(r, "stage")
  c = arrivalCtx(); c.player.x = SW5.FINISH.x + 4.0
  ok, r = L.arrivalReady(c, SW5.FINISH_PLAYER, SW5.FINISH_PEDS); assertEq(r, "player_far")
  c = arrivalCtx(); c.sweet.alive = false
  ok, r = L.arrivalReady(c, SW5.FINISH_PLAYER, SW5.FINISH_PEDS); assertEq(r, "sweet_dead")
  c = arrivalCtx(); c.girl.lost = true
  ok, r = L.arrivalReady(c, SW5.FINISH_PLAYER, SW5.FINISH_PEDS); assertEq(r, "girl_lost")
  c = arrivalCtx(); c.girl.z = SW5.FINISH.z + 4.0
  ok, r = L.arrivalReady(c, SW5.FINISH_PLAYER, SW5.FINISH_PEDS); assertEq(r, "girl_far")
  c = arrivalCtx(); c.player.alive = false
  ok, r = L.arrivalReady(c, SW5.FINISH_PLAYER, SW5.FINISH_PEDS); assertEq(r, "player_dead")
end)

test("R6: arrival before 60000 ms from go is not accepted", function()
  local ok, ms = L.minTimeOk(1000, 60999)
  assertEq(ok, false); assertEq(ms, 59999)
  ok, ms = L.minTimeOk(1000, 61000)
  assertEq(ok, true); assertEq(ms, 60000)
  ok = L.minTimeOk(nil, 999999)
  assertEq(ok, false)
end)

test("data: T0 state from COVERAGE 6.2", function()
  assertEq(SW5.SWEET.seat, 1); assertEq(SW5.GIRL.seat, 2)
  assertEq(SW5.SWEET.model, 270); assertEq(SW5.GIRL.model, 12)
  assertEq(SW5.SENTINELS[1].rot, 182.7); assertEq(SW5.SENTINELS[2].z, 13.3442)
  assertEq(SW5.SENTINEL.model, 405); assertEq(SW5.SENTINEL.driverModel, 105)
  assertEq(SW5.DRAG.playerCar, 5.0); assertEq(SW5.DRAG.sentinel, 0.1)
  for _, key in ipairs(SW5.SEQ.pickup) do assert(SW5.AUDIO[key], key) end
  for _, key in ipairs(SW5.INSULTS) do assert(SW5.AUDIO[key], key) end
  assert(SW5.AUDIO[SW5.NONINSULTS[1]])
end)

---------------------------------------------------------------------------
-- Task 11: dialogos (COVERAGE §4)
---------------------------------------------------------------------------
test("dialogue queue: start when idle, drop if busy and dropIfBusy, else queue", function()
  assertEq(L.audioAdmit(false, false), "start")
  assertEq(L.audioAdmit(false, true), "start")
  assertEq(L.audioAdmit(true, true), "drop")
  assertEq(L.audioAdmit(true, false), "queue")
end)

test("line step: loading -> play when loaded, load timeout after 5000 ms", function()
  local line = { phase = "loading", since = 1000 }
  assertEq(L.lineStep(line, 1100, { loaded = false }), nil)
  assertEq(L.lineStep(line, 1100, { loaded = true }), "play")
  assertEq(L.lineStep(line, 5999, { loaded = false }), nil)
  assertEq(L.lineStep(line, 6000, { loaded = false }), "load_timeout")
end)

test("line step: playing ends on finish, speaker death (CASE 2) or 30 s cap", function()
  local line = { phase = "playing", since = 0 }
  assertEq(L.lineStep(line, 500, {}), nil)
  assertEq(L.lineStep(line, 500, { finished = true }), "end")
  assertEq(L.lineStep(line, 500, { speakerDead = true }), "end")
  assertEq(L.lineStep(line, 29999, {}), nil)
  assertEq(L.lineStep(line, 30000, {}), "end")
end)

test("line step: subtitle-only lines last 3000 ms", function()
  local line = { phase = "subtitle", since = 0 }
  assertEq(L.lineStep(line, 2999, {}), nil)
  assertEq(L.lineStep(line, 3000, {}), "end")
end)

test("dialogue data: the 18 reachable entries are exactly the ones the server sends", function()
  local sent, order = {}, {}
  local function add(list)
    for _, k in ipairs(list) do
      if k then sent[k] = true; order[#order + 1] = k end
    end
  end
  for _, name in ipairs({ "opening", "ring", "phoneCall", "pickup", "badDriving" }) do add(SW5.SEQ[name]) end
  add(SW5.INSULTS)
  add(SW5.NONINSULTS)
  local reachable, excluded = 0, 0
  for key, info in pairs(SW5.AUDIO) do
    if info.excluded then
      excluded = excluded + 1
      assertEq(sent[key], nil, "excluded key sent: " .. key)
    else
      reachable = reachable + 1
      assertEq(sent[key], true, "reachable key never sent: " .. key)
    end
  end
  assertEq(reachable, 18)
  assertEq(excluded, 10)
  for k in pairs(sent) do assertEq(SW5.AUDIO[k] ~= nil, true, "unknown key " .. k) end
  -- Orden de la llamada de la largada y de la etapa phone
  local opening = table.concat(SW5.SEQ.opening, ",")
  assertEq(opening, "MOBRING,MSWE13A,MSWE13B,MSWE13C,MSWE13D,MSWE13E,MSWE13F,MSWE13G")
  assertEq(table.concat(SW5.SEQ.phoneCall, ","), "SWE5_FA,SWE5_FB")
  for _, item in ipairs(SW5.SEQ.openingTexts) do assertEq(SW5.TEXT_KEYS[item[1]], true) end
end)

test("dialogue data: speakers are audio_for_char[n] of the SCM", function()
  -- audio_for_char[1..29] (sweet5.sc CASE 0); [28] SWE5_EF esta comentada
  local scm = { [1] = 1, [2] = 0, [3] = 0, [4] = 0, [5] = 0, [6] = 1, [7] = 0, [8] = 0, [9] = 0,
    [10] = 3, [11] = 0, [12] = 0, [13] = 2, [14] = 2, [15] = 2, [16] = 1, [17] = 1, [18] = 1,
    [19] = 3, [20] = 3, [21] = 2, [22] = 3, [23] = 2, [24] = 2, [25] = 2, [26] = 1, [27] = 2, [29] = 0 }
  local seen = 0
  for key, info in pairs(SW5.AUDIO) do
    assertEq(info.speaker, scm[info.n], "speaker of " .. key)
    seen = seen + 1
  end
  assertEq(seen, 28)
end)

---------------------------------------------------------------------------
-- Respuesta de daño de GTA para peds de script (session B, fix 1)
---------------------------------------------------------------------------
local function hit(t)
  local h = { healthAfter = 100, loss = 0, weapon = 22, bodypart = 3, inVehicle = false, byPlayer = true,
    criticalHits = true, armor = 0 }
  for k, v in pairs(t) do h[k] = v end
  return h
end
local noRand = function() error("rand no esperado") end

test("gta damage: body shot undoes MTA's 0.33 player factor (pistol 25 -> 8.25 -> 25)", function()
  local health, why = L.gtaPedDamage(hit({ healthAfter = 91.75, loss = 8.25 }), noRand)
  assertEq(why, "scaled")
  assertEq(math.floor(health * 100 + 0.5), 7500)
end)

test("gta damage: 4 pistol body shots kill a 100 hp ped, as in GTA", function()
  local health = 100
  for _ = 1, 4 do
    local after = health - 8.25
    if after <= 0 then health = 0 break end
    health = L.gtaPedDamage(hit({ healthAfter = after, loss = 8.25 }), noRand)
  end
  assertEq(health, 0)
end)

test("gta damage: health below 1 after the hit is death (ComputeWillKillPed)", function()
  local health, why = L.gtaPedDamage(hit({ healthAfter = 17.0, loss = 8.25 }), noRand)
  assertEq(health, 0)
  assertEq(why, "scaled")
end)

test("gta damage: player headshot with a gun kills (ComputeWillForceDeath)", function()
  local health, why = L.gtaPedDamage(hit({ healthAfter = 91.75, loss = 8.25, bodypart = 9 }), noRand)
  assertEq(health, 0)
  assertEq(why, "critical")
end)

test("gta damage: no headshot kill when critical hits are off (SET_CHAR_SUFFERS_CRITICAL_HITS FALSE)", function()
  local health, why = L.gtaPedDamage(hit({ healthAfter = 91.75, loss = 8.25, bodypart = 9, criticalHits = false }), noRand)
  assertEq(why, "scaled")
  assertEq(math.floor(health * 100 + 0.5), 7500)
end)

test("gta damage: headshot in a vehicle kills whoever shoots", function()
  local health = L.gtaPedDamage(hit({ healthAfter = 95, loss = 5, bodypart = 9, byPlayer = false, inVehicle = true }), noRand)
  assertEq(health, 0)
end)

test("gta damage: ped headshot on foot kills 1 in 8 (rand [0,8) == 0), rifles always", function()
  local calls = 0
  local r0 = function(lo, hi) calls = calls + 1; assertEq(lo, 0); assertEq(hi, 8); return 0 end
  local r5 = function(lo, hi) return 5 end
  assertEq(L.gtaPedDamage(hit({ healthAfter = 95, loss = 5, bodypart = 9, byPlayer = false }), r0), 0)
  assertEq(calls, 1)
  local h = L.gtaPedDamage(hit({ healthAfter = 95, loss = 5, bodypart = 9, byPlayer = false }), r5)
  assertEq(h > 0, true)
  assertEq(L.gtaPedDamage(hit({ healthAfter = 95, loss = 5, bodypart = 9, byPlayer = false, weapon = 34 }), noRand), 0)
end)

test("gta damage: non-gun head hits are not critical", function()
  local _, why = L.gtaPedDamage(hit({ healthAfter = 95, loss = 5, bodypart = 9, weapon = 0 }), noRand)
  assertEq(why, "scaled")
end)

test("gta damage: nothing to do for no loss, a dead ped, or armour", function()
  assertEq(L.gtaPedDamage(hit({ healthAfter = 100, loss = 0 }), noRand), nil)
  assertEq(L.gtaPedDamage(hit({ healthAfter = 0, loss = 8.25 }), noRand), nil)
  assertEq(L.gtaPedDamage(hit({ healthAfter = 100, loss = 8.25, armor = 10 }), noRand), nil)
  local health, why = L.gtaPedDamage(hit({ healthAfter = 100, loss = 8.25, armor = 10, bodypart = 9 }), noRand)
  assertEq(health, 0)
  assertEq(why, "critical")
end)

test("char arrow data: GTA threat red / friendly blue, size 1.2, above the head", function()
  assertEq(table.concat(SW5.COLOR.ARROW_ENEMY, ","), "180,25,29,255")
  assertEq(table.concat(SW5.COLOR.ARROW_FRIENDLY, ","), "20,25,200,255")
  assertEq(SW5.CHAR_ARROW.size, 1.2)
  assertEq(SW5.CHAR_ARROW.zOffset >= 2.0 and SW5.CHAR_ARROW.zOffset <= 2.5, true)
end)

test("gta damage: Sweet / girlfriend take normal-ped damage x defendWeakness, no critical hits", function()
  assertEq(SW5.SWEET.defendWeakness, 1.0)  -- SPECIAL01 -> STAT_STD_MISSION
  assertEq(SW5.GIRL.defendWeakness, 1.1)   -- BFYRI -> STAT_COWARD
  -- Sweet: pistol 25 (8.25 in MTA) -> 25, also on the head (SET_CHAR_SUFFERS_CRITICAL_HITS FALSE)
  local h, why = L.gtaPedDamage(hit({ healthAfter = 91.75, loss = 8.25, bodypart = 9, criticalHits = false,
    defendWeakness = SW5.SWEET.defendWeakness }), noRand)
  assertEq(why, "scaled")
  assertEq(math.floor(h * 100 + 0.5), 7500)
  -- Girlfriend: 25 x 1.1 = 27.5
  h = L.gtaPedDamage(hit({ healthAfter = 91.75, loss = 8.25, criticalHits = false,
    defendWeakness = SW5.GIRL.defendWeakness }), noRand)
  assertEq(math.floor(h * 100 + 0.5), 7250)
end)

test("gta damage (review): healthBefore is the last known health, not after + loss", function()
  -- MTA reports after = 90 but the last known health was 100 and loss 8.25: 100 - 25 = 75
  local h, why = L.gtaPedDamage(hit({ healthBefore = 100, healthAfter = 90, loss = 8.25 }), noRand)
  assertEq(why, "scaled")
  assertEq(math.floor(h * 100 + 0.5), 7500)
  -- without healthBefore it falls back to after + loss
  h = L.gtaPedDamage(hit({ healthAfter = 90, loss = 8.25 }), noRand)
  assertEq(math.floor(h * 100 + 0.5), 7325)
end)

test("gta damage (review): a stale healthBefore never heals the ped", function()
  assertEq(L.gtaPedDamage(hit({ healthBefore = 40, healthAfter = 20, loss = 1 }), noRand), nil)
end)

test("gta damage (review): only bullets (22-34, 38) and melee (0-15) are rescaled", function()
  for _, w in ipairs({ 0, 4, 8, 15, 22, 28, 32, 34, 38 }) do
    assertEq(L.isRescaledWeapon(w), true, "weapon " .. w)
    local _, why = L.gtaPedDamage(hit({ healthAfter = 95, loss = 5, weapon = w }), noRand)
    assertEq(why, "scaled", "weapon " .. w)
  end
  -- grenade, teargas, molotov, rockets, flamethrower, rammed, run over, explosion, drowning, fall
  for _, w in ipairs({ 16, 17, 18, 35, 36, 37, 49, 50, 51, 53, 54 }) do
    assertEq(L.isRescaledWeapon(w), false, "weapon " .. w)
    assertEq(L.gtaPedDamage(hit({ healthAfter = 95, loss = 5, weapon = w }), noRand), nil, "weapon " .. w)
  end
end)
