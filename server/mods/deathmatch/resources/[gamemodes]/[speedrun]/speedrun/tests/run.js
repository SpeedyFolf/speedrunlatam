// Runs pure-logic Lua tests (no MTA APIs) with fengari.
const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

let passed = 0, failed = 0, currentFile = "";

function pushJsFn(name, fn) {
  lua.lua_pushjsfunction(L, fn);
  lua.lua_setglobal(L, to_luastring(name));
}
const str = (i) => to_jsstring(lauxlib.luaL_tolstring(L, i));

// __report(name, ok, message)
pushJsFn("__report", (L) => {
  const name = to_jsstring(lua.lua_tostring(L, 1));
  const ok = lua.lua_toboolean(L, 2);
  const msg = lua.lua_isnil(L, 3) ? "" : to_jsstring(lua.lua_tostring(L, 3));
  if (ok) { passed++; console.log("PASS " + currentFile + ": " + name); }
  else { failed++; console.log("FAIL " + currentFile + ": " + name + "\n     " + msg); }
  return 0;
});

function run(code, chunkname) {
  const buf = to_luastring(code);
  let st = lauxlib.luaL_loadbuffer(L, buf, buf.length, to_luastring("@" .concat(chunkname)));
  if (st === lua.LUA_OK) st = lua.lua_pcall(L, 0, 0, 0);
  if (st !== lua.LUA_OK) {
    const m = to_jsstring(lua.lua_tostring(L, -1));
    lua.lua_pop(L, 1);
    return m;
  }
  return null;
}

const prelude = `
function assertEq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assertEq") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end
function test(name, fn)
  local ok, err = pcall(fn)
  __report(name, ok, (not ok) and tostring(err) or nil)
end
`;
let err = run(prelude, "prelude");
if (err) { console.log("prelude error: " + err); process.exit(2); }

const root = path.join(__dirname, "..");
// Pure-logic dirs: logic/ and shared/ (no MTA APIs at load time).
for (const dirName of ["logic", "shared"]) {
  const dir = path.join(root, dirName);
  const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith(".lua")).sort() : [];
  for (const f of files) {
    err = run(fs.readFileSync(path.join(dir, f), "utf8"), dirName + "/" + f);
    if (err) { failed++; console.log("FAIL loading " + dirName + "/" + f + "\n     " + err); }
  }
}

const testFiles = fs.readdirSync(__dirname).filter(f => f.endsWith("_test.lua")).sort()
  .map(f => ({ label: f, file: path.join(__dirname, f) }));

// Mission resources: [misiones]/<mission>/shared/*.lua and logic/*.lua (pure, no MTA APIs at
// load time) are loaded, and [misiones]/<mission>/tests/*_test.lua are run.
const missionsRoot = path.join(root, "..", "[misiones]");
const missionDirs = fs.existsSync(missionsRoot) ? fs.readdirSync(missionsRoot).sort() : [];
for (const m of missionDirs) {
  for (const dirName of ["shared", "logic"]) {
    const dir = path.join(missionsRoot, m, dirName);
    const files = fs.existsSync(dir) ? fs.readdirSync(dir).filter(f => f.endsWith(".lua")).sort() : [];
    for (const f of files) {
      const label = m + "/" + dirName + "/" + f;
      err = run(fs.readFileSync(path.join(dir, f), "utf8"), label);
      if (err) { failed++; console.log("FAIL loading " + label + "\n     " + err); }
    }
  }
  const tdir = path.join(missionsRoot, m, "tests");
  const tfiles = fs.existsSync(tdir) ? fs.readdirSync(tdir).filter(f => f.endsWith("_test.lua")).sort() : [];
  for (const f of tfiles) testFiles.push({ label: m + "/" + f, file: path.join(tdir, f) });
}

for (const t of testFiles) {
  currentFile = t.label;
  err = run(fs.readFileSync(t.file, "utf8"), t.label);
  if (err) { failed++; console.log("FAIL " + t.label + " (file error)\n     " + err); }
}

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed > 0 ? 1 : 0);
