local A = AmbientLogic

local function veh(x, y, extra)
  local c = { model = 410, driverModel = 7, x = x, y = y, z = 13, rotation = 90, speed = 20 }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local function ped(x, y, extra)
  local c = { model = 7, x = x, y = y, z = 13, direction = 2 }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

test("normalizeVehicle accepts a valid candidate and clamps speed", function()
  local c = A.normalizeVehicle(veh(30, 0, { speed = 100 }), 0, 0, 13)
  assertEq(c.model, 410); assertEq(c.driverModel, 7); assertEq(c.speed, A.MAX_SPEED); assertEq(c.rotation, 90)
  assertEq(A.normalizeVehicle(veh(30, 0, { speed = "x" }), 0, 0, 13).speed, A.DEFAULT_SPEED)
  assertEq(A.normalizeVehicle(veh(30, 0, { speed = 1 }), 0, 0, 13).speed, A.MIN_SPEED)
end)

test("normalizeVehicle rejects bad shapes, far, police and cops", function()
  local _, why = A.normalizeVehicle(veh(0 / 0, 0), 0, 0, 13); assertEq(why, "shape")
  _, why = A.normalizeVehicle(veh(math.huge, 0), 0, 0, 13); assertEq(why, "shape")
  _, why = A.normalizeVehicle(veh(A.PROPOSE_RADIUS + 1, 0), 0, 0, 13); assertEq(why, "far")
  assertEq(A.normalizeVehicle(veh(A.PROPOSE_RADIUS, 0), 0, 0, 13) ~= nil, true)
  _, why = A.normalizeVehicle(veh(30, 0, { model = 596 }), 0, 0, 13); assertEq(why, "model")
  _, why = A.normalizeVehicle(veh(30, 0, { model = 399 }), 0, 0, 13); assertEq(why, "model")
  _, why = A.normalizeVehicle(veh(30, 0, { model = 410.5 }), 0, 0, 13); assertEq(why, "model")
  _, why = A.normalizeVehicle(veh(30, 0, { driverModel = 280 }), 0, 0, 13); assertEq(why, "driver")
  _, why = A.normalizeVehicle("nope", 0, 0, 13); assertEq(why, "shape")
  _, why = A.normalizeVehicle(veh(5000, 0), 4990, 0, 13); assertEq(why, "world")
end)

test("normalizePed uses heading or direction * 45", function()
  local c = A.normalizePed(ped(5, 5), 0, 0, 13)
  assertEq(c.direction, 2); assertEq(c.heading, 90)
  assertEq(A.normalizePed(ped(5, 5, { heading = 33 }), 0, 0, 13).heading, 33)
  assertEq(A.normalizePed(ped(5, 5, { direction = 9 }), 0, 0, 13).direction, 0)
  local _, why = A.normalizePed(ped(5, 5, { model = 285 }), 0, 0, 13); assertEq(why, "model")
  _, why = A.normalizePed(ped(5, 5, { model = 0 }), 0, 0, 13); assertEq(why, "model")
end)

test("acceptBatch respects cap and 5 m separation", function()
  local occupied = { { x = 0, y = 20 } }
  local list = { veh(10, 0), veh(12, 0), veh(30, 0), veh(0, 22), veh(50, 0) }
  local accepted, rejected = A.acceptBatch(list, A.normalizeVehicle, A.MAX_VEHICLES - 2, A.MAX_VEHICLES, occupied, 0, -100, 13)
  -- room = 2: (10,0) ok, (12,0) too close, (30,0) ok, the rest over the cap / too close
  assertEq(#accepted, 2); assertEq(rejected, 3)
  assertEq(accepted[1].x, 10); assertEq(accepted[2].x, 30)
  assertEq(#occupied, 3)
end)

test("acceptBatch with no room accepts nothing and survives junk", function()
  local accepted = A.acceptBatch({ ped(5, 5) }, A.normalizePed, A.MAX_PEDS, A.MAX_PEDS, {}, 0, 0, 13)
  assertEq(#accepted, 0)
  local a2, r2 = A.acceptBatch("junk", A.normalizePed, 0, A.MAX_PEDS, {}, 0, 0, 13)
  assertEq(#a2, 0); assertEq(r2, 0)
end)

test("acceptBatch trims oversized proposals", function()
  local list = {}
  for i = 1, 40 do list[i] = ped(i * 6 - 100, 0) end
  local accepted, rejected = A.acceptBatch(list, A.normalizePed, 0, 100, {}, 0, 0, 13)
  assertEq(#accepted + rejected, A.MAX_PROPOSAL_ITEMS)
end)

test("selectDespawn picks entries beyond the radius, highest index first", function()
  local entries = { { x = 0, y = 0, z = 0 }, { x = A.DESPAWN_RADIUS + 1, y = 0, z = 0 }, { x = 100, y = 0, z = 0 }, { x = 0, y = A.DESPAWN_RADIUS + 50, z = 0 } }
  local out = A.selectDespawn(entries, 0, 0, 0, A.DESPAWN_RADIUS)
  assertEq(#out, 2); assertEq(out[1], 4); assertEq(out[2], 2)
  assertEq(#A.selectDespawn({ { x = 220, y = 0, z = 0 } }, 0, 0, 0, 220), 0)
end)

test("population stages match the official builders", function()
  local z = PopulationStages.build("postCleaningTheHood")
  assertEq(z.GAN1.gangStrengths[2], 40); assertEq(z.GAN2.gangStrengths[2], 40)
  assertEq(z.GAN1.gangStrengths[1], nil)
  assertEq(PopulationStages.build("postIntro").GAN1.gangStrengths[2], 10)
  local g = PopulationStages.build("postGreenSabre")
  assertEq(g.GAN1.gangStrengths[1], 10); assertEq(g.GAN1.gangStrengths[2], 0)
  assertEq(g.JEF3A.gangStrengths[2], 0); assertEq(g.ELCO1.gangStrengths[8], 40); assertEq(g.CHC1A.gangStrengths[3], 40)
  assertEq(PopulationStages.build("nope"), nil); assertEq(PopulationStages.has(nil), false)
  local labels = PopulationStages.sortedLabels(z)
  assertEq(#labels, 2); assertEq(labels[1], "GAN1"); assertEq(labels[2], "GAN2")
  -- each build is a fresh table
  z.GAN1.gangStrengths[2] = 1
  assertEq(PopulationStages.build("postCleaningTheHood").GAN1.gangStrengths[2], 40)
end)

test("vehicle allowlist: civilian road cars and bikes only", function()
  local allowed = { 400, 410, 420, 431, 448, 462, 492, 509, 560, 567, 603 }
  for _, m in ipairs(allowed) do assertEq(A.isAllowedVehicle(m), true, "allowed " .. m) end
  local blocked = {
    497, 430, 520, 425, 476, 487, 417, 548, 553, 577, 592, 593, 511, 512, 513, 519, 460, 469, 488, 563, 447, -- aire
    446, 452, 453, 454, 472, 473, 484, 493, 539, 595,                                                          -- agua
    537, 538, 449, 569, 570, 590,                                                                              -- trenes
    441, 464, 465, 501, 564, 594,                                                                              -- RC
    435, 450, 584, 591, 606, 607, 608, 610, 611,                                                               -- remolques
    407, 416, 427, 432, 433, 470, 490, 523, 528, 544, 596, 597, 598, 599, 601,                                 -- policia/emergencias/militares
    411, 415, 429, 451, 477, 494, 502, 503, 504, 506, 541, 522,                                                -- super y carrera
    406, 444, 457, 485, 486, 530, 531, 532, 556, 557, 568, 571, 572, 573, 583, 399, 612,
  }
  for _, m in ipairs(blocked) do
    assertEq(A.isAllowedVehicle(m), false, "blocked " .. m)
    local _, why = A.normalizeVehicle(veh(30, 0, { model = m }), 0, 0, 13)
    assertEq(why, "model", "normalize " .. m)
  end
end)

test("minimum distance from the proposing player", function()
  local _, why = A.normalizeVehicle(veh(24, 0), 0, 0, 13); assertEq(why, "near")
  assertEq(A.normalizeVehicle(veh(25, 0), 0, 0, 13) ~= nil, true)
  _, why = A.normalizePed(ped(4, 0), 0, 0, 13); assertEq(why, "near")
  assertEq(A.normalizePed(ped(5, 0), 0, 0, 13) ~= nil, true)
end)

test("vehicle search origin: exact first, then a ring of 15..45 m", function()
  local x, y, z, r = A.vehicleSearchOrigin(100, 200, 13, 0, 1)
  assertEq(x, 100); assertEq(y, 200); assertEq(z, 13); assertEq(r, 0)
  _, _, _, r = A.vehicleSearchOrigin(100, 200, 13, A.STATIONARY_SEARCH_START - 1, 1); assertEq(r, 0)
  local function ring(streak)
    local rx, ry, rz, rr = A.vehicleSearchOrigin(100, 200, 13, streak, 7)
    local d = math.sqrt((rx - 100) ^ 2 + (ry - 200) ^ 2)
    assertEq(math.abs(d - rr) < 1e-6, true, "on ring"); assertEq(rz, 13)
    return rr
  end
  assertEq(ring(A.STATIONARY_SEARCH_START), 15)
  assertEq(ring(A.STATIONARY_SEARCH_START + 3), 15)
  assertEq(ring(A.STATIONARY_SEARCH_START + 4), 25)
  assertEq(ring(A.STATIONARY_SEARCH_START + 100), 45)
end)

test("player occupant: any seat, peds do not count", function()
  local typeOf = function(el) return el.kind end
  assertEq(A.hasPlayerOccupant(nil, typeOf), false)
  assertEq(A.hasPlayerOccupant({}, typeOf), false)
  assertEq(A.hasPlayerOccupant({ [0] = { kind = "ped" } }, typeOf), false)
  assertEq(A.hasPlayerOccupant({ [0] = { kind = "player" } }, typeOf), true)
  assertEq(A.hasPlayerOccupant({ [0] = { kind = "ped" }, [2] = { kind = "player" } }, typeOf), true)
end)
