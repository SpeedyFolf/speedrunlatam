local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

test("stats baseline: GTA new-game values for the listed stats", function()
  local b = PlayerStats.BASELINE
  assertEq(b[21], 200, "fat"); assertEq(b[22], 0, "stamina"); assertEq(b[23], 50, "muscle")
  assertEq(b[24], 569, "max health"); assertEq(b[160], 0, "driving"); assertEq(b[165], 800, "energy")
  for id = 69, 79 do assertEq(b[id], 0, "weapon skill " .. id) end
  for _, id in ipairs({ 223, 225, 229, 230 }) do assertEq(b[id], 0, "stat " .. id) end
  assertEq(count(b), 4 + 11 + 2 + 4, "baseline size")
end)

test("stats merge: no mission stats gives the baseline (copy, not the same table)", function()
  local m = PlayerStats.merge(nil, nil)
  assertEq(count(m), count(PlayerStats.BASELINE))
  assertEq(m[24], 569)
  m[21] = 999
  assertEq(PlayerStats.BASELINE[21], 200, "baseline untouched")
end)

test("stats merge: mission stats override, extra ids kept, bad values ignored", function()
  local m = PlayerStats.merge({ [21] = 0, ["69"] = 1000, [300] = 5, [22] = "x" }, nil)
  assertEq(m[21], 0, "override")
  assertEq(m[69], 1000, "string id")
  assertEq(m[300], 5, "extra id")
  assertEq(m[22], 0, "non-number ignored")
  assertEq(m[23], 50, "untouched baseline")
end)

test("stats merge: maxHealthStat wins over stats[24]", function()
  assertEq(PlayerStats.merge({ [24] = 700 }, 1000)[24], 1000)
  assertEq(PlayerStats.merge({ [24] = 700 }, nil)[24], 700)
  assertEq(PlayerStats.merge(nil, "x")[24], 569)
end)
