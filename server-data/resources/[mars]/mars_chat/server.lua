local lastMessage = {}

local function clean(text)
    text = tostring(text or ''):gsub('[%c]', ' ')
    text = text:gsub('^%s+', ''):gsub('%s+$', '')
    if #text > ChatConfig.MaxLength then text = text:sub(1, ChatConfig.MaxLength) end
    return text
end

local function spam(src)
    local now = GetGameTimer()
    if lastMessage[src] and now - lastMessage[src] < ChatConfig.SpamSeconds * 1000 then return true end
    lastMessage[src] = now
    return false
end

local function characterName(src)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    local info = ok and player and player.PlayerData and player.PlayerData.charinfo
    if info and info.firstname then
        return ('%s %s'):format(info.firstname, info.lastname or '')
    end
    return GetPlayerName(src) or ('#' .. src)
end

local function send(target, author, text, color)
    TriggerClientEvent('chat:addMessage', target, { color = color, args = { author, text } })
end

local function sendNear(src, radius, author, text, color)
    local origin = GetEntityCoords(GetPlayerPed(src))
    for _, id in ipairs(GetPlayers()) do
        local pid = tonumber(id)
        if #(GetEntityCoords(GetPlayerPed(pid)) - origin) <= radius then
            send(pid, author, text, color)
        end
    end
end

-- plain text from the chat box -> people nearby
RegisterNetEvent('mars_chat:server:say', function(text)
    local src = source
    text = clean(text)
    if text == '' or spam(src) then return end

    -- legacy hook used by some resources
    TriggerEvent('chatMessage', src, GetPlayerName(src), text)
    if WasEventCanceled() then return end

    sendNear(src, ChatConfig.LocalRadius, characterName(src), text, { 255, 255, 255 })
end)

-- roleplay commands
for name, cmd in pairs(ChatConfig.Commands) do
    RegisterCommand(name, function(src, args)
        if src == 0 then return end
        local text = clean(table.concat(args, ' '))
        if text == '' or spam(src) then return end

        local author
        if cmd.ooc then
            author = ('[%s] %s (%d)'):format(cmd.label, GetPlayerName(src), src)
        elseif cmd.action then
            author = ('%s %s'):format(cmd.label, characterName(src))
        else
            author = ('[%s] %s'):format(cmd.label, characterName(src))
        end

        if cmd.radius then
            sendNear(src, cmd.radius, author, text, cmd.color)
        else
            send(-1, author, text, cmd.color)
        end
    end, false)
end

-- command suggestions (only commands the player may use)
local function sendSuggestions(src)
    local list = {}
    for _, c in ipairs(GetRegisteredCommands()) do
        if IsPlayerAceAllowed(src, ('command.%s'):format(c.name)) then
            local cfg = ChatConfig.Commands[c.name]
            list[#list + 1] = { name = '/' .. c.name, help = cfg and cfg.help or '' }
        end
    end
    TriggerClientEvent('chat:addSuggestions', src, list)
end

RegisterNetEvent('mars_chat:server:ready', function() sendSuggestions(source) end)

AddEventHandler('playerDropped', function() lastMessage[source] = nil end)
