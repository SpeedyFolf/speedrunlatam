local defaultList = {1226,1232,1350,1568,1283,1284,
717,792,737,669,669,708,
1229,1375,1233,1258,1349,1211,1300,1285,1286,1287,1288,1289,1216, 234,
966,968,1468,3852,1257,
3851,1315,1297,1290,1294,1346,1367,1334,1331,1340,1280,3516,
718,1231,1215,996,1341,3447,
3460,1278,3463,738,716,1223,1351,1352,
1224,1220,1221,1230,
1265,1374,1373,956,1291,
1293,3578,3577,3666,1441,
1438,1440,1437,1336,
1328,1329,1330,1227,3853,
3855,640,1251,1250,1686,
1409,1365,1410,3465,7893,
1342,626,8865,1372,625}

local deleteList = {}
local poleremoverGetList = get("poleremoverDeletedList") or defaultList
local polermoeverGetVerbose = get("poleremoverVerbose") or true
local i=1
for token in string.gmatch(poleremoverGetList, "([^,]+),%s*") do
	deleteList[i] = token
	i = i + 1
end

addEvent("startThatShit", true)
function triggerRemoveObjects(res)
	triggerClientEvent("poleremoverRemoveObjects", root, deleteList)
end
addEventHandler("startThatShit", root, triggerRemoveObjects)

function quack()
	triggerClientEvent("poleremoverRemoveObjects", root, deleteList)
end
addEventHandler("onMapStarting", root, quack)
