--[[
    Mars Community 2 – admins by Citizen ID
    ---------------------------------------
    VMP players often have no stable Steam/Rockstar identifier, so admin rights
    are given by QBox Citizen ID instead (shown in the server log as
    "lol (Citizen ID: XXXXXXXX ...) has successfully loaded!").

    server.cfg:
      set mars:admins "G2NRW24I,ABCD1234"
      add_ace resource.mars_identity command.add_principal allow
      add_ace resource.mars_identity command.remove_principal allow

    When a listed character loads, the player gets group.admin for this session
    and is opted in to admin mode automatically (qbx_core requireOptIn).
]]

local function adminSet()
    local set = {}
    for id in GetConvar('mars:admins', ''):gmatch('[^,%s]+') do set[id:upper()] = true end
    return set
end

local granted = {}

local function grant(src, citizenid)
    if granted[src] then return end
    granted[src] = true
    ExecuteCommand(('add_principal player.%d group.admin'):format(src))
    print(('[mars_identity] admin rights given to %s (Citizen ID %s)'):format(GetPlayerName(src) or src, citizenid))

    -- qbx_core only allows admin commands after /optin; do it automatically
    SetTimeout(500, function()
        local ok, optedIn = pcall(function() return exports.qbx_core:IsOptin(src) end)
        if ok and not optedIn then pcall(function() exports.qbx_core:ToggleOptin(src) end) end
    end)
end

local function check(player)
    local data = player and player.PlayerData
    if not data or not data.citizenid then return end
    if adminSet()[data.citizenid:upper()] then grant(data.source, data.citizenid) end
end

AddEventHandler('QBCore:Server:PlayerLoaded', check)

AddEventHandler('playerDropped', function()
    local src = source
    if granted[src] then
        granted[src] = nil
        ExecuteCommand(('remove_principal player.%d group.admin'):format(src))
    end
end)

-- also apply to players already in game when this resource (re)starts
CreateThread(function()
    Wait(2000)
    local ok, players = pcall(function() return exports.qbx_core:GetQBPlayers() end)
    if ok and players then
        for _, player in pairs(players) do check(player) end
    end
end)
