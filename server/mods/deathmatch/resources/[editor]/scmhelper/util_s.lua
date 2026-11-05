function teleportToMarker(x, y, z)
	outputConsole("Teleport to "..x..","..y..","..z)
	spawnPlayer(client, x, y, z)
	setPedWearingJetpack(client, true)
end
addEvent("teleportToMarker", true)
addEventHandler("teleportToMarker", root, teleportToMarker)
