-- Blacklist certain maps from having a third checkpoint blip displayed on the minimap.
-- Any_order maps purposefully have the blipsize of regular checkpoints set to 0.
-- However, if a player chooses to have a third checkpoint blip displayed on the minimap, a regular checkpoint's blip will be visible even on any_order maps.
-- This is due to the third checkpoint blip's size being set to 1 upon its creation.
-- Not only is this completely unnecessary but can also be potentially confusing to some players on certain maps such as "Billboard Bagging" by Mawfeen.
-- This would of course also conflict with other maps that have their checkpoint's blipsize purposefully set to 0.
-- This is the case on maps such as "Super FleischBerg© Autos" or "Filler Map Quick Latency Test".
-- Other maps, such as "Maproll Challenge - Trust me, bro", have been blacklisted in order to not interfere with their checkpoint-related gimmick.

RadarCpBlipsBlacklists = {
	-- Blacklist any_order maps from having a third checkpoint blip displayed on the radar / minimap.
	organizationalFolders = {
		"[maps]/[R]/[AnyOrder]",
		"[maps]/[F]/[AnyOrder]",
	},

	-- Blacklist these individual maps from having a third checkpoint blip displayed on the radar / minimap as well.
	maps = {
		["Airpain3"] = true,
		["AllHorseshoes"] = true,
		["AllSnapshots"] = true,
		["AllTags"] = true,
		["BackToSchool"] = true,
		["BattleRoyal"] = true,
		["BloodBowlRandomTrack"] = true,
		["BMXChallenge"] = true,
		["ChaosMod"] = true,
		["ChaseTheCheckpoint"] = true,
		["FillerMapQuickLatencyTest"] = true,
		["Freight"] = true,
		["GoLeftGoRight"] = true,
		["ImportExportRace"] = true,
		["ImportExportRace2"] = true,
		["MapRollChallengeTrustMeBro"] = true,
		["NRG500"] = true,
		["PackMule"] = true,
		["PlayerForGeneratedRaces"] = true,
		["PlayerForGeneratedRacesFestiveEdition"] = true,
		["ProcedurallyGeneratedRace"] = true,
		["ProcedurallyGeneratedRaceFestiveEdition"] = true,
		["PropertyRun"] = true,
		["TheRankedRace"] = true,
		["SanAndreasRally898CPKEKW"] = true,
		["ShuffledRace"] = true,
		["SunnysideTaxis"] = true,
		["SuperFleischbergAutos"] = true,
		["SuperFleischbergAutosCollisions"] = true,
		["SuperFleischbergAutosFestiveEdition"] = true,
		["SuperFleischbergAutosFestiveEditionCollisions"] = true,
		-- add more maps here over time if necessary
	},
}
