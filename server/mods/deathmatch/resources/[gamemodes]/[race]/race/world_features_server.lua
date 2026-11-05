WorldFeatures = {}

local trafficResources = { 'native-ped-traffic', 'native-vehicle-traffic' }
local wantedResource = 'native-wanted-police'
local stopOrder = { wantedResource, 'native-vehicle-traffic', 'native-ped-traffic' }
local missingWarned = {}

local function setResourceRunning(name, shouldRun)
	local resource = getResourceFromName(name)
	if not resource then
		if shouldRun and not missingWarned[name] then
			missingWarned[name] = true
			outputWarning("WorldFeatures: resource '" .. name .. "' is not installed")
		end
		return
	end

	local state = getResourceState(resource)
	if shouldRun then
		if state ~= 'running' then
			local ok = startResource(resource)
			outputDebugString('WorldFeatures: start ' .. name .. ' -> ' .. tostring(ok))
		end
	elseif state == 'running' then
		local ok = stopResource(resource)
		outputDebugString('WorldFeatures: stop ' .. name .. ' -> ' .. tostring(ok))
	end
end

function WorldFeatures.apply(options)
	options = options or {}
	for _, name in ipairs(trafficResources) do
		setResourceRunning(name, options.traffic == true)
	end
	setResourceRunning(wantedResource, options.wanted == true)
end

function WorldFeatures.stopAll()
	for _, name in ipairs(stopOrder) do
		setResourceRunning(name, false)
	end
end
