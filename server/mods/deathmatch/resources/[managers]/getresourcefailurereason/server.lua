for _, v in ipairs(getResources()) do
	if getResourceState(v) == "failed to load" then
		outputChatBox("Resource: " .. getResourceName(v) .. " failed to load because: " .. getResourceLoadFailureReason(v) .. ".")
	end
end
