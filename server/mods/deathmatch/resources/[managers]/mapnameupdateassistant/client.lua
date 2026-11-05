local TIMER = nil

addEventHandler("onClientResourceStart", resourceRoot,
	function ()
		TIMER = setTimer(startTimer, 1000, 0)
	end
)

function startTimer()
	local res = getResourceFromName("race_ghost")
	if (res and getResourceState(res) == "running") then
		killTimer(TIMER)
		clientUpdate()
	end
end

function clientUpdate()
	local file
	local playername = getPlayerName(localPlayer):gsub('[%p%c%s]', '')
	if (not fileExists("updatesdone_"..playername..".txt")) then
		file = fileCreate("updatesdone_"..playername..".txt")
	else
		file = fileOpen("updatesdone_"..playername..".txt")
	end
	local data = fileRead(file, fileGetSize(file))
	local updatesdone = tonumber(data)
	if (not updatesdone) then updatesdone = 0 end

	if (updatesdone == #RENAME_MAPS) then
		-- We are up to date
		fileClose(file)
		return
	elseif (updatesdone > #RENAME_MAPS) then
		-- Something went wrong and we need to start from scratch
		updatesdone = 0
	end

	outputChatBox("Updating Race Ghosts... F8 for more info:", 255, 220, 0)
	for i=updatesdone,#RENAME_MAPS,1 do
		local maplist = RENAME_MAPS[i]
		if (maplist) then
			for _,m in pairs(maplist) do
				local oldFile = m[1]
				local newFile = m[2]
				local oldName = m[3]
				local newName = m[4]
				if (oldFile and newFile) then
					local oldGhost = "@ghosts/" .. oldFile .. "_" .. playername .. "_PB.ghost"
					local newGhost = "@ghosts/" .. newFile .. "_" .. playername .. "_PB.ghost"
					triggerEvent("OnRequestClientRenameLocalGhost", root, oldGhost, newGhost)
				end
			end
		end
	end
	updatesdone = #RENAME_MAPS
	fileClose(file)
	file = fileCreate("updatesdone_"..playername..".txt")
	fileWrite(file, tostring(updatesdone))
	fileClose(file)
end
