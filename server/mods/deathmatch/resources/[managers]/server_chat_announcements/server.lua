local chatCycle = 1

local spamMessages = {
    "¡Recuerda usar /rate (0-10)! Los mapas con calificaciones bajas serán considerados para su eliminación.",
    "Si tienes algún mapa que te gustaría que agreguemos, contacta a @ezekah o @anakeenskywalker en Discord.",
    "Por favor, reporta a los jugadores que actúen de manera inapropiada escribiendo /report y seleccionando 'Player Complaints' (Quejas de jugadores). Estos se revisarán regularmente.",
    "Presiona F9 para ver información sobre los comandos y recursos del servidor.",
    "¡Recuerda usar /register si aún no lo has hecho! Esto asegura que todos tus datos y configuraciones se guarden por completo.",
    "Escribe /report para informarnos sobre problemas con mapas o recursos, sugerir nuevas ideas o reportar a jugadores problemáticos.",
    "Escribe /autologin para iniciar sesión automáticamente al entrar.",
    "Escribe /cpblips seguido de 2 o 3 para cambiar el número de puntos de control/iconos que se muestran en el minimapa.",
}

addEventHandler("onResourceStart", resourceRoot, function()
	setTimer(spamChat, 240000, 0)
end )

function spamChat()
	if chatCycle <= #spamMessages then
		outputChatBox(spamMessages[chatCycle], root, 23, 198, 29) -- #17C61D
		chatCycle = chatCycle + 1
	else
		chatCycle = 1
	end
end

-- /me message adjustment is now done by Twitch Emotes Core
