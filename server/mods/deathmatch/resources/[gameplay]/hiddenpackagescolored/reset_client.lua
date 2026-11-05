function resetCommandHandler(commandName, ...)
	if (g_nonParticipant) then
		outputChatBox("You must enable hidden packages before you can do that.", 49, 206, 13)
		return
	end
	if (not g_loggedIn) then
		outputChatBox("You must be logged in before you can do that.", 49, 206, 13)
	end

	local args = {...}
	local packIds = {}
	for _,arg in ipairs(args) do
		if (arg == "all") then
			resetAllPackages()
			return
		else
			local resetType = arg:upper()
			if (#arg == 1 and (resetType == "C" or resetType == "K" or resetType:match("^[WGBORY]$"))) then
				for _, pack in pairs(Packages.instances) do
					local matchesType = resetType == "C" and pack.packType ~= PACKAGE_BLACK_TYPE
					if (resetType == "K") then
						matchesType = pack.packType == PACKAGE_BLACK_TYPE
					elseif (resetType ~= "C") then
						local typeLetter = PACKAGE_TYPES[pack.packType].forwardName:sub(1, 1):upper()
						matchesType = typeLetter == resetType
					end
					if (matchesType and pack.collected) then
						table.insert(packIds, {pack.packType, pack.packageNumber})
					end
				end
			else
				local id = convertResetFormatToCompositePackageKey(arg)
				local pack = Packages.instances[id]
				if (pack) then
					if (pack.collected) then
						table.insert(packIds, {pack.packType, pack.packageNumber})
					end
				else
					local region = Regions:getFromName(arg)
					if (region) then
						local regionPacks = region:getAllPackages(true)
						for _, rp in ipairs(regionPacks) do
							table.insert(packIds, {rp.packType, rp.packageNumber})
						end
					end
				end
			end
		end
	end
	outputChatBox("Resetting "..#packIds.." packages.", 206, 49, 13)
	triggerServerEvent("onClientResetRequest", localPlayer, packIds)
end
addCommandHandler("resetpackages", resetCommandHandler, false, false)

function resetAllPackages()
	local packages = Packages:getAllTypeNumberPairs(true)
	outputChatBox("Resetting "..#packages.." packages.", 206, 49, 13)
	triggerServerEvent("onClientResetRequest", localPlayer, packages)
end
