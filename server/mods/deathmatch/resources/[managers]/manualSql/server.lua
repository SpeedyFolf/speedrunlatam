function isPlayerAdmin(player)
	return isObjectInACLGroup("user." .. getAccountName(getPlayerAccount(player)), aclGetGroup("Admin"))
end

addCommandHandler("alterMapTable", function(player, cmd)
	if not isPlayerAdmin(player) then
		iprint("No")
		return
	end
	iprint("Y")

	executeSQLQuery("ALTER TABLE maptimes ADD COLUMN playerAccount TEXT")
	iprint("Y")

end)

addCommandHandler("deleteSpeedyfolfBFTime", function(player)
	if not isPlayerAdmin(player) then
		iprint("No")
		return
	end
	iprint("Y")

	local db = dbConnect("sqlite", ":/mapSuperFleischbergAutosCollisionsRecords.db")
	local q = dbExec(db, "DELETE FROM Table581 WHERE playername = 'SpeedyFolf' AND score = 25254")
	iprint("Y")
end)

addCommandHandler("deleteSunnysideSouvenier", function(player)
	if not isPlayerAdmin(player) then
		iprint("No")
		return
	end

	iprint("Y")
	local db = dbConnect("sqlite", ":/achievements.db")
	local q = dbExec(db, "UPDATE achievements SET data = REPLACE(data, ', \"Souvenier Shop22\"', '') WHERE data LIKE '%, \"Souvenier Shop22\"%' AND id = 'sunnysideEveryDest';")
	local q = dbExec(db, "UPDATE achievements SET data = REPLACE(data, '\"Souvenier Shop22\"', '') WHERE data LIKE '%\"Souvenier Shop22\"%' AND id = 'sunnysideEveryDest';")
	iprint("Y")
end)
