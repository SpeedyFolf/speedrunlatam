local currentSound = nil
local lastTrack = ""
local currentStationData = {}
currentRadioVolume = 100

local stations = radioStations

function setRadioVolume(volume)
	if not volume or volume < 0 or volume > 500 then
		return false
	end

	currentRadioVolume = volume
	if isElement(currentSound) then
		setSoundVolume(currentSound, volume / 100)
	end
	if updateRadioVolumeControl then
		updateRadioVolumeControl(volume)
	end

	return true
end

function playRadioStream(url, name, genre)
	if isElement(currentSound) then
		stopSound(currentSound)
	end

	currentSound = playSound(url)
	lastTrack = ""
	currentStationData = { name = name, genre = genre or "Unknown" }

	if currentSound then
		setSoundVolume(currentSound, currentRadioVolume / 100)
		outputChatBox("#00FF00[Radio] #FFFFFFNow Playing: #FFFF00" .. name .. " #BBBBBB(" .. currentStationData.genre .. ")", 255, 255, 255, true)
	else
		outputChatBox("Failed to connect to " .. name, 255, 0, 0)
	end
end

function stopRadioStream()
	if isElement(currentSound) then
		stopSound(currentSound)
		outputChatBox("Radio Stopped", 255, 0, 0)
	end
end

-- Command: /radiolist [page]
addCommandHandler("radiolist", function(cmd, page)
	local keys = {}
	for key in pairs(stations) do
		table.insert(keys, key)
	end
	table.sort(keys)

	local pageSize = 10
	local pageCount = math.max(1, math.ceil(#keys / pageSize))
	local pageNumber = 1
	if page then
		pageNumber = tonumber(page)
	end
	if not pageNumber or pageNumber % 1 ~= 0 or pageNumber < 1 or pageNumber > pageCount then
		outputChatBox("#FF9900Usage: /radiolist [page] (1-" .. pageCount .. ")", 255, 150, 0, true)
		return
	end

	outputChatBox("#00FF00Radio stations (page " .. pageNumber .. "/" .. pageCount .. "):", 255, 255, 255, true)
	for index = (pageNumber - 1) * pageSize + 1, math.min(pageNumber * pageSize, #keys) do
		local key = keys[index]
		outputChatBox("#FFFF00" .. key .. " #FFFFFF- " .. stations[key].name .. " (" .. stations[key].genre .. ")", 255, 255, 255, true)
	end
end, false)

-- Command: /radio [station key]
addCommandHandler("radio", function(cmd, stationKey)
	if not stationKey then
		toggleRadioWindow()
		return
	end

	if not stations[stationKey] then
		outputChatBox("Usage: /radio [station key]. Use /radio or /radiolist [page] to browse.", 255, 150, 0)
		return
	end

	local s = stations[stationKey]
	playRadioStream(s.url, s.name, s.genre)
end, false)

-- Command: /customradio [url]
addCommandHandler("customradio", function(cmd, url)
	if not url then
		outputChatBox("Usage: /customradio [url]. Use console (backtick/F8) to paste. Pasting may be built into chat in the future. Don't use slash when using commands in console.", 255, 150, 0)
		return
	end
	-- If it's an iHeart link, we strip the HLS suffix just in case
	local cleanUrl = url:gsub("/hls.m3u8.*", "")
	playRadioStream(cleanUrl, "Custom Stream")
end, false)

-- Command: /stopradio
addCommandHandler("stopradio", function()
	stopRadioStream()
end, false)

-- Command: /vol [0-500]
addCommandHandler("vol", function(cmd, volume)
	volume = tonumber(volume)

	-- Allow volume up to 500% (artificial amplification)
	if not volume or volume < 0 or volume > 500 then
		outputChatBox("Usage: /vol [0-500]. Use /radio to open the GUI for a slider.", 255, 150, 0)
		return
	end

	setRadioVolume(volume)
	if isElement(currentSound) then
		if volume > 100 then
			-- Output in green with an orange warning attached
			outputChatBox("#00FF00Volume set to " .. volume .. "% #FF9900(Warning: Audio distortion may occur above 100%)", 255, 255, 255, true)
		else
			outputChatBox("Volume set to " .. volume .. "%", 0, 255, 0)
		end
	end
end, false)

-- Metadata Check (Now Playing)
-- This runs every 5 seconds to see if the song title changed
setTimer(function()
	if isElement(currentSound) then
		local meta = getSoundMetaTags(currentSound)
		-- Note: Many radio streams hide metadata in 'stream_title' instead of 'title'
		local trackName = meta and (meta.stream_title or meta.title)

		if trackName and trackName ~= "" and trackName ~= lastTrack then
			lastTrack = trackName
			outputChatBox("#FFFF00[Radio] #FFFFFFTrack: " .. trackName, 255, 255, 255, true)
		end
	end
end, 5000, 0)
