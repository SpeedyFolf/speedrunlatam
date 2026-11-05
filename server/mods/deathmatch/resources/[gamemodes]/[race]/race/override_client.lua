--
-- override_client.lua
--

-------------------------------------------------------
--
-- OverrideClient
--
-- Apply element vars for alpha and collideness
--
--------------------------------------------------------
OverrideClient = {}
OverrideClient.method = "fast"
OverrideClient.debug = false

-- getElementData returns false (not nil) when the key is missing.
local function hasKey( element, key )
	local value = getElementData( element, key, false )
	return value ~= false and value ~= nil
end

addEventHandler('onClientElementStreamIn', root,
	function()
		if getElementType( source ) == "vehicle" or getElementType( source ) == "player" then
			OverrideClient.updateVars( source )
		end
	end
)

addEventHandler('onClientElementDataChange', root,
	function(dataName)
		if dataName == "race.collideothers" or dataName == "race.collideworld" or dataName == "race.alpha"  then
			OverrideClient.updateVars( source )
		end
	end
)

function OverrideClient.updateVars( element )
	-- Abort if the element is nil (e.g., player is on foot)
	if not isElement(element) then return end

	-- Alpha
	local alpha = getElementData ( element, "race.alpha" )
	if alpha then
		setElementAlpha ( element, alpha )
	end
	if OverrideClient.method ~= "fast" then return end
	if not isVersion102Compatible() then
		if g_Vehicle then
			-- 1.0 and 1.0.1
			-- Collide others: only between race-managed vehicles
			local collideothers = isCollideOthers ( g_Vehicle )
			for _,other in ipairs( getElementsByType( "vehicle" ) ) do
				if other ~= g_Vehicle and hasKey( other, "race.collideothers" ) then
					local docollide = collideothers and isCollideOthers ( other )
					setElementCollisionsEnabled ( other, docollide )
					setHeliBladeCollisionsEnabled( other, docollide )
				end
			end
			-- Collide world
			local collideworld = isCollideWorld ( g_Vehicle )
			setElementCollisionsEnabled ( g_Vehicle, collideworld )
		end
	else
		-- 1.0.2
		-- Collide others: only between race-managed vehicles
		if hasKey( element, "race.collideothers" ) then
			local collideothers = isCollideOthers ( element )
			for _,other in ipairs( getElementsByType( "vehicle" ) ) do
				if other ~= element and hasKey( other, "race.collideothers" ) then
					local docollide = collideothers and isCollideOthers ( other )
					setElementCollidableWith ( element, other, docollide )
					setHeliBladeCollisionsEnabled( other, docollide )
				end
			end
		end
		-- Collide world: only for race-managed elements
		if hasKey( element, "race.collideworld" ) then
			local collideworld = isCollideWorld ( element )
			setElementCollisionsEnabled ( element, collideworld )
		end
	end

end

function isCollideOthers ( element )
	if not isElement(element) then return false end
	return ( getElementData ( element, 'race.collideothers' ) or 0 ) ~= 0
end

function isCollideWorld ( element )
	if not isElement(element) then return true end
	return ( getElementData ( element, 'race.collideworld' ) or 1 ) ~= 0
end

--
-- Emergency backup method - Works, but is slower and doesn't look as nice
--
addEventHandler('onClientPreRender', root,
	function()
		if OverrideClient.method ~= "slow" then return end
		if g_Vehicle then
			-- Collide others: only between race-managed vehicles
			local collideothers = isCollideOthers ( g_Vehicle )
			for _,vehicle in ipairs( getElementsByType( "vehicle" ) ) do
				if vehicle ~= g_Vehicle and hasKey( vehicle, "race.collideothers" ) then
					local docollide = collideothers and isCollideOthers ( vehicle )
					setElementCollisionsEnabled ( vehicle, docollide )
					setHeliBladeCollisionsEnabled( vehicle, docollide )
				end
			end
			-- Collide world
			local collideworld = isCollideWorld ( g_Vehicle )
			setElementCollisionsEnabled ( g_Vehicle, collideworld )
		end
	end
)

-----------------------------------------------
-- Debug output
if OverrideClient.debug then
	addEventHandler('onClientRender', root,
		function()
			local sx = { 30, 200, 280, 360, 420, 500 }
			local sy = 200
			dxDrawText ( "name", sx[1], sy )
			dxDrawText ( "collisions", sx[2], sy )
			dxDrawText ( "colwith#", sx[3], sy )
			dxDrawText ( "col-othrs", sx[4], sy )
			dxDrawText ( "col-wrld", sx[5], sy )
			sy = sy + 25
			for _,vehicle in ipairs(getElementsByType("vehicle")) do
				local count = not isElementCollidableWith and "n/a" or 0
				for _,vehicle2 in ipairs(getElementsByType("vehicle")) do
					if vehicle ~= vehicle2 then
						if isElementCollidableWith and isElementCollidableWith( vehicle, vehicle2 ) then
							count = count + 1
						end
					end
				end
				local player = getVehicleController(vehicle)
				local collisions = not isVehicleCollisionsEnabled and "n/a" or isVehicleCollisionsEnabled(vehicle)
				local collideothers = getElementData ( vehicle, "race.collideothers" )
				local collideworld = getElementData ( vehicle, "race.collideworld" )
				dxDrawText ( getElementDesc(vehicle), sx[1], sy )
				dxDrawText ( tostring(collisions), sx[2], sy )
				dxDrawText ( tostring(count), sx[3], sy )
				dxDrawText ( tostring(collideothers), sx[4], sy )
				dxDrawText ( tostring(collideworld), sx[5], sy )
				sy = sy + 20
			end
		end
	)
end
