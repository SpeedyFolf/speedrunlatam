g_currentMap = getResourceName(call(getResourceFromName("mapmanager"), "getRunningGamemodeMap"))
local DD_timers = {}
local finishTimes = {} -- Photo Finish
local lastDrivenVehicle = {} -- Auto-Selfie
local hitByOwnVehicle = {} -- Auto-Selfie
local winStreak = {} -- Domination
local finishedThisRace = {}
local trains = {} -- Off the Rails
local finishStreak = {} -- Participation Trophy
local vehicleDamage = {} -- Insurance Fraud
local underdogTime = {} -- Underdog
local underdogLastCheck = {} -- Underdog
local finishers = {} -- Double Trouble

-- Define a table to store author name overrides.
-- Key: The official author name (as in mapInfo.author)
-- Value: A table of alternative in-game names (case-insensitive for convenience)
local g_AuthorNameOverrides = {
	["driver2"] = {"tduva"},
	["driver2 (based on Fivetowers by Soner)"] = {"tduva"},
	["LotsOfS"] = {"S."},
	["marshall"] = {"marshall","[meow]marshall","[cock]marshall"},
	["misterfolg"] = {"misterfolg","[meow]misterfolg"},
	["assfasda"] = {"Suzuki","[meow]suzuki"},
	["Gang & S."] = {"Gang","S."},
	["S. & Gang"] = {"S.","Gang"},
	["Oekeokiki & Gang"] = {"Oekeokiki","Gang"},
	["Gang & Oekeokiki"] = {"Gang","Oekeokiki"},
	["Ali Digitali"] = {"Ali_Digitali"},
	["Mark01 with some edits by Mawfeen"] = {"Mawfeen"},
	["Mark01, edits by Mawfeen"] = {"Mawfeen"},
	["J.R.R. Mawfeen"] = {"Mawfeen"},
	["Mawfeen ft. rrrrrrr"] = {"Mawfeen","rrrrrrr"},
	["Ali_Digitali + Kreedon"] = {"Ali_Digitali","Kreedon"},
	["Ali_Digitali + Mintse"] = {"Ali_Digitali","Mintse"},
	["Map - LateLJ. Scripting - Joshimuz"] = {"LateLJ","Joshimuz"},
	["LateLJ (Edits by Joshimuz)"] = {"LateLJ","Joshimuz"},
	["Boterklontje"] = {"Boterklontje","[SKC]Boterklontje","[Su-57]Boterklontje"},
	["HUNJA (edited by =FoX=Wuzi)"] = {"#CC0000=FoX=Wuzi"},
	["mix by |GMC|Zaya, idea by MaD_EaGLeR, edit by =FoX=Wuzi, script by Discoordination"] = {"#CC0000=FoX=Wuzi","Discoordination"},
	["|GMC|Zaya &amp; |GMC|MaD_EaGLeR, script by Discoordination"] = {"Discoordination"},
	["misterfolg, script by Discoordination"] = {"misterfolg","[meow]misterfolg","Discoordination"},
	["R*, ported by 123robot, edited by Mawfeen"] = {"123robot","Mawfeen"},
	["R*, ported by 123robot, improved by Mawfeen"] = {"123robot","Mawfeen"},
	["R*, ported by 123robot, perfected by Mawfeen"] = {"123robot","Mawfeen"},
	["Mawfeen & SpeedyFolf"] = {"Mawfeen","SpeedyFolf"},
	-- Add more as needed
}

-- Clothes stuff
local clothes = {}
for i = 0, 16 do
	local clothesIndex = 0
	clothes[i] = {}
	while (getClothesByTypeIndex(i, clothesIndex)) do
		local clothesTexture, clothesModel = getClothesByTypeIndex(i, clothesIndex)
		table.insert(clothes[i], {clothesTexture, clothesModel})
		clothesIndex = clothesIndex + 1
	end
end

-- triggerAchievement
-- playerSource, group of achievements, achievement, data
-- exports.achievements:triggerAchievement(player, "general29") -- EXAMPLE
-- exports.achievements:updateObjective(source, "disco10", "data") -- EXAMPLE

-- Achievement triggers for "Speeeeeeeeeeed", "AFK", "Explorer" and "Fashion Victim"
function update()
	for _, players in ipairs(getElementsByType("player")) do
		-- Speed
		if getPedOccupiedVehicle(players) then
			local speedVector = Vector3(getElementVelocity(getPedOccupiedVehicle(players)))
			if speedVector.length >= 2.1875 and speedVector.x > 0.1 and speedVector.y > 0.1 then -- disable ach for players who just falling from the sky
				triggerAchievement(players, "general19")
			end
		end

		-- AFK
		if getPlayerIdleTime(players) and getPlayerIdleTime(players) >= 300000 then
			triggerAchievement(players, "general20")
		end

		-- Explorer
		local x, y, z = getElementPosition(players)
		local zone = getZoneName(x, y, z, false)
		if zone ~= "Unknown" and zone ~= "Whetstone" and zone ~= "Flint County" and zone ~= "Los Santos"
		and zone ~= "San Fierro" and zone ~= "Red County" and zone ~= "Las Venturas" and zone ~= "Bone County" and zone ~= "Tierra Robada" then
			updateObjective(players, "general22", zone)
		end

		-- Clother checks
		if getElementModel(players) == 0 then
			for clothesType = 0, 16 do
				local texture, model = getPedClothes(players, clothesType)
				for i = 1, #clothes[clothesType] do
					if clothes[clothesType][i][1] == texture and clothes[clothesType][i][2] == model then
						updateObjective(players, "cjalloutfits", 1000 * clothesType + i)
						break
					end
				end
			end
		end

		-- Off the Rails
		if trains[players] then
			if isElement(trains[players]) then
				if isTrainDerailed(trains[players]) then
					triggerAchievement(players, "offTheRails")
					trains[players] = nil
				end
			else
				-- Clean up the table if the train was destroyed/deleted
				trains[players] = nil
			end
		end
	end
end

-- Game Critic
addCommandHandler("rate", function(player, command, rated)
	rated = tonumber(rated)
	if rated and rated <= 10 and rated >= 0 then
		updateObjective(player, "general21", g_currentMap)
		updateObjective(player, "bigrating", g_currentMap)
	end
end )

-- Generic map finish achievement triggers
addEvent("onPlayerFinish", true)
addEventHandler("onPlayerFinish", root, function(rank, time)

	-- Participation Trophy / Domination
	finishedThisRace[source] = true
	finishStreak[source] = (finishStreak[source] or 0) + 1
	if finishStreak[source] == 20 then
		triggerAchievement(source, "finisherstreak")
	end

	if rank == 1 and getPlayerCount() >= 4 then
		if not winStreak[source] then
			winStreak[source] = {map = g_currentMap, streak = 1}
		else
			if winStreak[source].map == g_currentMap then
				winStreak[source].streak =
					winStreak[source].streak + 1
			else
				winStreak[source] = {map = g_currentMap, streak = 1}
			end
		end
		if winStreak[source].streak == 3 then
			triggerAchievement(source, "win3inarow")
		end
	else
		winStreak[source] = nil
	end

	-- Repeat Offender
	if g_currentMap ~= "MostWantedLosSantos" and g_currentMap ~= "BackToSchool" and g_currentMap ~= "TheGeoguesser" then
		local found = false
		for i, v in pairs(finishers) do
			if v == getPlayerSerial(source) then
				triggerAchievement(source, "repeatOffender")
				found = true
				break
			end
		end
		if not found then
			table.insert(finishers, getPlayerSerial(source))
		end
	end

	-- Pinpointer
	if g_currentMap == "TheGeoguesser" and (getElementData(source, "Points") or 0) >= 2500 then
		triggerAchievement(source, "geoguesserPerfectScore")
	end

	if time < 0 then
		return -- Bugfixing
	end

	-- Finish, Finisher, Finishest
	triggerAchievement(source, "general1")
	triggerAchievement(source, "general2")
	triggerAchievement(source, "general3")

	-- Deathless 5, Deathless 50, Deathless 500
	if getElementData(source, "timesDied") == 0 then
		updateObjective(source, "deathless5", g_currentMap)
		updateObjective(source, "deathless50", g_currentMap)
		updateObjective(source, "deathless500", g_currentMap)
	end

	-- Jesus Take the Wheel
	if getElementData(source, "ach_keyPresses") == 0 then
		triggerAchievement(source, "general15")
	end

	-- Walking Enthusiast
	if not getPedOccupiedVehicle(source) then
		triggerAchievement(source, "general17")
	end

	-- Racist
	if getPlayerCount() >= 5 and rank == 1 then
		updateObjective(source, "winner100")
	end

	-- Photo Finish
	finishTimes[rank] = {player = source, time = time}
	for _, data in pairs(finishTimes) do
		if data.player ~= source then
			local diff = math.abs(time - data.time)
			if diff <= 10 then
				triggerAchievement(source, "photophinish")
				triggerAchievement(data.player, "photophinish")
			end
		end
	end

	-- $60,000,000 Project
	if isPedWearingJetpack(source) then
		triggerAchievement(source, "finishWithJetpack")
	end

	-- Al Dente
	if g_currentMap == "AllTags" and getElementData(source, "soundTags") and getElementData(source, "soundTags") == 0 then
		triggerAchievement(source, "alltagssilent")
	end

	-- San Fierro Traitor
	if g_currentMap == "AllTags" and getElementData(getResourceRootElement(getResourceFromName("AllTags")), "secretMode") == 10 then
		triggerAchievement(source, "alltagsrifa")
	end

	-- Stop Playing With Yourself
	if getPlayerCount() == 1 then
		triggerAchievement(source, "stopPlayingWithYourself")
	end

	-- Me and the Boys
	if getPlayerCount() >= 64 then
		triggerAchievement(source, "meAndTheBoys")
	end

	-- Timelapse
	local hour, _ = getTime()
	updateObjective(source, "allhours", tostring(hour))

	-- One Pump Chump
	if time < 10000 then
		triggerAchievement(source, "finish10s")
	end

	if rank == 1 then
		-- Underdog
		if time >= 60000 then
			local accumulated = underdogTime[source] or 0
			if underdogLastCheck[source] then
				accumulated = accumulated + (getTickCount() - underdogLastCheck[source])
			end
			if accumulated / time >= 0.25 then
				triggerAchievement(source, "underdogwin")
			end
		end

		-- L + Ratio
		local playerName = getPlayerName(source)
		local isAuthor = false
		if playerName == g_MapAuthor then
			isAuthor = true
		else
			local overrides = g_AuthorNameOverrides[g_MapAuthor]
			if overrides then
				for _, overrideName in ipairs(overrides) do
					if playerName:lower() == overrideName:lower() then
						isAuthor = true
						break
					end
				end
			end
		end

		if not isAuthor then -- check if author is present
			for _, p in ipairs(getElementsByType("player")) do
				if p ~= source then
					local state = getElementData(p, "state")
					if state == "alive" or state == "dead" or state == "finished" then
						local name = getPlayerName(p)

						if name == g_MapAuthor then
							triggerAchievement(source, "mapauthorslow")
							break
						else
							local overrides = g_AuthorNameOverrides[g_MapAuthor]
							if overrides then
								for _, alias in ipairs(overrides) do
									if name:lower() == alias:lower() then
										triggerAchievement(source, "mapauthorslow")
										break
									end
								end
							end
						end
					end
				end
			end
		end
	end

	-- Joint Effort
	if g_currentMap == "SaveTheWeed" and getElementData(source, "weedHarvested") and getElementData(source, "weedHarvested") > 0 and time < 45000 then
		triggerAchievement(source, "jointEffort")
	end

	if g_currentMap == "Hay" then
		-- Needle in a Haystack
		if time < 120000 then
			triggerAchievement(source, "haytime")
		end
		-- Strawman
		if getPlayerCount() >= 4 and rank == 1 and not getElementData(source, "haybigfall") then
			triggerAchievement(source, "hayfall")
		end
	end

	-- Special Needs Ops
	if g_currentMap == "OperationBlack" and getElementData(source, "specialops") then
		triggerAchievement(source, "operationblack")
	end

	------------------- ATTENTION -------------------
	-- CONDITIONS BELOW REQUIRES BEING IN THE VEHICLE
	------------------- ATTENTION -------------------

	if not getPedOccupiedVehicle(source) then
		return
	end

	local vehicle = getPedOccupiedVehicle(source)
	local model = getElementModel(vehicle)

	-- Yes, Even That One
	updateObjective(source, "allvehicles", model)

	-- Lazy Gamer
	if getPedOccupiedVehicleSeat(source) ~= 0 then
		triggerAchievement(source, "general16")
	end

	-- Come Fly With Me
	if g_currentMap == "SqualoII" and model == 460 then
		triggerAchievement(source, "disco1")
	end

	-- Perfect Handling
	if g_currentMap == "SuperGTTrainingCourse" and getElementData(source, "timesDied") == 0 then
		triggerAchievement(source, "disco6")
	end

	-- Deadline
	if g_currentMap == "Deadline" and getElementData(source, "timesDied") == 0 and time < 135000 then
		triggerAchievement(source, "general5")
	end

	if g_currentMap == "CrazyTaxi" or g_currentMap == "CrazyTaxi2" then
		-- Crazy Taxi
		if getElementData(source, "Score") >= 2500 then
			triggerAchievement(source, "disco8")
		-- Excellent Driver
		elseif getElementData(source, "Score") == 0 then
			triggerAchievement(source, "disco9") end
	end

	-- Full Repossession
	if g_currentMap == "FearTheRepo" and getElementData(getPedOccupiedVehicle(source), "tvs") >= 18 then
		triggerAchievement(source, "disco3")
	end

	-- Advanced Player
	if g_currentMap == "GTAAdvanceRace" and time < 60000 then
		triggerAchievement(source, "disco2")
	end

	-- Pedal for the Medal
	if (g_currentMap == "PedalForAMedal3Party" or g_currentMap == "PedalForAMedal1Escape" or g_currentMap == "PedalForAMedal2Meeting") and time < 120000 then
		updateObjective(source, "general8", g_currentMap)
	end

	-- Procedurally Generated Race
	if g_currentMap == "ProcedurallyGeneratedRace" then
		if getVehicleTowedByVehicle(getPedOccupiedVehicle(source)) then
			-- Player has a trailer
			updateObjective(source, "disco10", getElementModel(getVehicleTowedByVehicle(getPedOccupiedVehicle(source))))
		else
			updateObjective(source, "disco10", getElementModel(getPedOccupiedVehicle(source)))
		end
	end

	-- OG Racer
	if g_currentMap == "Barnstorming" or g_currentMap == "ChopperCheckpoint" or g_currentMap == "HeliHell" or g_currentMap == "MilitaryService" or g_currentMap == "WhirlyBirdWaypoint" or g_currentMap == "WorldWarAce" or g_currentMap == "BackroadWanderer" or g_currentMap == "CityCircuit" or g_currentMap == "Freeway" or g_currentMap == "IntoTheCountry" or g_currentMap == "LittleLoop" or g_currentMap == "LowriderRace" or g_currentMap == "Vinewood" or g_currentMap == "DamRider" or g_currentMap == "DesertTricks" or g_currentMap == "LvRingroad" or g_currentMap == "SfToLv" or g_currentMap == "BanditoCounty" or g_currentMap == "CountryEndurance" or g_currentMap == "DirtbikeDanger" or g_currentMap == "GoGoKarting" or g_currentMap == "SanFierroFastlane" or g_currentMap == "SanFierroHills" then
		updateObjective(source, "general9", g_currentMap)
	end

	-- Mountain Expert
	if g_currentMap == "BirdseyeWinder" or g_currentMap == "CobraRun" or g_currentMap == "ScotchBonnetYellowRoute" then
		updateObjective(source, "general10", g_currentMap)
	end

	-- Destiny Seeker
	if g_currentMap == "IWannaFindMyDestiny" and getElementData(source, "timesDied") == 0 then
		triggerAchievement(source, "general11")
	end

	-- I'm Blind Not Stupid
	if g_currentMap == "WuZiMuButPlayingAsWoozie" then
		triggerAchievement(source, "disco13")
	end

	-- Take It Easy
	if g_currentMap == "SlowRide" and getElementData(source, "timesDied") == 0 then
		triggerAchievement(source, "disco14")
	end

	-- Alley-oop!
	if g_currentMap == "TramVsFeltzer" and getVehicleType(model) == "Train" then
		setTimer(function(player)
			if isElement(vehicle) and isTrainDerailed(vehicle) then
				triggerAchievement(player, "disco15")
			end
		end, 2000, 1, source)
	end

	-- Pilot Skill+
	if getVehicleType(model) == "Plane" or getVehicleType(model) == "Helicopter" then
		updateObjective(source, "general18", g_currentMap)
	end

	-- On the Waves
	if getVehicleType(model) == "Boat" then
		updateObjective(source, "onthewaves", g_currentMap)
	end

	-- Choo Choo
	if getVehicleType(model) == "Train" then
		updateObjective(source, "choochoo", g_currentMap)
	end

	-- I Just Need the Money
	if g_currentMap == "CatalinaQuadrilogy" then
		triggerAchievement(source, "general23")
	end

	-- Sunnyside Taxis
	if g_currentMap == "SunnysideTaxis" then
		-- Casual Driver
		if model == 420 then
			triggerAchievement(source, "disco16")
		end

		-- Every Mode
		updateObjective(source, "sunnysideEveryMode", getElementData(getResourceRootElement(getResourceFromName("SunnysideTaxis")), "currentTaxiMode"))
	end

	-- Mountain Course
	if g_currentMap == "MountainCourse" and getElementData(source, "timesDied") == 0 then
		triggerAchievement(source, "general28")
	end

	-- Getting Over It
	if g_currentMap == "GettingOverItWithBMX" or g_currentMap == "GettingOverItWithBMX2" or g_currentMap == "GettingOverItWithBMX3" then
		updateObjective(source, "general38", g_currentMap)
	end

	-- Going Up
	if (g_currentMap == "GoingUp1" or g_currentMap == "GoingUp2" or g_currentMap == "GoingUp3" or g_currentMap == "GoingUp4") and getElementData(source, "timesDied") == 0 then
		triggerAchievement(source, "sssGoingUpNoDeath")
	end

	-- Lowrider Race
	if g_currentMap == "LowriderRace" and time < 60000 then
		triggerAchievement(source, "suboneLowriderRace")
	end

	-- Monster
	if g_currentMap == "Monster" and time < 260000 then
		triggerAchievement(source, "sub420Monster")
	end

	-- BMX Challenge
	if g_currentMap == "BMXChallenge" and time < 40000 then
		triggerAchievement(source, "ogBMXChallenge")
	end

	-- CAT CUPs
	if g_currentMap == "CATCUP-BuccaneerBay" and time < 120000 then
		triggerAchievement(source, "cc24bb1")
	end
	if g_currentMap == "CATCUP-PussyPyramid" and time < 155000 then
		triggerAchievement(source, "cc24pp1")
	end
	if g_currentMap == "CATCUP-TreetopTown" and time < 125000 then
		triggerAchievement(source, "cc24tt1")
	end

	-- Dance Dance
	if g_currentMap == "DanceDance" and getElementData(source, "dance.score") == 0 then
		triggerAchievement(source, "dancedanceTerrible")
	end

	-- Nightmare Fuel
	if g_currentMap == "CinemaTrip" and getElementData(source, "cinema_fuelSkip") == 1 and model ~= 447 and getPlayerCount() >= 10 and rank == 1 then
		triggerAchievement(source, "cinemaFuelWin")
	end

	-- Phnom Penh '92
	if g_currentMap == "CinemaTrip" and rank == 1 and getPlayerCount() > 1 and model == 447 then
		triggerAchievement(source, "cinemaHeliWin")
	end

	-- You Decide What to Drive
	if (g_currentMap == "YouDecideWhatToDrive1" or g_currentMap == "YouDecideWhatToDrive2" or g_currentMap == "YouDecideWhatToDrive3") then
		if model == 583 or model == 574 then
			triggerAchievement(source, "youDecideTug") -- Tug Life
		else
			local key = g_currentMap .. "_" .. tostring(model)
			updateObjective(source, "youDecideAll", key) -- Indecisive
		end
	end

	-- Trial of the Beast
	if (g_currentMap == "GrandRallyRandomizer254CPKEKW" or g_currentMap == "GrandRallyRandomizerReverse254CPKEKW") and time < 1620000 and rank == 1 then
		triggerAchievement(source, "grandRallyWin", time)
	end

	-- He Killed My Brother
	if g_currentMap == "VanceLandscaping1" then
		triggerAchievement(source, "lancevancemow")
	end

	-- Sign me up first!
	if g_currentMap == "SecretOfTheGoldenMower" and time < 793000 then
		triggerAchievement(source, "secretMowerSignMeUp")
	end

	-- Noise Pollution
	setTimer(function(player, time)
		if isElement(player) then
			local honkTime = getElementData(player, "achs_honkingTime")
			if honkTime and (honkTime / time) >= 0.9 then
				triggerAchievement(player, "noisePollutionRace")
			end
		end
	end, 3000, 1, source, time)

	-- Typerider
	updateObjective(source, "everyVehicleType", getVehicleType(model))

	-- Randomaster
	if g_currentMap == "AeroGrandPrixRandomizer"
	or g_currentMap == "AroundMyBillboard"
	or g_currentMap == "AroundMyHouseRandomiser"
	or g_currentMap == "BicycleRandomizer"
	or g_currentMap == "CheatRandomizer"
	or g_currentMap == "CrazyProjectsRandomizer"
	or g_currentMap == "CzechoslovakiaRandomiser"
	or g_currentMap == "DriftCanyonRomp"
	or g_currentMap == "DynaLoopRandomiser"
	or g_currentMap == "DynaLoopRandomiserCollisions"
	or g_currentMap == "FortCarsonFunCourseRandomiser"
	or g_currentMap == "GoingTheDistanceRandomiser311CP"
	or g_currentMap == "GrandRallyRandomizer254CPKEKW"
	or g_currentMap == "GrandRallyRandomizerReverse254CPKEKW"
	or g_currentMap == "HoldNothingRandomiser"
	or g_currentMap == "HoldWRandomiser"
	or g_currentMap == "JoshimuzsRandomWorldOfAdventure"
	or g_currentMap == "LowriderRaceReversedAndRandomisedAndCollisionised"
	or g_currentMap == "MaximumDownhillRandomizer"
	or g_currentMap == "MonsterRandomizer"
	or g_currentMap == "MotorSpeedwayFastCarsRandomizer"
	or g_currentMap == "MulhollandADHD"
	or g_currentMap == "NascarStadium2Randomiser"
	or g_currentMap == "NascarStadium2RandomiserDerbyEdition"
	or g_currentMap == "PoliceRandomizer60FPS"
	or g_currentMap == "PressWRandomiser"
	or g_currentMap == "RandomisedLowriderRace"
	or g_currentMap == "RandomizerOvalRace"
	or g_currentMap == "RandomizerRace"
	or g_currentMap == "RandomizerRace2"
	or g_currentMap == "RandomizerRace3"
	or g_currentMap == "RandomizerRaceRerollEdition"
	or g_currentMap == "RandomLuck"
	or g_currentMap == "RandomRace"
	or g_currentMap == "Rattlesnake"
	or g_currentMap == "Real8TrackRandomizerExperience"
	or g_currentMap == "RSHaulRandomiser"
	or g_currentMap == "SanAndreasRandomizerCollisions"
	or g_currentMap == "Shanty8TrackRandomiser"
	or g_currentMap == "Shanty8TrackRandomiserCollisions"
	or g_currentMap == "SputsBoneCountyRomp"
	or g_currentMap == "SputsRandomRomp"
	or g_currentMap == "SurvivalOfTheFastest"
	or g_currentMap == "TheGrandLowriderRallyRandomiser"
	or g_currentMap == "TransportRandomiser"
	or g_currentMap == "TransportRandomiser"
	or g_currentMap == "Vandomiser"
	or g_currentMap == "VandomiserCollisions" then
		updateObjective(source, "randomaster", g_currentMap)
	end

	-- 8-Bit Win
	if (g_currentMap == "Los8BitSantos" or g_currentMap == "San8BitFierro" or g_currentMap == "Las8BitVenturas") and rank == 1 and getPlayerCount() > 2 then
		updateObjective(source, "eightBitSteer", g_currentMap)
	end

	-- With Full Gallop
	if (g_currentMap == "Steeplechase" or g_currentMap == "IKnowWhatImDoing1AHorseWithNoName" or g_currentMap == "ModernHobbyhorsing" or g_currentMap == "ModernHobbyhorsing2") and time < 200000 then
		updateObjective(source, "withFullGallop", g_currentMap)
	end

	-- Fatality
	if g_currentMap == "6058-FatalFreeway" and time < 162000 then
		triggerAchievement(source, "fatalfreewaygrindmonkey")
	end

	-- Friends With Benefits
	if g_currentMap == "Greedfall" and time < 170000 then
		triggerAchievement(source, "greedfallteamwork")
	end

	-- Just-a-nitro
	if g_currentMap == "JustARace" and getElementData(source, "allNitros") and getElementData(source, "timesDied") == 0 then
		triggerAchievement(source, "justanitro")
	end

	-- Need for Street
	if g_currentMap == "StreetX" and time < 70000 then
		triggerAchievement(source, "streetxtime")
	end

	-- The Human Element
	if g_currentMap == "QuadDrag" and time < 139000 then
		triggerAchievement(source, "quaddragtime")
	end

	-- Dragster
	if g_currentMap == "InfernusVsNRG500Drag" then
		local key = tostring(model)
		updateObjective(source, "infnrgvehicles", key)
	end

	-- Forest run
	if g_currentMap == "ForestRun" then
		-- Emergency Training
		if model == 416 and getVehicleSirensOn(vehicle) then
			triggerAchievement(source, "emergencyTraining")
		end

		-- Between the lines
		if getElementData(source, "gotofftrack") ~= 1 then
			triggerAchievement(source, "betweenthelines")
		end
	end

	-- Student Driver
	if g_currentMap == "StudentDriver" and not getElementData(source, "fuckedcones") then
		triggerAchievement(source, "patientStudent")
	end

	-- I Am a Baaaaad Man
	if g_currentMap == "ALC41Seconds" and time < 60000 and getElementData(source, "nicolascage") then
		triggerAchievement(source, "gonein41s")
	end

	-- Rush Hour 5
	if g_currentMap == "TrafficJam" and time < 60000 and getElementData(source, "timesDied") == 0 and getElementHealth(vehicle) > 900 then
		updateObjective(source, "trafficjam1", model)
	end

	-- Vagos Approved
	if (g_currentMap == "VagosTestDrive1Hermes" or g_currentMap == "VagosTestDrive2Tornado" or g_currentMap == "VagosTestDrive3Oceanic") and time < 130000 then
		updateObjective(source, "vagosApproved", g_currentMap)
	end

	-- Ballas Approved
	if (g_currentMap == "BallasTestDrive1Tahoma" or g_currentMap == "BallasTestDrive2Majestic") and time < 130000 then
		updateObjective(source, "ballasApproved", g_currentMap)
	end

	-- Rifas Approved
	if (g_currentMap == "SanFierroRifasTestDrive1Stallion" or g_currentMap == "SanFierroRifasTestDrive2Sabre" or g_currentMap == "SanFierroRifasTestDrive3Blade") and time < 130000 then
		updateObjective(source, "rifasApproved", g_currentMap)
	end

	-- Da Nang Boys Approved
	if (g_currentMap == "DaNangBoysTestDrive1Tampa" or g_currentMap == "DaNangBoysTestDrive2Manana" or g_currentMap == "DaNangBoysTestDrive3Buccaneer") and time < 130000 then
		updateObjective(source, "danangboysApproved", g_currentMap)
	end

	-- Mafia Approved
	-- if (g_currentMap == "MafiaTestDrive1Feltzer" or g_currentMap == "MafiaTestDrive2Sentinel" or g_currentMap == "MafiaTestDrive3Admiral") and time < 130000 then
		-- updateObjective(source, "mafiaApproved", g_currentMap)
	-- end

	-- Triads Approved
	-- if (g_currentMap == "SanFierroTriadsTestDrive1VEHICLE" or g_currentMap == "SanFierroTriadsTestDrive2VEHICLE" or g_currentMap == "SanFierroTriadsTestDrive3VEHICLE") and time < 130000 then
		-- updateObjective(source, "triadsApproved", g_currentMap)
	-- end

	-- Aztecas Approved
	-- if (g_currentMap == "VarriosLosAztecasTestDrive1VEHICLE" or g_currentMap == "VarriosLosAztecasTestDrive2VEHICLE" or g_currentMap == "VarriosLosAztecasTestDrive3VEHICLE") and time < 130000 then
		-- updateObjective(source, "aztecasApproved", g_currentMap)
	-- end

	-- GSF Approved
	-- if (g_currentMap == "GroveStreetFamiliesTestDrive1VEHICLE" or g_currentMap == "GroveStreetFamiliesTestDrive2VEHICLE" or g_currentMap == "GroveStreetFamiliesTestDrive3VEHICLE") and time < 130000 then
		-- updateObjective(source, "gsfApproved", g_currentMap)
	-- end

	-- Hot Stuff
	if getElementHealth(vehicle) < 250 then
		triggerAchievement(source, "firefinish")
	end

	-- Competition Race
	if g_currentMap == "CompetitionRace" and getPlayerCount() > 1 and rank == 1 then
		local winnerModel = model
		for _, v in ipairs(getAlivePlayers()) do
			if getPedOccupiedVehicle(v) and getElementModel(getPedOccupiedVehicle(v)) == winnerModel then
				updateObjective(v, "competitionWins", winnerModel)
			end
		end
	end

	-- In Control
	if (g_currentMap == "OutOfControl" or g_currentMap == "OutOfControl2" or g_currentMap == "OutOfControl3") and not getElementData(source, "achs_spinout") then
		updateObjective(source, "inControl", g_currentMap)
	end

	-- Easy to Drive?
	if g_currentMap == "DozerousTurns" and not getElementData(source, "achs_spinout") then
		triggerAchievement(source, "easyToDriveQ")
	end

	-- Damaged Goods
	if (g_currentMap == "SuicideSprint" or g_currentMap == "SuicideSprintCollisions") and rank == 1 and getElementHealth(vehicle) <= 250 then
		setElementData(source, "isDamagedGoods", true, false)
		setTimer(function(p)
			if isElement(p) then
				setElementData(p, "isDamagedGoods", false, false)
			end
		end, 1000, 1, source)
	end

	-- CARLOCKED
	if g_currentMap == "SANCHEZCASPLOCK" and getElementData(source, "didCARLOCKED") then
		triggerAchievement(source, "casplockcar")
	end

	-- Addvantage
	if (g_currentMap == "Vandomiser" or g_currentMap == "VandomiserCollisions") and not getElementData(source, "vandoNotAmbu") then
		triggerAchievement(source, "vandoachi")
	end

	-- Navigation Troubles
	if g_currentMap == "NavigationTroubles" and not getElementData(source, "fuckedup") then
		triggerAchievement(source, "navigationTroublesPerfect")
	end

	-- FACE/OFF
	if (g_currentMap == "Face2Face" or g_currentMap == "Face2Face2Face")
	and getPlayerCount() > 9 and getElementData(source, "timesDied") == 0 then
		triggerAchievement(source, "face2face2face2face2")
	end

	-- Janissary
	if g_currentMap == "JumpingSultan" and getElementData(source, "timesDied") == 0 and getElementData(source, "jumpingsultannorepair") then
		triggerAchievement(source, "jumpingsultan")
	end

	-- That's How Physics Works
	if g_currentMap == "IDontNeedNoParachute" and getElementData(source, "parachuteAchievement") then
		triggerAchievement(source, "iDoNeedAParachute")
	end

	-- Featherweight
	if g_currentMap == "Gridlock" and getElementData(source, "gridlocker") then
		triggerAchievement(source, "gridlockvehicles")
	end

	-- Pothead
	if model == 594 and rank == 1 then
		updateObjective(source, "pothead", g_currentMap)
	end

	-- The Brakes Is Out
	if (g_currentMap == "Unbraked2" or g_currentMap == "Unbraked3") and getElementData(source, "ach_boolean") then
		updateObjective(source, "unbraked", g_currentMap)
	end

	-- Backwards Compatible
	if reverseOnly[source] ~= false then
		triggerAchievement(source, "reversingonly", g_currentMap)
	end

	-- Cone Crazier
	if g_currentMap == "1236-ExpertVanDriver" and getElementData(source, "ach_boolean") and time <= 260000 then
		triggerAchievement(source, "expertvandriver1")
	end

	-- Rock Hard Truckin'
	if g_currentMap == "ChiliadsToughestTrucker" and getElementData(source, "ach_boolean") then
		local trailer = getVehicleTowedByVehicle(vehicle)
		if trailer and getElementModel(trailer) == 435 then
			triggerAchievement(source, "chiliadtruck1")
			setTimer(function()
				if isElement(trailer) then
					destroyElement(trailer)
				end
			end, 3000, 1)
		end
	end
end )

addEvent("onPlayerReachCheckpoint", true)
addEventHandler("onPlayerReachCheckpoint", root, function(checkpoint, time)

	-- Checkmate
	triggerAchievement(source, "checkpointcheckmate")

	if not getPedOccupiedVehicle(source) then
		return
	end
	-- Randomizers with all vehicles
	if g_currentMap == "GoingTheDistanceRandomiser311CP"
	or g_currentMap == "GrandRallyRandomizer254CPKEKW"
	or g_currentMap == "GrandRallyRandomizerReverse254CPKEKW"
	or g_currentMap == "HoldWRandomiser"
	or g_currentMap == "LowriderRaceReversedAndRandomisedAndCollisionised"
	or g_currentMap == "MonsterRandomizer"
	or g_currentMap == "RandomizerOvalRace"
	or g_currentMap == "RandomizerRace"
	or g_currentMap == "RandomizerRace2"
	or g_currentMap == "RandomizerRace3"
	or g_currentMap == "RandomizerRaceRerollEdition"
	or g_currentMap == "Real8TrackRandomizerExperience"
	or g_currentMap == "Shanty8TrackRandomiser"
	or g_currentMap == "Shanty8TrackRandomiserCollisions"
	or g_currentMap == "SputsBoneCountyRomp" then
		setTimer(function(player, checkpoint)
			if not isElement(player) or not getPedOccupiedVehicle(player) then
				return
			end

			-- Wrap in tonumber() so 'false' becomes 'nil'
			local oldOldModel = tonumber(getElementData(player, "ach_oldoldcar"))
			local oldModel = tonumber(getElementData(player, "ach_oldcar"))
			local newModel = tonumber(getElementModel(getPedOccupiedVehicle(player)))

			if getElementData(player, "race.checkpoint") and getElementData(player, "race.checkpoint") - 1 ~= checkpoint then
				return
			end

			-- Safely verify all three are valid numbers before proceeding
			if oldOldModel and oldModel and newModel then
				if oldOldModel == oldModel and oldModel == newModel then
					-- Triple
					triggerAchievement(player, "randoTriple")
				else
					local slowCars = {485, 574, 530, 486, 532, 531, 583, 572, 606, 607, 594, 441, 457, 571, 564}
					local isASlowCar = {false, false, false}
					local isAFastCar = {false, false, false}

					-- check if it's a junk car
					for i = 1, #slowCars do
						if oldOldModel == slowCars[i] then
							isASlowCar[1] = true
						end
						if oldModel == slowCars[i] then
							isASlowCar[2] = true
						end
						if newModel == slowCars[i] then
							isASlowCar[3] = true
						end
					end

					-- Check if it's a fast car
					local handling = {getOriginalHandling(oldOldModel), getOriginalHandling(oldModel), getOriginalHandling(newModel)}
					for i = 1, 3 do
						-- Added 'handling[i]' safeguard to prevent indexing a boolean if the model is invalid
						if handling[i] and handling[i]["maxVelocity"] >= 205 then
							isAFastCar[i] = true
						end
					end

					-- Never Lucky
					if isASlowCar[1] and isASlowCar[2] and isASlowCar[3] then
						triggerAchievement(player, "randoNeverLucky")
					end

					-- Always Lucky
					if isAFastCar[1] and isAFastCar[2] and isAFastCar[3] then
						triggerAchievement(player, "randoAlwaysLucky")
					end
				end
			end

			-- fill stack
			setElementData(player, "ach_oldoldcar", getElementData(player, "ach_oldcar"))
			setElementData(player, "ach_oldcar", getElementModel(getPedOccupiedVehicle(player)))
		end, math.max(getPlayerPing(source) * 2, 500), 1, source, checkpoint)
	end

	-- Peaking Early
	if g_currentMap == "RandomizerRaceRerollEdition" and checkpoint == 1 and time < 8400 then
		triggerAchievement(source, "randoRerollEarly1st")
	end

	-- Houston, We Have a Problem
	if g_currentMap == "TryAgain" and (checkpoint == 4 or checkpoint == 6 or checkpoint == 7) then
		local player = source
		setTimer(function(player)
			local _, _, z = getElementPosition(player)
			if z > 1000 and z < 15000 then
				triggerAchievement(player, "tryagainspace")
			end
		end, 3000, 1, player)
	end
end )

addEvent("onPlayerPickUpRacePickup", true)
addEventHandler("onPlayerPickUpRacePickup", root, function(pickupID, pickupType, vehicleModel)
	-- "Almost!"
	if pickupType == "repair" and getPedOccupiedVehicle(source) and getElementHealth(getPedOccupiedVehicle(source)) < 250 then
		triggerAchievement(source, "general32")
	end

	-- Fire Cream
	if g_currentMap == "BaysideJinglyJingly" and pickupType == "nitro" then
		triggerAchievement(source, "sssAveh423Nitro")
	end

	-- Loot Goblin
	triggerAchievement(source, "pickupachi")

	-- Janissary
	if g_currentMap == "JumpingSultan" then
		setElementData(source, "jumpingsultannorepair", false)
	end

	-- Me vs BS
	if g_currentMap == "BFvsBF" then
		local model = tostring(vehicleModel)
		updateObjective(source, "bfvsbfvehs", model)
	end
end )

addEventHandler("onPlayerLogin", root, function(_, account)
	-- In the Beginning
	triggerAchievement(source, "general14")
	-- Always Fresh
	updateObjective(source, "general27", getPlayerVersion(source))

	-- Full Time Job
	local player = source
	setTimer(function(p)
		if isElement(p) then
			triggerAchievement(p, "fulltimejob")
		end
	end, 18000000, 1, player)
end )

-- Achievement trigger for "Annihilator", derby support and generic "deathless" support
addEventHandler("onPlayerWasted", root, function(_, killer, deathType)
	setElementData(source, "timesDied", (getElementData(source, "timesDied") or 0) + 1)

	-- Dildo Collection
	if g_currentMap == "HalfDildo" and killer and isElement(killer) then
		updateObjective(killer, "dildoCollection", deathType)
	end

	-- Wasted Potential
	triggerAchievement(source, "1000deaths")

	-- Not Quite Nine Lives
	-- updateObjective(source, "notQuiteNineLives", deathType)
	updateDeaths(deathType)

	-- Later, Creator
	local attacker = getElementData(source, "achs_attackedBy")
	if attacker ~= source then
		local playerName = getPlayerName(source)

		-- Check if the player's name matches the direct g_MapAuthor
		-- OR if g_MapAuthor has overrides and the player's name is in the overrides list
		local isMapAuthor = false
		if playerName == g_MapAuthor then
			isMapAuthor = true
		else
			local overrides = g_AuthorNameOverrides[g_MapAuthor]
			if overrides then
				for _, overrideName in ipairs(overrides) do
					if playerName:lower() == overrideName:lower() then -- Case-insensitive comparison
						isMapAuthor = true
						break
					end
				end
			end
		end

		if isMapAuthor then
			triggerAchievement(attacker, "mapauthorkill")
		end
	end

	if g_currentMap_Type == "DD" and getElementData(source, "achs_attackedBy") then
		-- Hoist the Colours
		if g_currentMap == "BumperBlistas" then
			local flagID = getElementData(source, "currentFlag")
			updateObjective(attacker, "bumperflags", flagID)
		end

		-- Annihilator
		setElementData(getElementData(source, "achs_attackedBy"), "achs_kills", getElementData(getElementData(source, "achs_attackedBy"), "achs_kills") + 1)
		triggerAchievement(getElementData(source, "achs_attackedBy"), "general37")

		-- Towerful
		if (getElementData(getElementData(source, "achs_attackedBy"), "achs_kills") or 0) >= 5 then
			triggerAchievement(attacker, "dd5kills")
		end

		setElementData(source, "achs_attackedBy", false) -- Reset the state
		if isTimer(DD_timers[source]) then
			killTimer(DD_timers[source])
		end
	end

	-- Auto-Selfie
	if hitByOwnVehicle[source] then
		triggerAchievement(source, "selfRunOver")
		hitByOwnVehicle[source] = nil
	end
end )

-- Maps handler
addEventHandler("onMapStarting", root, function(mapInfo)
	g_MapAuthor = mapInfo.author or nil
	local currentMap = call(getResourceFromName("mapmanager"), "getRunningGamemodeMap")
	if currentMap then
		g_currentMap = getResourceName(currentMap)
		g_currentMap_Type = getResourceInfo(currentMap, "racetype") or "god knows what"
	end

	finishTimes = {} -- Photo Finish reset
	finishers = {} -- Double Trouble reset
	hitByOwnVehicle = {} -- Auto-Selfie reset
	lastDrivenVehicle = {} -- Auto-Selfie reset
	vehicleDamage = {} -- Insurance Fraud reset
	reverseOnly = {} -- Backwards Compatible reset
	underdogTime = {} -- Underdog reset
	underdogLastCheck = {} -- Underdog reset

	-- Kill all DD timers
	for i, v in ipairs(DD_timers) do
		if isTimer(v) then
			killTimer(v)
		end
	end

	for _, player in ipairs(getElementsByType("player")) do
		setElementData(player, "timesDied", 0, false) -- deaths reset

		if g_currentMap == "JumpingSultan" then -- Janissary reset
			setElementData(player, "jumpingsultannorepair", true)
		end
	end
end )

addEvent("onRaceStateChanging", true)
addEventHandler("onRaceStateChanging", root, function(newState, oldState)
	if newState == "PostFinish" and g_currentMap_Type == "DD" then
		local alive = getAlivePlayers()
		local winner = alive[1]
		if winner then
			-- Dynamic Demolitionist
			updateObjective(winner, "ddwinner", g_currentMap)

			-- Hunter-gatherer
			if g_currentMap == "61Towers" and getElementData(winner, "ach_boolean", true) then
				triggerAchievement(winner, "61towersach")
			end
		end
	end
	-- Participation Trophy
	if newState == "PostFinish" and g_currentMap_Type ~= "DD" then
		for _, player in ipairs(getElementsByType("player")) do
			if not finishedThisRace[player] then
				finishStreak[player] = 0
			end
		end
		finishedThisRace = {}
	end
	-- Underdog
	if newState == "Running" and oldState == "GridCountdown" then
		underdogTime = {}
		underdogLastCheck = {}
	end
	-- press b pls
	if newState == "TimesUp" then
		for _, player in ipairs(getElementsByType("player")) do
			local raceState = getElementData(player, "state")
			if raceState == "alive" then
				triggerAchievement(player, "hurryhurryhurry")
			end
		end
	end
end )

-- Achievement trigger for "First!", "Double Time", "Wise Man" and also derby support
addEventHandler("onElementDataChange", root, function(theKey, oldValue, newValue)

	if getElementType(source) ~= "player" then
		return
	end

	if theKey == "ach_topTime1" and newValue > (oldValue or 0) then
		triggerAchievement(source, "general4")

		if newValue >= 2 then
			triggerAchievement(source, "general6")
		end

		-- Stunting/skill maps for Taurus
		if g_currentMap == "10000PercentDifficult"
		or g_currentMap == "AerodromeAgility"
		or g_currentMap == "AnnoyingCraneOfAbsoluteDoom"
		or g_currentMap == "BlazingChandelleStage1"
		or g_currentMap == "BlazingChandelleStage2"
		or g_currentMap == "BlazingChandelleStage3"
		or g_currentMap == "ClimbUp"
		or g_currentMap == "GettingOverItWithBMX"
		or g_currentMap == "GettingOverItWithBMX2"
		or g_currentMap == "GettingOverItWithBMX3"
		or g_currentMap == "GettingOverSuzukiWithNRG500"
		or g_currentMap == "GettingOverWuziWithNRG500"
		or g_currentMap == "GoingUp1"
		or g_currentMap == "GoingUp2"
		or g_currentMap == "GoingUp3"
		or g_currentMap == "GoingUp4"
		or g_currentMap == "KnowYourGameMechanics"
		or g_currentMap == "LostInReflection"
		or g_currentMap == "MadnessAtTheMedicalCenter"
		or g_currentMap == "ReDSSRace"
		or g_currentMap == "RooftopRagequit"
		or g_currentMap == "SanchezPlayground"
		or g_currentMap == "SkillIssue2"
		or g_currentMap == "SkillTFCTestrace"
		or g_currentMap == "TheHighRollerHard"
		or g_currentMap == "ThreadingTheNeedle"
		or g_currentMap == "VeryNoobFriendly" then
			triggerAchievement(source, "stuntskillmaps")
		end
	end

	-- Wise Man
	if theKey == "quizScore" and g_currentMap == "AWiseManFromTheEast" and getPlayerCount() > 1 then
		if newValue > (oldValue or 0) then
			setElementData(source, "timesDied", (getElementData(source, "timesDied") or 0) + 1) -- used as score
			if getElementData(source, "timesDied") == 5 then
				triggerAchievement(source, "general13")
			end
		elseif newValue < (oldValue or 0) then
			setElementData(source, "timesDied", 0)
		end -- reset "score"
	end

	-- DD kills stuff
	if theKey == "achs_attackedBy" and newValue ~= false then
		if isTimer(DD_timers[source]) then
			killTimer(DD_timers[source])
		end

		DD_timers[source] = setTimer(function(player)
			if isElement(player) then
				setElementData(player, "achs_attackedBy", false)
			end
		end, 30000, 1, source)
	end

	-- Count Double B as death
	if theKey == "race.spectating" and newValue == true then
		setElementData(source, "timesDied", (getElementData(source, "timesDied") or 0) + 1)
	end

	-- Der Rote Baron
	if theKey == "flappy_baron:highscore"
	and tonumber(newValue)
	and tonumber(newValue) > (tonumber(oldValue) or 0)
	and tonumber(newValue) >= 100 then
		triggerAchievement(source, "flappybaron")
	end

	-- Corner Three!
	if theKey == "basketball:score"
	and tonumber(newValue)
	and tonumber(newValue) > (tonumber(oldValue) or 0)
	and tonumber(newValue) >= 25 then
		triggerAchievement(source, "basketball")
	end

	-- Underdog
	if theKey == "race rank" and newValue and newValue ~= "" then
		local player = source
		local now = getTickCount()
		local previousRank = tonumber(oldValue)
		local currentRank = tonumber(newValue)

		underdogTime[player] = underdogTime[player] or 0

		if underdogLastCheck[player] and previousRank and previousRank >= 5 then
			underdogTime[player] = underdogTime[player] + (now - underdogLastCheck[player])
		end

		if currentRank and currentRank >= 5 then
			underdogLastCheck[player] = now
		else
			underdogLastCheck[player] = nil
		end
	end
end )

-- Derby support
addEvent("getAttacker", true)
addEventHandler("getAttacker", root, function(attackedWho)
	if g_currentMap_Type == "DD" then
		setElementData(attackedWho, "achs_attackedBy", source)
	end
end )

-- Support for trigger_c.lua
addEvent("achievement", true)
addEventHandler("achievement", root, function(achievementID)
	triggerAchievement(client, achievementID, nil)
end )

addEventHandler("onPlayerDamage", root, function(attacker, weapon, bodypart, loss)
	-- Auto-Selfie
	if g_currentMap_Type == "F" and attacker and getElementType(attacker) == "vehicle" then
		local victim = source
		local driver = getVehicleOccupant(attacker, 0)

		if driver == victim then
			hitByOwnVehicle[victim] = true
		end
	end
	if g_currentMap_Type ~= "DD" then
		return
	end

	if attacker and getElementType(attacker) == "vehicle" then
		setElementData(source, "lastAttackerVehicle", attacker)
	end
end )

function updateWithMultipleObjectives(player, ach, data)
	if #data > 0 then
		for _, v in pairs(data) do
			if isElement(v) then
				updateObjective(player, ach, getPlayerSerial(v))
			end
		end
	end
end

-- Photographed
addEvent("photographUpdatePlayers", true)
addEventHandler("photographUpdatePlayers", root, function(photographedPlayers)
	updateWithMultipleObjectives(source, "paparazzi", photographedPlayers)
end )

-- Water turrets trigger
addEvent("waterCannonUpdatePlayers", true)
addEventHandler("waterCannonUpdatePlayers", root, function(sprayedPlayers)
	updateWithMultipleObjectives(source, "sprayEveryPlayer", sprayedPlayers)
end )

-- Honk on every player
addEvent("honkUpdatePlayers", true)
addEventHandler("honkUpdatePlayers", root, function(honkedPlayers)
	updateWithMultipleObjectives(source, "honkEveryPlayer", honkedPlayers)
end )

-- Drive on every surface
addEvent("updateCollectedMaterials", true)
addEventHandler("updateCollectedMaterials", root, function(material)
	updateObjective(source, "driveOnEverySurface", material)
end )

function checkTrains(vehicle, player)
	-- Off the Rails
	if getVehicleType(vehicle) == "Train" and not isTrainDerailed(vehicle) then
		trains[player] = vehicle
	elseif trains[player] and (getVehicleType(vehicle) ~= "Train" or (getVehicleType(vehicle) == "Train" and isTrainDerailed(vehicle))) then
		trains[player] = nil
	end
end

addEventHandler("onElementModelChange", root, function(old, new)
	if getElementType(source) == "vehicle" and getVehicleType(new) == "Train" and getVehicleOccupant(source) then
		checkTrains(source, getVehicleOccupant(source))
	end
end )

addEventHandler("onPlayerVehicleEnter", root, function(vehicle, seat)
	-- Player entered car as a driver
	if seat == 0 then
		lastDrivenVehicle[source] = vehicle -- Auto-Selfie
		checkTrains(vehicle, source)        -- Train derailment Ach
	end

	-- In the Carpool Lane
	setTimer(function(player, vehicle)
		if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then
			return
		end

		player = getVehicleOccupant(vehicle, 0)

		if not isElement(player) or getPedOccupiedVehicle(player) ~= vehicle then
			return
		end

		local occupants = getVehicleOccupants(vehicle)
		if not occupants then
			return
		end

		local passengerCount = 0
		for seat, ped in pairs(occupants) do
			if getElementType(ped) ~= "player" then
				return
			end
			if seat ~= 0 then
				passengerCount = passengerCount + 1
			end
		end

		if passengerCount > 2 then
			triggerAchievement(player, "lotsofpassengers")
		end
	end, 1000, 1, source, vehicle)
end )

-- Identity Crisis
addEventHandler("onPlayerChangeNick", root, function(oldNick, newNick)
	if source and oldNick ~= newNick and not wasEventCancelled() then
		triggerAchievement(source, "nameachi")
	end
end )

function updateDeaths(deathType)
	-- Deaths tracker
	local found = false
	if #deathsTracker ~= 0 then
		for _, death in ipairs(deathsTracker) do
			if death == deathType then
				found = true
				break
			end
		end
	end

	if not found then
		table.insert(deathsTracker, deathType)
		local file = fileOpen("deaths.json")
		if file then
			fileWrite(file, toJSON(deathsTracker))
			fileClose(file)
		else
			iprint("[Achievements] ERROR: Could not open deaths.json for writing")
		end
	end
end

addEventHandler("onVehicleExplode", root, function()
	-- Damaged Goods
	local player = getVehicleController(source)
	if (g_currentMap == "SuicideSprint" or g_currentMap == "SuicideSprintCollisions") and player and getElementData(player, "isDamagedGoods") then
		triggerAchievement(player, "damagedgoods1")
	end
end )

addEventHandler("onVehicleDamage", root, function(loss)
	if not loss or loss <= 0 then
		return
	end
	-- Insurance Fraud
	local driver = getVehicleController(source)
	if not driver then
		return
	end

	if not vehicleDamage[driver] then
		vehicleDamage[driver] = 0
	end

	vehicleDamage[driver] = vehicleDamage[driver] + loss

	if vehicleDamage[driver] >= 10000 and getElementData(driver, "timesDied") == 0 then
		triggerAchievement(driver, "vehdamaging")
		vehicleDamage[driver] = 0
	end
end )


-- Gotta Catch 'Em All
addEvent("pokedex:pokemonCaught", true)
addEventHandler("pokedex:pokemonCaught", root, function(pokeIndex)
	local player = client
	if not player or getElementType(player) ~= "player" then
		return
	end

	local idx = tonumber(pokeIndex)
	if not idx or idx < 1 or idx > 151 then
		return
	end
	updateObjective(player, "151pokemon", idx)
end )

-- Shame of Name
addEvent("lore:nicknameRated", true)
addEventHandler("lore:nicknameRated", root, function()
	local player = client
	if not player or getElementType(player) ~= "player" then
		return
	end
	triggerAchievement(player, "ratenickname")
end )

-- Want Some Free Rare Candy?
addEvent("missingnoDone", true)
addEventHandler("missingnoDone", root, function()
	local player = client
	if not player or getElementType(player) ~= "player" then
		return
	end
	triggerAchievement(player, "missingno")
end )

addEvent("usedAccelerate", true)
addEventHandler("usedAccelerate", root, function()
	reverseOnly[client] = false
end)

addEventHandler("onPlayerQuit", root, function()
	winStreak[source] = nil
	finishStreak[source] = nil
	finishedThisRace[source] = nil
	lastDrivenVehicle[source] = nil
	hitByOwnVehicle[source] = nil
end )
