test("formatTime basic", function()
  assertEq(Results.formatTime(252345), "4:12.345")
  assertEq(Results.formatTime(5007), "0:05.007")
  assertEq(Results.formatTime(0), "0:00.000")
  assertEq(Results.formatTime(3600000), "60:00.000")
end)

test("rank orders by time", function()
  local players = {a = {finishedMs = 70000, failures = 1}, b = {finishedMs = 60000, failures = 0}}
  local r = Results.rank(players, {"a", "b"})
  assertEq(r[1].id, "b"); assertEq(r[1].position, 1); assertEq(r[1].failures, 0)
  assertEq(r[2].id, "a"); assertEq(r[2].position, 2); assertEq(r[2].failures, 1)
end)

test("ties keep server order", function()
  local players = {a = {finishedMs = 60000, failures = 0}, b = {finishedMs = 60000, failures = 0}}
  local r = Results.rank(players, {"b", "a"})
  assertEq(r[1].id, "b")
  assertEq(r[2].id, "a")
end)

test("dnf last without position", function()
  local players = {a = {failures = 3, dnf = true}, b = {finishedMs = 90000, failures = 0}, c = {failures = 0}}
  local r = Results.rank(players, {"a", "b", "c"})
  assertEq(r[1].id, "b"); assertEq(r[1].position, 1)
  assertEq(r[2].id, "a"); assertEq(r[2].position, nil); assertEq(r[2].finishedMs, nil)
  assertEq(r[3].id, "c"); assertEq(r[3].position, nil)
  assertEq(r[2].failures, 3)
end)

test("isNewRecord", function()
  assertEq(Results.isNewRecord(nil, 1), true)
  assertEq(Results.isNewRecord(1000, 1000), false)
  assertEq(Results.isNewRecord(1000, 999), true)
  assertEq(Results.isNewRecord(1000, 1001), false)
end)

test("recordKind: mission record only when the mission best falls", function()
  assertEq(Results.recordKind(nil, 5000), "mission")      -- first time on the mission
  assertEq(Results.recordKind(6000, 5000), "mission")
  assertEq(Results.recordKind(5000, 5000), "personal")    -- tie keeps the old record
  assertEq(Results.recordKind(4000, 5000), "personal")    -- personal best, not the record
end)
