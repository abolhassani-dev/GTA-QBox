local isOpen = false

local function open()
    if isOpen or IsPauseMenuActive() then return end
    isOpen = true
    SetNuiFocus(true, false)
    SendNUIMessage({ type = 'open' })
end

local function close()
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

RegisterCommand('+mars_chat', open, false)
RegisterCommand('-mars_chat', function() end, false)
RegisterKeyMapping('+mars_chat', 'Open chat', 'keyboard', ChatConfig.OpenKey)

RegisterNUICallback('send', function(data, cb)
    cb('ok')
    close()
    local text = tostring(data.message or '')
    if text == '' then return end
    if text:sub(1, 1) == '/' then
        -- client and server commands (/admin, /ooc, /me ...)
        ExecuteCommand(text:sub(2))
    else
        TriggerServerEvent('mars_chat:server:say', text)
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb('ok')
    close()
end)

-- ── public chat API (same events as the Cfx chat resource) ──

AddEventHandler('chat:addMessage', function(message)
    if type(message) == 'string' then message = { args = { message } } end
    SendNUIMessage({ type = 'message', message = message })
end)
RegisterNetEvent('chat:addMessage')

-- very old API: chatMessage(author, color, text)
RegisterNetEvent('chatMessage', function(author, color, text)
    SendNUIMessage({ type = 'message', message = { color = color, args = { author, text } } })
end)

AddEventHandler('chat:addSuggestion', function(name, help)
    SendNUIMessage({ type = 'suggestions', list = { { name = name, help = help or '' } } })
end)
RegisterNetEvent('chat:addSuggestion')

RegisterNetEvent('chat:addSuggestions', function(list)
    SendNUIMessage({ type = 'suggestions', list = list })
end)

RegisterNetEvent('chat:removeSuggestion', function(name)
    SendNUIMessage({ type = 'removeSuggestion', name = name })
end)

RegisterNetEvent('chat:clear', function()
    SendNUIMessage({ type = 'clear' })
end)

AddEventHandler('chat:addTemplate', function() end)
RegisterNetEvent('chat:addTemplate')

CreateThread(function()
    SendNUIMessage({ type = 'config', fade = ChatConfig.FadeSeconds, max = ChatConfig.MaxMessages, maxLength = ChatConfig.MaxLength })
    -- suggestions for client-side commands
    Wait(3000)
    TriggerServerEvent('mars_chat:server:ready')
    for _, c in ipairs(GetRegisteredCommands()) do
        if c.name:sub(1, 1) ~= '+' and c.name:sub(1, 1) ~= '-' then
            SendNUIMessage({ type = 'suggestions', list = { { name = '/' .. c.name, help = '' } } })
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
