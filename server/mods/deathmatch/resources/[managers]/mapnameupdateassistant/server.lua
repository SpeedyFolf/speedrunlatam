local gameTypes = {"Sprint", "Destruction derby", "Freeroam"}
local TIMER_S

addEventHandler("onResourceStart", resourceRoot,
	function ()
		TIMER_S = setTimer(startTimer, 1000, 0)
	end
)

function startTimer()
	if (getResourceState(getResourceFromName("race_ghost")) == "running") then
		killTimer(TIMER_S)
		serverUpdate()
	end
end

function serverUpdate()
	-- We store how many updates are done in a setting. If this setting is incremented, it means the update already happened and we do not need to do it again.
	local updatesdone = tonumber(get("*updatesdone"))
	if (updatesdone >= #RENAME_MAPS) then return end

	for i=updatesdone+1,#RENAME_MAPS,1 do
		-- Get the map list for update i
		local maplist = RENAME_MAPS[i]
		if (maplist) then
			for _,m in pairs(maplist) do
				local oldFile = m[1]
				local newFile = m[2]
				local oldName = m[3]
				local newName = m[4]
				outputServerLog("[MNUA] Evaluating "
					..(oldFile or "<nil>").."; "
					..(newFile or "<nil>").."; "
					..(oldName or "<nil>").."; "
					..(newName or "<nil>"))
				if (oldFile and newFile) then
					-- Rename ghosts
					triggerEvent("OnRequestRenameGhosts", root, oldFile, newFile)
					-- Update mapratings
					local count = #executeSQLQuery("SELECT * FROM mapratings WHERE mapname=?", oldFile)
					if (count > 0) then
						outputServerLog("[MNUA] SQL updating "..count.." mapratings from "..oldFile.." to "..newFile)
						executeSQLQuery("UPDATE mapratings SET mapname=? where mapname=?", newFile, oldFile)
					end
					-- Update race_mapmanager_maps
					count = #executeSQLQuery("SELECT * FROM race_mapmanager_maps WHERE resName=?", oldFile)
					if count > 0 then
						outputServerLog("[MNUA] SQL deleting old "..newFile.." from race_mapmanager_maps")
						executeSQLQuery("UPDATE race_mapmanager_maps SET resName=? WHERE resName=?", newFile.."_OLD", newFile)
					end
					count = #executeSQLQuery("SELECT * FROM race_mapmanager_maps WHERE resName=?", oldFile)
					if count > 0 then
						outputServerLog("[MNUA] SQL Updating "..count.." "..oldFile.." from race_mapmanager_maps to "..newFile)
						executeSQLQuery("UPDATE race_mapmanager_maps SET resName=? WHERE resName=?", newFile, oldFile)
					end
					count = #executeSQLQuery("SELECT * FROM race_mapmanager_maps WHERE infoName=?", oldName)
					if count > 0 then
						outputServerLog("[MNUA] SQL Updating "..count.." "..oldName.." from race_mapmanager_maps to "..newName)
						executeSQLQuery("UPDATE race_mapmanager_maps SET infoName=? WHERE infoName=?", newName, oldName)
					end
				end
				if (oldName and newName) then
					-- Update all the table names from toptimes. Boards exists for either DD, Freeroam, or Race. Check all 3.
					for _, t in pairs(gameTypes) do
						-- local tableNameOld = "race maptimes "..t.." "..oldName
						-- tableNameOld = string.gsub(tableNameOld, "(['])", "''")
						-- local tableNameNew = "race maptimes "..t.." "..newName
						-- tableNameNew = string.gsub(tableNameNew, "(['])", "''")
						-- Check if the table exists
						-- if (executeSQLQuery("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='"..tableNameOld.."'")[1]["count(*)"] > 0) then
						-- 	-- Check if the new table already exists (likely leftovers from 2013)
						-- 	if (executeSQLQuery("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='"..tableNameNew.."'")[1]["count(*)"] > 0) then
						-- 		iprint("[MNUA] SQL renaming leftover table from last decade: '"..tableNameNew.."'' to '"..tableNameNew.."_OLD'.")
						-- 		executeSQLQuery("ALTER TABLE '"..tableNameNew.."' RENAME TO '"..tableNameNew.."_OLD'" )
						-- 	end
						-- 	-- Rename old table to new
						-- 	iprint("[MNUA] SQL renaming table from last decade: '"..tableNameOld.."'' to '"..tableNameNew.."'.")
						-- 	executeSQLQuery("ALTER TABLE '"..tableNameOld.."' RENAME TO '"..tableNameNew.."'" )
						-- end
						outputServerLog("[MNUA] SQL updating maptimes "..oldName.." to "..newName)
						executeSQLQuery("UPDATE maptimes SET mapName=? WHERE mapName=?", newName, oldName)
					end
				end
			end
		end
	end
	updatesdone = #RENAME_MAPS
	set("*updatesdone", updatesdone)
end
