nametag = {}
local nametags = {}
local g_screenX,g_screenY = guiGetScreenSize()
local bHideNametags = false

-- Nametag settings
local NAMETAG_SCALE = 0.3 -- Overall adjustment of the nametag, use this to resize but constrain proportions
local NAMETAG_ALPHA_DISTANCE = 50 -- Distance to start fading out
local NAMETAG_DISTANCE = 120 -- Distance until we're gone

local NAMETAG_ALPHA = 255 -- Full opacity for text
local NAMETAG_BAR_ALPHA = 120 -- Original semi-transparent alpha for healthbar

-- The following arent actual pixel measurements, they're just proportional constraints
local NAMETAG_TEXT_BAR_SPACE = 2
local NAMETAG_WIDTH = 50
local NAMETAG_HEIGHT = 5
local NAMETAG_TEXTSIZE = 0.7
local NAMETAG_OUTLINE_THICKNESS = 1.2

local NAMETAG_ALPHA_DIFF = NAMETAG_DISTANCE - NAMETAG_ALPHA_DISTANCE
NAMETAG_SCALE = 1/NAMETAG_SCALE * 800 / g_screenY

-- Ensure the nametag doesn't get too big
local maxScaleCurve = { {0, 0}, {3, 3}, {13, 5} }
-- Ensure the text doesn't get too small/unreadable
local textScaleCurve = { {0, 0.8}, {0.8, 1.2}, {99, 99} }
-- Make the text a bit brighter and fade more gradually
local textAlphaCurve = { {0, 0}, {25, 110}, {120, 200}, {255, 255} }

-- Variable to track if the outline is enabled (defaults to true)
local bShowOutline = true
-- The local, private file path where we will save the setting
local settingsFilePath = "@nametag_settings.xml"

function nametag.create(player)
	nametags[player] = true
end

function nametag.destroy(player)
	nametags[player] = nil
end

-- NEW: Function to load the saved setting from the XML file
local function loadOutlineSetting()
	local xml = xmlLoadFile(settingsFilePath)
	if xml then
		local savedSetting = xmlNodeGetAttribute(xml, "outlineEnabled")
		if savedSetting == "false" then
			bShowOutline = false
		else
			bShowOutline = true
		end
		xmlUnloadFile(xml)
	else
		-- File doesn't exist yet (first time playing), create it with default 'true'
		xml = xmlCreateFile(settingsFilePath, "settings")
		if xml then
			xmlNodeSetAttribute(xml, "outlineEnabled", "true")
			xmlSaveFile(xml)
			xmlUnloadFile(xml)
		end
	end
end

-- NEW: Function to update and save the setting to the XML file
local function saveOutlineSetting()
	local xml = xmlLoadFile(settingsFilePath)
	if not xml then
		xml = xmlCreateFile(settingsFilePath, "settings")
	end
	if xml then
		xmlNodeSetAttribute(xml, "outlineEnabled", tostring(bShowOutline))
		xmlSaveFile(xml)
		xmlUnloadFile(xml)
	end
end

addEventHandler("onClientRender", root,
	function()
		for i,player in ipairs(getElementsByType("player")) do
			if player ~= localPlayer then
				setPlayerNametagShowing(player, false)
				if not nametags[player] then
					nametag.create(player)
				end
			end
		end
		if bHideNametags then
			return
		end
		local x,y,z = getCameraMatrix()
		for player in pairs(nametags) do
			while true do
				if not isElement(player) then
					nametags[player] = nil
					break
				end
				if isPedDead(player) then
					break
				end
				if getElementDimension(player) ~= getElementDimension(localPlayer) then
					break
				end

				local vehicle = getPedOccupiedVehicle(player)
				local px,py,pz = getElementPosition(vehicle or player)
				local pdistance = getDistanceBetweenPoints3D(x,y,z,px,py,pz)

				if pdistance <= NAMETAG_DISTANCE then
					local sx,sy = getScreenFromWorldPosition(px, py, pz+0.95, 0.06)
					if not sx or not sy then
						break
					end

					local scale = 1/(NAMETAG_SCALE * (pdistance / NAMETAG_DISTANCE))
					local alphaCalc = ((pdistance - NAMETAG_ALPHA_DISTANCE) / NAMETAG_ALPHA_DIFF)

					-- Calculate separate alphas
					local textAlphaBase = (alphaCalc < 0) and NAMETAG_ALPHA or NAMETAG_ALPHA-(alphaCalc*NAMETAG_ALPHA)
					local barAlphaBase = (alphaCalc < 0) and NAMETAG_BAR_ALPHA or NAMETAG_BAR_ALPHA-(alphaCalc*NAMETAG_BAR_ALPHA)

					scale = math.evalCurve(maxScaleCurve,scale)
					local textscale = math.evalCurve(textScaleCurve,scale)
					local textalpha = math.evalCurve(textAlphaCurve, textAlphaBase)
					local outlineThickness = NAMETAG_OUTLINE_THICKNESS*(scale)

					local r,g,b = 255,255,255
					local team = getPlayerTeam(player)

					local display_name = _getPlayerName(player)
					if team then
						r,g,b = getTeamColor(team)
						display_name = getPlayerName(player)
					end

					-- Create a stripped version purely for the black outline
					local clean_name = string.gsub(display_name, "#%x%x%x%x%x%x", "")

					local offset = (scale) * NAMETAG_TEXT_BAR_SPACE/2

					-- --- TEXT OUTLINE (Opaque Black) ---
					if bShowOutline then
						local outDist = 1.5
						dxDrawText(clean_name, sx - outDist, sy - offset - outDist, sx - outDist, sy - offset - outDist, tocolor(0, 0, 0, textalpha), textscale*NAMETAG_TEXTSIZE, "default", "center", "bottom", false, false, false, false)
						dxDrawText(clean_name, sx + outDist, sy - offset - outDist, sx + outDist, sy - offset - outDist, tocolor(0, 0, 0, textalpha), textscale*NAMETAG_TEXTSIZE, "default", "center", "bottom", false, false, false, false)
						dxDrawText(clean_name, sx - outDist, sy - offset + outDist, sx - outDist, sy - offset + outDist, tocolor(0, 0, 0, textalpha), textscale*NAMETAG_TEXTSIZE, "default", "center", "bottom", false, false, false, false)
						dxDrawText(clean_name, sx + outDist, sy - offset + outDist, sx + outDist, sy - offset + outDist, tocolor(0, 0, 0, textalpha), textscale*NAMETAG_TEXTSIZE, "default", "center", "bottom", false, false, false, false)
					end

					-- --- MAIN TEXT (Colored) ---
					dxDrawText(display_name, sx, sy - offset, sx, sy - offset, tocolor(r,g,b,textalpha), textscale*NAMETAG_TEXTSIZE, "default", "center", "bottom", false, false, false, true)

					-- --- HEALTHBAR (Semi-Transparent) ---
					local drawX = sx - NAMETAG_WIDTH*scale/2
					local drawY = sy + offset
					local width,height =  NAMETAG_WIDTH*scale, NAMETAG_HEIGHT*scale

					dxDrawRectangle(drawX, drawY, width, height, tocolor(0,0,0,barAlphaBase))

					local health = 0
					if (vehicle) then
						health = getElementHealth(vehicle)
						health = math.max(health - 250, 0)/750
					else
						health = getElementHealth(player)
						local maxHealthStat = getPedStat(player, 24)
						local maxHP = 100 + (maxHealthStat - 569) / 4.31
						health = math.max(health, 0)/maxHP
					end

					local p = -510*(health^2)
					local hr, hg = math.max(math.min(p + 255*health + 255, 255), 0), math.max(math.min(p + 765*health, 255), 0)

					dxDrawRectangle(drawX + outlineThickness, drawY + outlineThickness, width - outlineThickness*2, height - outlineThickness*2, tocolor(hr,hg,0,0.4*barAlphaBase))
					dxDrawRectangle(drawX + outlineThickness, drawY + outlineThickness, health*(width - outlineThickness*2), height - outlineThickness*2, tocolor(hr,hg,0,barAlphaBase))
				end
				break
			end
		end
	end
)

---------------THE FOLLOWING IS THE MANAGEMENT OF NAMETAGS-----------------

addCommandHandler("togglenametagoutline",
	function()
		bShowOutline = not bShowOutline
		saveOutlineSetting() -- Save to the XML file instantly when toggled

		if bShowOutline then
			outputChatBox("Nametag outline enabled.", 0, 255, 0)
		else
			outputChatBox("Nametag outline disabled.", 255, 255, 0)
		end
	end, false
)

addEventHandler("onClientResourceStart", resourceRoot,
	function()
		loadOutlineSetting() -- Load the XML file as soon as the script starts

		for i, player in ipairs(getElementsByType("player")) do
			if player ~= localPlayer then
				nametag.create(player)
			end
		end
	end
)

addEventHandler("onClientPlayerJoin", root,
	function()
		if source == localPlayer then
			return
		end
		setPlayerNametagShowing(source, false)
		nametag.create(source)
	end
)

addEventHandler("onClientPlayerQuit", root,
	function()
		nametag.destroy(source)
	end
)


addEvent("onClientScreenFadedOut", true)
addEventHandler("onClientScreenFadedOut", root,
	function()
		bHideNametags = true
	end
)

addEvent("onClientScreenFadedIn", true)
addEventHandler("onClientScreenFadedIn", root,
	function()
		bHideNametags = false
	end
)
