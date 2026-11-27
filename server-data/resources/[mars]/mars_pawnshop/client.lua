local npc
local isOpen = false

local function openShop()
    local h = GetClockHours()
    if Config.Hours.open ~= 0 or Config.Hours.close ~= 24 then
        if h < Config.Hours.open or h >= Config.Hours.close then
            return lib.notify({ title = Config.ShopName, description = ('Open %02d:00 – %02d:00.'):format(Config.Hours.open, Config.Hours.close), type = 'error' })
        end
    end
    local state = lib.callback.await('mars_pawn:server:state', false)
    if not state then return end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', state = state, images = 'nui://ox_inventory/web/images/' })
end

local function closeShop()
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

RegisterNUICallback('close', function(_, cb) cb('ok'); closeShop() end)

-- every UI action goes to the server and returns the fresh shop state
local function action(event)
    return function(data, cb)
        local res = lib.callback.await(event, false, data.name, data.count, data.haggle)
        if res and res.ok and res.ticket then
            PlaySoundFrontend(-1, 'PURCHASE', 'HUD_LIQUOR_STORE_SOUNDSET', true)
        elseif res and not res.ok then
            PlaySoundFrontend(-1, 'ERROR', 'HUD_AMMO_SHOP_SOUNDSET', true)
        end
        cb(res or { ok = false, msg = 'No answer from the shop.' })
    end
end

RegisterNUICallback('sell', action('mars_pawn:server:sell'))
RegisterNUICallback('buy', action('mars_pawn:server:buy'))
RegisterNUICallback('buyBlack', action('mars_pawn:server:buyBlack'))
RegisterNUICallback('melt', action('mars_pawn:server:melt'))
RegisterNUICallback('collect', action('mars_pawn:server:collect'))
RegisterNUICallback('refresh', function(_, cb) cb({ ok = true, state = lib.callback.await('mars_pawn:server:state', false) }) end)

-- ── NPC and blip ──

CreateThread(function()
    local c = Config.Npc.coords
    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, Config.Blip.sprite); SetBlipColour(blip, Config.Blip.color); SetBlipScale(blip, Config.Blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(Config.ShopName); EndTextCommandSetBlipName(blip)

    while true do
        local near = #(GetEntityCoords(cache.ped) - c.xyz) < 60.0
        if near and not npc then
            lib.requestModel(Config.Npc.model, 10000)
            npc = CreatePed(4, Config.Npc.model, c.x, c.y, c.z - 1.0, c.w, false, true)
            FreezeEntityPosition(npc, true)
            SetEntityInvincible(npc, true)
            SetBlockingOfNonTemporaryEvents(npc, true)
            TaskStartScenarioInPlace(npc, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
            SetModelAsNoLongerNeeded(Config.Npc.model)
            exports.ox_target:addLocalEntity(npc, {
                { name = 'mars_pawn_open', icon = 'fa-solid fa-gem', label = ('Talk to %s'):format(Config.ShopName), distance = 2.5, onSelect = openShop },
            })
        elseif not near and npc then
            exports.ox_target:removeLocalEntity(npc)
            DeleteEntity(npc); npc = nil
        end
        Wait(2000)
    end
end)

RegisterNetEvent('mars_pawn:client:policeAlert', function(coords)
    lib.notify({ title = '911 Report', description = 'Suspicious sale of valuables at the pawn shop.', type = 'warning', duration = 8000 })
    local blip = AddBlipForRadius(coords.x, coords.y, coords.z, 60.0)
    SetBlipColour(blip, 1); SetBlipAlpha(blip, 120)
    SetTimeout(60000, function() RemoveBlip(blip) end)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    if npc then DeleteEntity(npc) end
end)

-- ── /pawnadmin ──

local openAdmin

local function editNumber(path, label, current, min, max)
    local input = lib.inputDialog(label, { { type = 'number', label = ('%s (%s – %s)'):format(label, min, max), default = current, min = min, max = max, step = 0.01, required = true } })
    if input then
        local ok, msg = lib.callback.await('mars_pawn:admin:set', false, path, input[1])
        lib.notify({ title = 'Pawn admin', description = msg, type = ok and 'success' or 'error' })
    end
end

local function openItem(it)
    lib.registerContext({
        id = 'mars_pawnadmin_item', title = it.label, menu = 'mars_pawnadmin_items',
        options = {
            { title = ('Min price: $%d'):format(it.min), onSelect = function() editNumber(('Items.%s.min'):format(it.name), 'Min price', it.min, 1, 1000000); openAdmin() end },
            { title = ('Max price: $%d'):format(it.max), onSelect = function() editNumber(('Items.%s.max'):format(it.name), 'Max price', it.max, 1, 1000000); openAdmin() end },
            { title = ('Market: -%d%% • stock %d%s'):format(math.floor(it.saturation * 100), it.stock, it.hot and ' • HOT' or ''), readOnly = true },
        },
    })
    lib.showContext('mars_pawnadmin_item')
end

openAdmin = function()
    local data = lib.callback.await('mars_pawn:admin:data', false)
    if not data then return end
    local itemOptions = {}
    for _, it in ipairs(data.items) do
        itemOptions[#itemOptions + 1] = {
            title = ('%s%s'):format(it.hot and '🔥 ' or '', it.label),
            description = ('$%d – $%d • market -%d%% • stock %d'):format(it.min, it.max, math.floor(it.saturation * 100), it.stock),
            arrow = true, onSelect = function() openItem(it) end,
        }
    end
    lib.registerContext({ id = 'mars_pawnadmin_items', title = 'Item prices', menu = 'mars_pawnadmin', options = itemOptions })

    local options = {
        { title = 'Item prices ▸', icon = 'fa-solid fa-tags', arrow = true, onSelect = function() lib.showContext('mars_pawnadmin_items') end },
    }
    for _, s in ipairs(data.settings) do
        options[#options + 1] = {
            title = ('%s: %s'):format(s.label, tostring(s.value)), icon = 'fa-solid fa-sliders',
            onSelect = function() editNumber(s.path, s.label, s.value, s.min, s.max); openAdmin() end,
        }
    end
    options[#options + 1] = { title = 'Pick new hot items', icon = 'fa-solid fa-fire', onSelect = function()
        local ok, msg = lib.callback.await('mars_pawn:admin:action', false, 'rotateHot')
        lib.notify({ title = 'Pawn admin', description = msg, type = ok and 'success' or 'error' }); openAdmin() end }
    options[#options + 1] = { title = 'Reset market prices', icon = 'fa-solid fa-rotate-left', onSelect = function()
        local ok, msg = lib.callback.await('mars_pawn:admin:action', false, 'resetMarket')
        lib.notify({ title = 'Pawn admin', description = msg, type = ok and 'success' or 'error' }); openAdmin() end }
    options[#options + 1] = { title = 'Teleport to the shop', icon = 'fa-solid fa-location-arrow', onSelect = function()
        local c = Config.Npc.coords
        SetEntityCoords(cache.ped, c.x + 1.0, c.y - 1.0, c.z, false, false, false, false) end }

    lib.registerContext({ id = 'mars_pawnadmin', title = 'Pawn shop – Admin', options = options })
    lib.showContext('mars_pawnadmin')
end

RegisterNetEvent('mars_pawn:client:openAdmin', openAdmin)
