-- Custom polls by Ali Digitali
-- anyone reading this has permission to coppy parts of this script

-- star the poll created clientside
function voteStartHandler(question,options,duration)

	local poll = {
		title=tostring("Player Poll: " .. question),
		percentage=0,
		timeout=duration,
		allowchange=true,
		visibleTo=root
		}

	-- add the options to the list of answers
	for index,item in ipairs(options) do
		table.insert(poll,item)
	end

	-- start the poll
	local pollDidStart,errorCode = exports.votemanager:startPoll(poll)
	triggerClientEvent(source,"updateErrorBox",root,pollDidStart,errorCode)
end
addEvent("voteStart",true)
addEventHandler("voteStart",root,voteStartHandler)

function checkRightHandler()
	if hasObjectPermissionTo(source,"resource.poll",false) then
		triggerClientEvent(source,"showPollGui",root)
	end
end
addEvent("checkRight",true)
addEventHandler("checkRight",root,checkRightHandler)
