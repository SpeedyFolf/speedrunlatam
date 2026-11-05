local function pushToCore()
	local myEmotes = {}
	local resName = getResourceName(resource)

	local function scan(dir)
		local files = pathListDir(dir)
		if files then
			for _, f in ipairs(files) do
				local path = dir .. "/" .. f
				if pathIsDirectory(path) then
					scan(path)
				elseif f:match("%.png$") then
					local name = f:match("([^/]+)%.png$")
					if name then
						table.insert(myEmotes, {name = name, path = ":" .. resName .. "/" .. path})
					end
				end
			end
		end
	end

	scan("Emotes")

	-- Try to register. If core isn't ready, we'll try again when onResourceStart triggers for the core.
	if getResourceState(getResourceFromName("twitch_emotes_core")) == "running" then
		if exports.twitch_emotes_core and exports.twitch_emotes_core.registerEmotes then
			exports.twitch_emotes_core:registerEmotes(resName, myEmotes)
		end
	end
end

-- This fires when THIS pack starts OR when the CORE starts
addEventHandler("onResourceStart", root, function(res)
	if res == resourceRoot or getResourceName(res) == "twitch_emotes_core" then
		-- Small delay ensures the export is actually accessible
		setTimer(pushToCore, 500, 1)
	end
end)
