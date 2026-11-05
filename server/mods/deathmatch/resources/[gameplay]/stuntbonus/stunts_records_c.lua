local displayStuntsStats = false
local statsStantsInited = false
local statsStuntsAlpha = 0
local stuntsData
local stuntsNames = {
	"Maximum Insane Jump Distance",
	"Maximum Insane Jump Height",
	"Maximum Insane Jump Flips",
	"Maximum Insane Jump Rotation",
	"Longest Stoppie Distance",
	"Longest Stoppie Time",
	"Longest Wheelie Distance",
	"Longest Wheelie Time",
	"Longest 2 Wheels Distance",
	"Longest 2 Wheels Time"
};
local stuntsUnits = { "m", "m", "times", "°", "m", "s", "m", "s", "m", "s" }

-- Screen stuff
screenX, screenY = guiGetScreenSize()
s_offsets = {0.25, 0.25, 0.5, 0.6} -- X-left, Y-top, width, height for a box
st_offsets = {0.27, 0.20} -- X-left, Y1, Y2, textsize

function showStuntsStats()
	-- Request data for stats
	triggerServerEvent("getStuntsStats", localPlayer)

	-- Show stats
	displayStuntsStats = not displayStuntsStats
end

function drawStuntsStats()
	if not statsStuntsInited then return end

	dxDrawText("Stunts Records", screenX*(st_offsets[1]+0.005), screenY*(st_offsets[2]-0.01+0.003), screenX, screenY, tocolor(0, 0, 0, statsStuntsAlpha), (screenY/1080)*4.02, (screenY/1080)*4.15, "beckett")
	dxDrawText("Stunts Records", screenX*st_offsets[1], screenY*(st_offsets[2]-0.01), screenX*st_offsets[1], screenY, tocolor(175, 202, 230, statsStuntsAlpha), (screenY/1080)*4, (screenY/1080)*4, "beckett")

	local box_height = screenY*s_offsets[4] * 0.9
	local textSize = box_height / 75 / 12
	local smallOffset = box_height / 31
	local offset = box_height / 31

	for i = 1, #stuntsNames do
		-- Texts
		dxDrawText(stuntsNames[i], screenX*st_offsets[1], screenY*0.27 + offset, screenX*st_offsets[1], screenY, tocolor(175, 202, 230, statsStuntsAlpha), textSize, textSize, "bankgothic")
		dxDrawText("TOP: " ..stuntsData[i][1]["playername"]:gsub("#%x%x%x%x%x%x", ""), screenX*(st_offsets[1]+0.03), screenY*0.27 + offset + smallOffset, screenX*st_offsets[1], screenY, tocolor(175, 202, 230, statsStuntsAlpha), textSize, textSize, "bankgothic")
		dxDrawText("PB:   " ..stuntsData[#stuntsNames+i][1]["playername"]:gsub("#%x%x%x%x%x%x", ""), screenX*(st_offsets[1]+0.03), screenY*0.27 + offset + smallOffset*2, screenX*st_offsets[1], screenY, tocolor(175, 202, 230, statsStuntsAlpha), textSize, textSize, "bankgothic")

		-- Numbers
		dxDrawText(string.format("%.1f", stuntsData[i][1]["score"]).. " " ..stuntsUnits[i], screenX*(st_offsets[1]+0.03), screenY*0.27 + offset + smallOffset, screenX*(st_offsets[1]+0.45), screenY, tocolor(175, 202, 230, statsStuntsAlpha), textSize, textSize, "bankgothic", "right")
		dxDrawText(string.format("%.1f", stuntsData[#stuntsNames+i][1]["score"]).. " " ..stuntsUnits[i], screenX*(st_offsets[1]+0.03), screenY*0.27 + offset + smallOffset*2, screenX*(st_offsets[1]+0.45), screenY, tocolor(175, 202, 230, statsStuntsAlpha), textSize, textSize, "bankgothic", "right")

		offset = offset + smallOffset * 3
	end
end

addEventHandler("onClientRender", root, function()
	if displayStuntsStats then
		-- Fade In
		if statsStuntsAlpha < 255 then statsStuntsAlpha = statsStuntsAlpha + 51
		else statsStuntsAlpha = 255 end
	else
		-- Fade out
		if statsStuntsAlpha > 0 then statsStuntsAlpha = statsStuntsAlpha - 51
		else statsStuntsAlpha = 0 end
	end

	-- Draw Stats
	if statsStuntsAlpha > 200 then
		dxDrawRectangle(screenX*s_offsets[1], screenY*s_offsets[2], screenX*s_offsets[3], screenY*s_offsets[4], tocolor(0, 0, 0, 200, 50))
	else
		dxDrawRectangle(screenX*s_offsets[1], screenY*s_offsets[2], screenX*s_offsets[3], screenY*s_offsets[4], tocolor(0, 0, 0, statsStuntsAlpha, 50))
	end

	drawStuntsStats()
end )

addEvent("receiveStuntsStats", true)
addEventHandler("receiveStuntsStats", root, function(data)
	stuntsData = data

	-- Check for empty data
	for i = 1, #stuntsNames do
		if stuntsData[i][1] == nil then
			stuntsData[i][1] =
			{
				["playername"] = "-- EMPTY --",
				["score"] = "0.0"
			}
		end

		if stuntsData[#stuntsNames+i][1] == nil then
			stuntsData[#stuntsNames+i][1] =
			{
				["playername"] = "-- EMPTY --",
				["score"] = "0.0"
			}
		end
	end

	statsStuntsInited = true
end )

addCommandHandler("stunts", showStuntsStats)

addEventHandler("onClientKey", root, function(button, press)
	if isChatBoxInputActive() then return end
	if displayStuntsStats and press and button == "escape" then
		displayStuntsStats = false
	end
end )
