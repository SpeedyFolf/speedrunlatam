bigGUI = false
travelScreenDuration = 3000 + 2950

-- DEBUG_WIDTH = 800
-- DEBUG_HEIGHT = 600

function bindKeys()
	local keys = getBoundKeys("Toggle scoreboard")
	if (not keys) then
		keys = {["F1"] = "down"}
	end
	for key, state in pairs(keys) do
		bindKey(key, "both", toggleBigGUI)
	end
end

function toggleBigGUI(key, state)
	bigGUI = state == "down"
	if (bigGUI) then
		showGUIComponents("bigInfoLabelMap", "bigInfoLabelFolderName", "bigInfoLabelFolderPath", "bigInfoLabelAuthor", "bigInfoLabelType", "bigInfoLabelVW", "bigInfoLabelGM", "bigInfoLabelRS", "bigInfoLabelOther", "bigInfoContentMap", "bigInfoContentFolderName", "bigInfoContentFolderPath", "bigInfoContentAuthor", "bigInfoContentType", "bigInfoContentVW", "bigInfoContentGM", "bigInfoContentRS", "bigInfoContentOther", "bigInfoContentPing", "bigInfoLabelPing", "bigInfoContentFPS", "bigInfoLabelFPS", "bigInfoLabelDescription", "bigInfoContentDescription", "bigInfoLabelSpawns", "bigInfoLabelChecks", "bigInfoLabelObjects", "bigInfoLabelRemovedObjects", "bigInfoLabelPickups", "bigInfoLabelRegularPickups", "bigInfoContentSpawns", "bigInfoContentChecks", "bigInfoContentObjects", "bigInfoContentRemovedObjects", "bigInfoContentPickups", "bigInfoContentRegularPickups")
		hideGUIComponents("cornerLabelFolderName", "cornerContentFolderName", "cornerLabelFolderPath", "cornerContentFolderPath", "cornerLabelMap", "cornerContentMap", "cornerLabelAuthor", "cornerContentAuthor", "cornerLabelFPS", "cornerContentFPS", "cornerLabelPing", "cornerContentPing", "cornerLabelConf", "cornerLabelConfG", "cornerLabelConfR", "cornerLabelConfW")
	else
		showGUIComponents("cornerLabelFolderName", "cornerContentFolderName", "cornerLabelFolderPath", "cornerContentFolderPath", "cornerLabelMap", "cornerContentMap", "cornerLabelAuthor", "cornerContentAuthor", "cornerLabelFPS", "cornerContentFPS", "cornerLabelPing", "cornerContentPing", "cornerLabelConf", "cornerLabelConfG", "cornerLabelConfR", "cornerLabelConfW")
		hideGUIComponents("bigInfoLabelMap", "bigInfoLabelFolderName", "bigInfoLabelFolderPath", "bigInfoLabelAuthor", "bigInfoLabelType", "bigInfoLabelVW", "bigInfoLabelGM", "bigInfoLabelRS", "bigInfoLabelOther", "bigInfoContentMap", "bigInfoContentFolderName", "bigInfoContentFolderPath", "bigInfoContentAuthor", "bigInfoContentType", "bigInfoContentVW", "bigInfoContentGM", "bigInfoContentRS", "bigInfoContentOther", "bigInfoContentPing", "bigInfoLabelPing", "bigInfoContentFPS", "bigInfoLabelFPS", "bigInfoLabelDescription", "bigInfoContentDescription", "bigInfoLabelSpawns", "bigInfoLabelChecks", "bigInfoLabelObjects", "bigInfoLabelRemovedObjects", "bigInfoLabelPickups", "bigInfoLabelRegularPickups", "bigInfoContentSpawns", "bigInfoContentChecks", "bigInfoContentObjects", "bigInfoContentRemovedObjects", "bigInfoContentPickups", "bigInfoContentRegularPickups")
	end
end

function buildGUI()
	local screenWidth, screenHeight = guiGetScreenSize()
	screenWidth = DEBUG_WIDTH or screenWidth
	screenHeight = DEBUG_HEIGHT or screenHeight
	bigUiFont = screenHeight / 750
	vertiStart = screenHeight / 900 * 275
	vertiOffset = bigUiFont * 18
	horiOffset = bigUiFont * 78
	g_dxGUI = {
		-- Bottom Left Corner
		-- Labels & Content
		cornerLabelPing = dxText:create("Ping:", 4, screenHeight - 110, false, "default-bold", 1.2, "left"),
		cornerContentPing = dxText:create("0", 45, screenHeight - 110, false, "default-bold", 1.2, "left"),

		cornerLabelFPS = dxText:create("FPS:", 4, screenHeight - 90, false, "default-bold", 1.2, "left"),
		cornerContentFPS = dxText:create("0", 45, screenHeight - 90, false, "default-bold", 1.2, "left"),

		cornerLabelConf = dxText:create("Conf:", 4, screenHeight - 70, false, "default-bold", 1.2, "left"),
		cornerLabelConfG = dxText:create("Gm", 45, screenHeight - 70, false, "default-bold", 1.2, "left"),
		cornerLabelConfR = dxText:create("Rs", 75, screenHeight - 70, false, "default-bold", 1.2, "left"),
		cornerLabelConfW = dxText:create("Vw", 99, screenHeight - 70, false, "default-bold", 1.2, "left"),

		cornerLabelAuthor = dxText:create("By:", 4, screenHeight - 50, false, "default-bold", 1.2, "left"),
		cornerContentAuthor = dxText:create("<unknown>", 45, screenHeight - 50, false, "default-bold", 1.2, "left"),

		cornerLabelMap = dxText:create("Map:", 4, screenHeight - 30, false, "default-bold", 1.2, "left"),
		cornerContentMap = dxText:create("<unknown>", 45, screenHeight - 30, false, "default-bold", 1.2, "left"),

		-- Big Info (Tab)
		-- Labels
		bigInfoLabelMap = dxText:create("Map Name:", 6, vertiStart + vertiOffset, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelAuthor = dxText:create("Author:", 6, vertiStart + vertiOffset * 2, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelType = dxText:create("Type:", 6, vertiStart + vertiOffset * 3, false, "default-bold", bigUiFont, "left"),

		bigInfoLabelVW = dxText:create("Vehicle Weapons:", 6, vertiStart + vertiOffset * 5, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelGM = dxText:create("Ghost Mode:", 6, vertiStart + vertiOffset * 6, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelRS = dxText:create("Respawn:", 6, vertiStart + vertiOffset * 7, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelOther = dxText:create("Other:", 6, vertiStart + vertiOffset * 8, false, "default-bold", bigUiFont, "left"),

		bigInfoLabelSpawns = dxText:create("Spawnpoints:", 6, vertiStart + vertiOffset * 10, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelChecks = dxText:create("Checkpoints:", 6, vertiStart + vertiOffset * 11, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelObjects = dxText:create("Added Objects:", 6, vertiStart + vertiOffset * 12, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelRemovedObjects = dxText:create("Removed Objects:", 6, vertiStart + vertiOffset * 13, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelPickups = dxText:create("Race Pickups:", 6, vertiStart + vertiOffset * 14, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelRegularPickups = dxText:create("Pickups:", 6, vertiStart + vertiOffset * 15, false, "default-bold", bigUiFont, "left"),

		bigInfoLabelPing = dxText:create("Ping:", 6, vertiStart + vertiOffset * 17, false, "default-bold", bigUiFont, "left"),
		bigInfoLabelFPS = dxText:create("FPS:", 6, vertiStart + vertiOffset * 18, false, "default-bold", bigUiFont, "left"),

		-- Content
		bigInfoContentMap = dxText:create("UNKNOWN", horiOffset * 1.15, vertiStart + vertiOffset, false, "default-bold", bigUiFont, "left"),
		bigInfoContentAuthor = dxText:create("UNKNOWN", horiOffset * 1.15, vertiStart + vertiOffset * 2, false, "default-bold", bigUiFont, "left"),
		bigInfoContentType = dxText:create("UNKNOWN", horiOffset * 1.15, vertiStart + vertiOffset * 3, false, "default-bold", bigUiFont, "left"),

		bigInfoContentVW = dxText:create("UNKNOWN", horiOffset * 1.47, vertiStart + vertiOffset * 5, false, "default-bold", bigUiFont, "left"),
		bigInfoContentGM = dxText:create("UNKNOWN", horiOffset * 1.47, vertiStart + vertiOffset * 6, false, "default-bold", bigUiFont, "left"),
		bigInfoContentRS = dxText:create("UNKNOWN", horiOffset * 1.47, vertiStart + vertiOffset * 7, false, "default-bold", bigUiFont, "left"),
		bigInfoContentOther = dxText:create("UNKNOWN", horiOffset * 1.47, vertiStart + vertiOffset * 8, false, "default-bold", bigUiFont, "left"),

		bigInfoContentSpawns = dxText:create("UNKNOWN", horiOffset * 1.53, vertiStart + vertiOffset * 10, false, "default-bold", bigUiFont, "left"),
		bigInfoContentChecks = dxText:create("UNKNOWN", horiOffset * 1.53, vertiStart + vertiOffset * 11, false, "default-bold", bigUiFont, "left"),
		bigInfoContentObjects = dxText:create("UNKNOWN", horiOffset * 1.53, vertiStart + vertiOffset * 12, false, "default-bold", bigUiFont, "left"),
		bigInfoContentRemovedObjects = dxText:create("UNKNOWN", horiOffset * 1.53, vertiStart + vertiOffset * 13, false, "default-bold", bigUiFont, "left"),
		bigInfoContentPickups = dxText:create("UNKNOWN", horiOffset * 1.53, vertiStart + vertiOffset * 14, false, "default-bold", bigUiFont, "left"),
		bigInfoContentRegularPickups = dxText:create("UNKNOWN", horiOffset * 1.53, vertiStart + vertiOffset * 15, false, "default-bold", bigUiFont, "left"),

		bigInfoContentPing = dxText:create("UNKNOWN", horiOffset * 0.5, vertiStart + vertiOffset * 17, false, "default-bold", bigUiFont, "left"),
		bigInfoContentFPS = dxText:create("UNKNOWN", horiOffset * 0.5, vertiStart + vertiOffset * 18, false, "default-bold", bigUiFont, "left"),

		-- Description Label & Content
		bigInfoLabelDescription = dxText:create("Map Description:", screenWidth * 0.25, screenHeight * 0.75, false, "default-bold", 1, "left"),
		bigInfoContentDescription = dxText:create("UNKNOWN", screenWidth * 0.25, screenHeight * 0.75 + 15, false, "default-bold", 1, "left"),

		-- Traveling Screen
		travelTextHeader = dxText:create("Travelling to", screenWidth / 2, screenHeight / 2 - 230, false, "bankgothic", 0.60, "center"),
		travelTextName = dxText:create("<mapname>", screenWidth / 2, screenHeight / 2 - 170, false, "bankgothic", 0.70, "center"),
		travelTextAuthor = dxText:create("<author>", screenWidth / 2, screenHeight / 2 - 140, false, "bankgothic", 0.70, "center"),
		travelTextConfigs = dxText:create("<conf>", screenWidth * 0.3, screenHeight / 2 - 60, false, "bankgothic", 0.70, "left"),
		travelTextFacts = dxText:create("<facts>", screenWidth * 0.52, screenHeight / 2 - 60, false, "bankgothic", 0.70, "left"),

		travelTextDescription = dxText:create("<description>", screenWidth / 2, screenHeight / 2 - 140, false, "bankgothic", 0.70, "center"),
	}

	-- Assign conditional fields after table creation
	-- Bottom Left Corner
	g_dxGUI.cornerLabelFolderPath = dxText:create("Path:", 4, screenHeight - 10, false, "default-bold", 1.2, "left")
	g_dxGUI.cornerContentFolderPath = dxText:create("<unknown>", 45, screenHeight - 10, false, "default-bold", 1.2, "left")

	-- Big Info (Tab)
	g_dxGUI.bigInfoLabelFolderPath = dxText:create("Folder Path:", 6, vertiStart, false, "default-bold", bigUiFont, "left")
	g_dxGUI.bigInfoContentFolderPath = dxText:create("UNKNOWN", horiOffset * 1.15, vertiStart, false, "default-bold", bigUiFont, "left")

	-- Bottom Left Corner
	g_dxGUI.cornerLabelFolderName = dxText:create("File:", 4, screenHeight - 10, false, "default-bold", 1.2, "left")
	g_dxGUI.cornerContentFolderName = dxText:create("<unknown>", 45, screenHeight - 10, false, "default-bold", 1.2, "left")

	-- Big Info (Tab)
	g_dxGUI.bigInfoLabelFolderName = dxText:create("Folder Name:", 6, vertiStart, false, "default-bold", bigUiFont, "left")
	g_dxGUI.bigInfoContentFolderName = dxText:create("UNKNOWN", horiOffset * 1.15, vertiStart, false, "default-bold", bigUiFont, "left")


	g_GUI = {
		travelImage = guiCreateStaticImage(screenWidth / 2 - 160, screenHeight / 2 - 280, 320, 25, "img/R.png", false, nil),
	}
	g_dxGUI["travelTextHeader"]:color(240,240,240)
	g_dxGUI["travelTextDescription"]:align("center","top")
	g_dxGUI["travelTextDescription"]:boundingBox(0.2,0.5,0.8,1,true)
	g_dxGUI["travelTextDescription"]:wordWrap(true)

	g_dxGUI["bigInfoContentDescription"]:align("left", "top")
	g_dxGUI["bigInfoContentDescription"]:boundingBox(screenWidth * 0.25, screenHeight * 0.75 + 12, screenWidth * 0.9, screenHeight, false)

	hideGUIComponents("cornerLabelFolderName", "cornerContentFolderName", "cornerLabelFolderPath", "cornerContentFolderPath", "cornerLabelMap", "cornerContentMap", "cornerLabelAuthor", "cornerContentAuthor", "cornerLabelFPS", "cornerContentFPS", "cornerLabelPing", "cornerContentPing", "cornerLabelConf", "cornerLabelConfG", "cornerLabelConfR", "cornerLabelConfW")
	hideGUIComponents("bigInfoLabelMap", "bigInfoLabelFolderName", "bigInfoLabelFolderPath", "bigInfoLabelAuthor", "bigInfoLabelType", "bigInfoLabelVW", "bigInfoLabelGM", "bigInfoLabelRS", "bigInfoLabelOther", "bigInfoContentMap", "bigInfoContentFolderName", "bigInfoContentFolderPath", "bigInfoContentAuthor", "bigInfoContentType", "bigInfoContentVW", "bigInfoContentGM", "bigInfoContentRS", "bigInfoContentOther", "bigInfoContentPing", "bigInfoLabelPing", "bigInfoContentFPS", "bigInfoLabelFPS", "bigInfoLabelDescription", "bigInfoContentDescription", "bigInfoLabelSpawns", "bigInfoLabelChecks", "bigInfoLabelObjects", "bigInfoLabelPickups", "bigInfoLabelRegularPickups", "bigInfoLabelRemovedObjects", "bigInfoContentSpawns", "bigInfoContentChecks", "bigInfoContentObjects", "bigInfoContentPickups", "bigInfoContentRegularPickups", "bigInfoContentRemovedObjects")
	hideGUIComponents("travelImage", "travelTextHeader", "travelTextName", "travelTextAuthor", "travelTextConfigs", "travelTextFacts", "travelTextDescription")
end

addEventHandler("onClientResourceStart", resourceRoot,
	function()
		bindKeys()
		buildGUI()
	end
)

-- -----------
-- Map changed
-- -----------

function showTravelingScreen()
	if (
		g_MapInfo.racetype == "R" or
		g_MapInfo.racetype == "SR" or
		g_MapInfo.racetype == "DD" or
		g_MapInfo.racetype == "TW" or
		g_MapInfo.racetype == "MG" or
		g_MapInfo.racetype == "F"
	) then
		guiStaticImageLoadImage(g_GUI["travelImage"], "img/" .. g_MapInfo.racetype .. ".png")
	else
		guiStaticImageLoadImage(g_GUI["travelImage"], "img/R.png")
	end
	if not g_MapInfo.racetype then
		g_MapInfo.racetype = "???"
	end

	local typeTag = "[" .. g_MapInfo.racetype .. "] "
	g_dxGUI["travelTextName"]:text(typeTag .. (g_MapInfo.name or g_MapInfo.resname or "<none>"))
	g_dxGUI["travelTextAuthor"]:text(g_MapInfo.author and "Author: " .. g_MapInfo.author or "")
	g_dxGUI["travelTextDescription"]:text(g_MapInfo.description or "")
	showGUIComponents("travelImage", "travelTextHeader", "travelTextName", "travelTextAuthor", "travelTextConfigs", "travelTextFacts", "travelTextDescription")
	setTimer(hideTravelingScreen, travelScreenDuration, 1)

	-- Details
	local text5 = ""
	text5 = text5 .. (g_MapInfo.ghostmode and "◼ Ghost mode\n" or "◻ Ghost mode\n")
	text5 = text5 .. (g_MapInfo.respawn == "timelimit" and "◼ Respawn: " .. g_MapInfo.respawntime / 1000 .. " sec\n" or "◻ Respawn\n")
	text5 = text5 .. (g_MapInfo.vehicleweapons and "◼ Vehicle weapons\n" or "◻ Vehicle weapons\n")
	text5 = text5 .. (g_MapInfo.allowonfoot and "◼ Exiting vehicles\n" or "◻ Exiting vehicles\n")
	if (g_MapInfo.allowonfoot) then
		-- Super sprint is currently enabled by using setGlitchEnabled in a serverside script instead of a map setting and therefore checked by using isGlitchEnabled
		-- If this is changed in the future, remember to update this behaviour in Race Information UI to support the movementglitches map setting
		-- Support for limited stamina maps: MTA:SA does not currently natively support stamina the way GTA:SA singleplayer does
		text5 = text5 .. (g_MapInfo.fastsprint and "◼ Super sprint\n" or "◻ Super sprint\n")
		-- text5 = text5 .. (g_MapInfo.falloffbike and "◼ Fall off bikes\n" or "◻ Fall off bikes\n")
		-- text5 = text5 .. (g_MapInfo.fistfights and "◼ Fighting\n" or "◻ Fighting\n")
	end

	local text6 = ""
	text6 = text6 .. (g_MapInfo.numSpawnpoints or 0) .. " Spawnpoint" .. (g_MapInfo.numSpawnpoints ~= 1 and "s" or "") .. "\n"
	text6 = text6 .. (g_MapInfo.numCheckpoints or 0) .. " Checkpoint" .. (g_MapInfo.numCheckpoints ~= 1 and "s" or "") .. "\n"
	text6 = text6 .. (g_MapInfo.numObjects or 0) .. " Added Object" .. (g_MapInfo.numObjects ~= 1 and "s" or "") .. "\n"
	text6 = text6 .. (g_MapInfo.numRemovedObjects or 0) .. " Removed Object" .. (g_MapInfo.numRemovedObjects ~= 1 and "s" or "") .. "\n"
	text6 = text6 .. (g_MapInfo.numPickups or 0) .. " Race Pickup" .. (g_MapInfo.numPickups ~= 1 and "s" or "") .. "\n"
	text6 = text6 .. (g_MapInfo.numRegularPickups or 0) .. " Pickup" .. (g_MapInfo.numRegularPickups ~= 1 and "s" or "") .. "\n"
	g_dxGUI["travelTextConfigs"]:text(text5)
	g_dxGUI["travelTextFacts"]:text(text6)
end

function hideTravelingScreen()
	hideGUIComponents("travelImage", "travelTextHeader", "travelTextName", "travelTextAuthor", "travelTextConfigs", "travelTextFacts", "travelTextDescription")
end

function updateBottomLeftInformation()
	local typeTag = "[" .. (g_MapInfo.racetype or "???") .. "] "
	g_dxGUI.cornerContentMap:text(typeTag .. (g_MapInfo.name or "<none>"))
	if g_Options.mapfolder == "fullpath" then
		g_dxGUI.cornerContentFolderPath:text((g_MapInfo.respath and g_MapInfo.resname) and (g_MapInfo.respath .. "/" .. g_MapInfo.resname) or "<none>")
	else
		g_dxGUI.cornerContentFolderName:text(g_MapInfo.resname or "<none>")
	end
	g_dxGUI.cornerContentAuthor:text(g_MapInfo.author or "<none>")

	g_dxGUI.bigInfoContentMap:text(g_MapInfo.name or "<none>")
	g_dxGUI.bigInfoContentAuthor:text(g_MapInfo.author or "<none>")
	if g_Options.mapfolder == "fullpath" then
		g_dxGUI.bigInfoContentFolderPath:text((g_MapInfo.respath and g_MapInfo.resname) and (g_MapInfo.respath .. "/" .. g_MapInfo.resname) or "<none>")
	else
		g_dxGUI.bigInfoContentFolderName:text(g_MapInfo.resname or "<none>")
	end

	g_dxGUI.bigInfoContentSpawns:text(tostring(g_MapInfo.numSpawnpoints) or "0")
	g_dxGUI.bigInfoContentChecks:text(tostring(g_MapInfo.numCheckpoints) or "0")
	g_dxGUI.bigInfoContentObjects:text(tostring(g_MapInfo.numObjects) or "0")
	g_dxGUI.bigInfoContentRemovedObjects:text(tostring(g_MapInfo.numRemovedObjects) or "0")
	g_dxGUI.bigInfoContentPickups:text(tostring(g_MapInfo.numPickups) or "0")
	g_dxGUI.bigInfoContentRegularPickups:text(tostring(g_MapInfo.numRegularPickups or "0"))
	if (g_MapInfo.numSpawnpoints and g_MapInfo.numSpawnpoints > 0) then
		g_dxGUI.bigInfoContentSpawns:color(255,255,255,255)
	else
		g_dxGUI.bigInfoContentSpawns:color(127,127,127,255)
	end
	if (g_MapInfo.numCheckpoints and g_MapInfo.numCheckpoints > 0) then
		g_dxGUI.bigInfoContentChecks:color(255,255,255,255)
	else
		g_dxGUI.bigInfoContentChecks:color(127,127,127,255)
	end
	if (g_MapInfo.numObjects and g_MapInfo.numObjects > 0) then
		g_dxGUI.bigInfoContentObjects:color(255,255,255,255)
	else
		g_dxGUI.bigInfoContentObjects:color(127,127,127,255)
	end
	if (g_MapInfo.numRemovedObjects and g_MapInfo.numRemovedObjects > 0) then
		g_dxGUI.bigInfoContentRemovedObjects:color(255,255,255,255)
	else
		g_dxGUI.bigInfoContentRemovedObjects:color(127,127,127,255)
	end
	if (g_MapInfo.numPickups and g_MapInfo.numPickups > 0) then
		g_dxGUI.bigInfoContentPickups:color(255,255,255,255)
	else
		g_dxGUI.bigInfoContentPickups:color(127,127,127,255)
	end
	if (g_MapInfo.numRegularPickups and g_MapInfo.numRegularPickups > 0) then
		g_dxGUI.bigInfoContentRegularPickups:color(255,255,255,255)
	else
		g_dxGUI.bigInfoContentRegularPickups:color(127,127,127,255)
	end

	g_dxGUI.bigInfoContentDescription:text(g_MapInfo.description or "<none>")

	if (g_MapInfo.racetype == "R") then
		g_dxGUI.bigInfoContentType:text("Race (R)")
	elseif (g_MapInfo.racetype == "SR") then
		g_dxGUI.bigInfoContentType:text("Speedrun (SR)")
	elseif (g_MapInfo.racetype == "DD") then
		g_dxGUI.bigInfoContentType:text("Destruction Derby (DD)")
	elseif (g_MapInfo.racetype == "TW") then
		g_dxGUI.bigInfoContentType:text("Teamwork (TW)")
	elseif (g_MapInfo.racetype == "MG") then
		g_dxGUI.bigInfoContentType:text("Minigame (MG)")
	elseif (g_MapInfo.racetype == "F") then
		g_dxGUI.bigInfoContentType:text("Footrace (F)")
	else
		g_dxGUI.bigInfoContentType:text("Unknown (" .. (g_MapInfo.racetype or "???") .. ")")
	end

	if (g_MapInfo.ghostmode) then
		g_dxGUI.cornerLabelConfG:color(255,255,255,255)
		g_dxGUI.bigInfoContentGM:text("Enabled")
		g_dxGUI.bigInfoContentGM:color(255,255,255,255)
	else
		g_dxGUI.cornerLabelConfG:color(127,127,127,255)
		g_dxGUI.bigInfoContentGM:text("Disabled")
		g_dxGUI.bigInfoContentGM:color(127,127,127,255)
	end
	if (g_MapInfo.respawn == "timelimit") then
		g_dxGUI.cornerLabelConfR:color(255,255,255,255)
		g_dxGUI.bigInfoContentRS:text(g_MapInfo.respawntime / 1000 .. " second" .. (g_MapInfo.respawntime == 1000 and "" or "s"))
		g_dxGUI.bigInfoContentRS:color(255,255,255,255)
	else
		g_dxGUI.cornerLabelConfR:color(127,127,127,255)
		g_dxGUI.bigInfoContentRS:text("None")
		g_dxGUI.bigInfoContentRS:color(127,127,127,255)
	end
	if (g_MapInfo.vehicleweapons) then
		g_dxGUI.cornerLabelConfW:color(255,255,255,255)
		g_dxGUI.bigInfoContentVW:text(g_MapInfo.hunterminigun and "Enabled" or "No Hunter Minigun")
		g_dxGUI.bigInfoContentVW:color(255,255,255,255)
	else
		g_dxGUI.cornerLabelConfW:color(127,127,127,255)
		g_dxGUI.bigInfoContentVW:text("Disabled")
		g_dxGUI.bigInfoContentVW:color(127,127,127,255)
	end

	local otherThings = {}
	if (getResourceFromName("extraairresistance")) then
		table.insert(otherThings, "No Air Resistance")
	end
	if (getResourceFromName("randomfoliage")) then
		table.insert(otherThings, "No Random Foliage")
	end
	if (getResourceFromName("poleremover")) then
		table.insert(otherThings, "No Light Poles")
	end
	if (getResourceFromName("bomb")) then
		table.insert(otherThings, "Bomb")
	end
	if (getResourceFromName("collidablevehicles")) then
		table.insert(otherThings, "Collidable Vehicles")
	end
	local otherThingsString = table.concat(otherThings, ", ")
	if (#otherThings > 0) then
		g_dxGUI.bigInfoLabelOther:text("Other:")
		g_dxGUI.bigInfoContentOther:text(otherThingsString)
		g_dxGUI.bigInfoContentOther:color(255,255,255,255)
	else
		g_dxGUI.bigInfoLabelOther:text("")
		g_dxGUI.bigInfoContentOther:text("")
	end
end

addEvent("onMapChangedC", true)
addEventHandler("onMapChangedC", root,
	function(mapInfo)
		g_MapInfo = mapInfo

		updateBottomLeftInformation()
		showTravelingScreen()
	end
)

-- ---------------------------------------------------------
-- Visuals (Colors, etc. Requires settings to be read first)
-- ---------------------------------------------------------

function updateGUIDisplay()
	local r,g,b,a = getColorFromString(g_Options.colorbottomleft)

	-- Bottom Left Corner
	if g_Options.mapfolder == "fullpath" then
		-- Hide folder name elements dynamically
		hideGUIComponents("cornerLabelFolderName", "cornerContentFolderName", "bigInfoLabelFolderName", "bigInfoContentFolderName")

		g_dxGUI.cornerLabelFolderPath:color(r,g,b,a)
		g_dxGUI.cornerLabelFolderPath:type("stroke", 1.5)
		g_dxGUI.cornerContentFolderPath:color(255, 255, 255, 255)
		g_dxGUI.cornerContentFolderPath:type("stroke", 1.5)
	else
		-- Hide folder path elements dynamically
		hideGUIComponents("cornerLabelFolderPath", "cornerContentFolderPath", "bigInfoLabelFolderPath", "bigInfoContentFolderPath")

		g_dxGUI.cornerLabelFolderName:color(r,g,b,a)
		g_dxGUI.cornerLabelFolderName:type("stroke", 1.5)
		g_dxGUI.cornerContentFolderName:color(255, 255, 255, 255)
		g_dxGUI.cornerContentFolderName:type("stroke", 1.5)
	end

	g_dxGUI.cornerLabelMap:color(r,g,b,a)
	g_dxGUI.cornerLabelMap:type("stroke", 1.5)
	g_dxGUI.cornerContentMap:color(255, 255, 255, 255)
	g_dxGUI.cornerContentMap:type("stroke", 1.5)

	g_dxGUI.cornerLabelAuthor:color(r,g,b,a)
	g_dxGUI.cornerLabelAuthor:type("stroke", 1.5)
	g_dxGUI.cornerContentAuthor:color(255, 255, 255, 255)
	g_dxGUI.cornerContentAuthor:type("stroke", 1.5)

	g_dxGUI.cornerLabelFPS:color(r,g,b,a)
	g_dxGUI.cornerLabelFPS:type("stroke", 1.5)
	g_dxGUI.cornerContentFPS:color(255, 255, 255, 255)
	g_dxGUI.cornerContentFPS:type("stroke", 1.5)

	g_dxGUI.cornerLabelPing:color(r,g,b,a)
	g_dxGUI.cornerLabelPing:type("stroke", 1.5)
	g_dxGUI.cornerContentPing:color(255, 255, 255, 255)
	g_dxGUI.cornerContentPing:type("stroke", 1.5)

	g_dxGUI.cornerLabelConf:color(r,g,b,a)
	g_dxGUI.cornerLabelConfG:color(127, 127, 127, 255)
	g_dxGUI.cornerLabelConfR:color(127, 127, 127, 255)
	g_dxGUI.cornerLabelConfW:color(127, 127, 127, 255)
	g_dxGUI.cornerLabelConf:type("stroke", 1.5)
	g_dxGUI.cornerLabelConfG:type("stroke", 1.5)
	g_dxGUI.cornerLabelConfR:type("stroke", 1.5)
	g_dxGUI.cornerLabelConfW:type("stroke", 1.5)

	-- Big Info (Tab)
	g_dxGUI.bigInfoLabelMap:color(r,g,b,a)
	g_dxGUI.bigInfoLabelMap:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelAuthor:color(r,g,b,a)
	g_dxGUI.bigInfoLabelAuthor:type("stroke", 1.7)
	if g_Options.mapfolder == "fullpath" then
		g_dxGUI.bigInfoLabelFolderPath:color(r,g,b,a)
		g_dxGUI.bigInfoLabelFolderPath:type("stroke", 1.7)
	else
		g_dxGUI.bigInfoLabelFolderName:color(r,g,b,a)
		g_dxGUI.bigInfoLabelFolderName:type("stroke", 1.7)
	end
	g_dxGUI.bigInfoLabelType:color(r,g,b,a)
	g_dxGUI.bigInfoLabelType:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelGM:color(r,g,b,a)
	g_dxGUI.bigInfoLabelGM:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelRS:color(r,g,b,a)
	g_dxGUI.bigInfoLabelRS:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelVW:color(r,g,b,a)
	g_dxGUI.bigInfoLabelVW:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelOther:color(r,g,b,a)
	g_dxGUI.bigInfoLabelOther:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelPing:color(r,g,b,a)
	g_dxGUI.bigInfoLabelPing:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelFPS:color(r,g,b,a)
	g_dxGUI.bigInfoLabelFPS:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelDescription:color(r,g,b,a)
	g_dxGUI.bigInfoLabelDescription:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelSpawns:color(r,g,b,a)
	g_dxGUI.bigInfoLabelSpawns:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelChecks:color(r,g,b,a)
	g_dxGUI.bigInfoLabelChecks:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelObjects:color(r,g,b,a)
	g_dxGUI.bigInfoLabelObjects:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelRemovedObjects:color(r,g,b,a)
	g_dxGUI.bigInfoLabelRemovedObjects:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelPickups:color(r,g,b,a)
	g_dxGUI.bigInfoLabelPickups:type("stroke", 1.7)
	g_dxGUI.bigInfoLabelRegularPickups:color(r,g,b,a)
	g_dxGUI.bigInfoLabelRegularPickups:type("stroke", 1.7)

	g_dxGUI.bigInfoContentMap:type("stroke", 1.7)
	g_dxGUI.bigInfoContentAuthor:type("stroke", 1.7)
	if g_Options.mapfolder == "fullpath" then
		g_dxGUI.bigInfoContentFolderPath:type("stroke", 1.7)
	else
		g_dxGUI.bigInfoContentFolderName:type("stroke", 1.7)
	end
	g_dxGUI.bigInfoContentType:type("stroke", 1.7)
	g_dxGUI.bigInfoContentGM:type("stroke", 1.7)
	g_dxGUI.bigInfoContentRS:type("stroke", 1.7)
	g_dxGUI.bigInfoContentVW:type("stroke", 1.7)
	g_dxGUI.bigInfoContentOther:type("stroke", 1.7)
	g_dxGUI.bigInfoContentFPS:type("stroke", 1.7)
	g_dxGUI.bigInfoContentPing:type("stroke", 1.7)
	g_dxGUI.bigInfoContentDescription:type("stroke", 1.7)
	g_dxGUI.bigInfoContentSpawns:type("stroke", 1.7)
	g_dxGUI.bigInfoContentChecks:type("stroke", 1.7)
	g_dxGUI.bigInfoContentObjects:type("stroke", 1.7)
	g_dxGUI.bigInfoContentRemovedObjects:type("stroke", 1.7)
	g_dxGUI.bigInfoContentPickups:type("stroke", 1.7)
	g_dxGUI.bigInfoContentRegularPickups:type("stroke", 1.7)

	-- Traveling Screen
	g_dxGUI.travelTextHeader:type("stroke", 1.7)
	g_dxGUI.travelTextName:type("stroke", 1.5)
	g_dxGUI.travelTextAuthor:type("stroke", 1.5)
	g_dxGUI.travelTextConfigs:type("stroke", 1.5)
	g_dxGUI.travelTextFacts:type("stroke", 1.5)
	g_dxGUI.travelTextDescription:type("stroke", 1.5)
end

addEvent("onResourceSettingsReady")
addEventHandler("onResourceSettingsReady", resourceRoot,
	function()
		updateGUIDisplay()

		-- Update text immediately if map info is already loaded
		if g_MapInfo then
			updateBottomLeftInformation()
		end

		showGUIComponents("cornerLabelFolderName", "cornerContentFolderName", "cornerLabelFolderPath", "cornerContentFolderPath", "cornerLabelMap", "cornerContentMap", "cornerLabelAuthor", "cornerContentAuthor", "cornerLabelFPS", "cornerContentFPS", "cornerLabelPing", "cornerContentPing", "cornerLabelConf", "cornerLabelConfG", "cornerLabelConfR", "cornerLabelConfW")
	end
)

function showGUIComponents(...)
	for i, name in ipairs({...}) do
		local isInactivePath = (name == "cornerLabelFolderPath" or name == "cornerContentFolderPath" or name == "bigInfoLabelFolderPath" or name == "bigInfoContentFolderPath") and g_Options.mapfolder ~= "fullpath"
		local isInactiveFile = (name == "cornerLabelFolderName" or name == "cornerContentFolderName" or name == "bigInfoLabelFolderName" or name == "bigInfoContentFolderName") and g_Options.mapfolder == "fullpath"

		if not isInactivePath and not isInactiveFile then
			if g_dxGUI[name] then
				g_dxGUI[name]:visible(true)
			elseif type(g_GUI[name]) == "table" then
				g_GUI[name]:show()
			elseif g_GUI[name] then
				guiSetVisible(g_GUI[name], true)
			end
		end
	end
end

function hideGUIComponents(...)
	for i,name in ipairs({...}) do
		if g_dxGUI[name] then
			g_dxGUI[name]:visible(false)
		elseif type(g_GUI[name]) == "table" then
			g_GUI[name]:hide()
		elseif g_GUI[name] then
			guiSetVisible(g_GUI[name], false)
		end
	end
end

-- ------------
-- FPS and Ping
-- ------------
addEventHandler("onClientPreRender", root,
	function (msSinceLastFrame)
		if (DEBUG_WIDTH and DEBUG_HEIGHT) then
			local DEBUG_COLOR = 0x80FF00FF -- 0xAARRGGBB format
			dxDrawRectangle(0, 0, DEBUG_WIDTH, DEBUG_HEIGHT, DEBUG_COLOR, false, false)
		end
		fpsString = (1 / msSinceLastFrame) * 1000
	end
)

function updateFPSAndPing()
	local ping = tostring(getPlayerPing(localPlayer))
	local fpsLimit = getFPSLimit()

	-- Use "formattedFPS" to prevent shadowing the outer "fpsString"
	local formattedFPS = tostring(math.floor((fpsString or 0) * 10) / 10)

	if fpsLimit == 0 then
		fpsStringBigInfo = formattedFPS .. " / 0 (Unlimited)"
	else
		fpsStringBigInfo = formattedFPS .. " / " .. fpsLimit
	end

	g_dxGUI.bigInfoContentFPS:text(fpsStringBigInfo)
	g_dxGUI.cornerContentFPS:text(formattedFPS)
	g_dxGUI.bigInfoContentPing:text(ping)
	g_dxGUI.cornerContentPing:text(ping)
end
setTimer(updateFPSAndPing, 1000, 0)
