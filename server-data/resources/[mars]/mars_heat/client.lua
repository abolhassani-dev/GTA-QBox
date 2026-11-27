-- mars_heat client: HUD, crime detection, /rep menu, police alerts, /heatadmin

local hudOn = GetResourceKvpInt('mars_heat_hud_off') ~= 1

local function isPolice()
    local data = exports.qbx_core:GetPlayerData()
    return data and data.job and data.job.type == Config.Police.jobType
end

-- ─────────────────────────────────────────────────────────────
-- HUD
-- ─────────────────────────────────────────────────────────────
local function pushHud()
    local heat = LocalPlayer.state.marsHeat or 0
    local tier = Config.TierFor(heat)
    SendNUIMessage({ action = 'heat', show = hudOn and heat >= 1, heat = heat, max = Config.MaxHeat,
                     label = tier.label, color = tier.color })
end

AddStateBagChangeHandler('marsHeat', ('player:%s'):format(cache.serverId), function()
    Wait(0); pushHud()
end)

CreateThread(function() Wait(2000); pushHud() end)

RegisterCommand('heathud', function()
    hudOn = not hudOn
    SetResourceKvpInt('mars_heat_hud_off', hudOn and 0 or 1)
    pushHud()
    lib.notify({ title = 'Street', description = hudOn and 'Heat meter shown.' or 'Heat meter hidden.' })
end, false)

RegisterNetEvent('mars_heat:client:tier', function(index, up)
    local t = Config.Tiers[index]
    lib.notify({
        title = up and 'Heat rising' or 'Heat cooling down',
        description = up and ('The police are getting interested. You are now: %s'):format(t.label)
                          or ('Things are calming down. You are now: %s'):format(t.label),
        type = up and 'warning' or 'success', duration = 6000,
    })
end)

-- ─────────────────────────────────────────────────────────────
-- crimes the game can see: shooting, killing, carjacking
-- ─────────────────────────────────────────────────────────────
local ignored = {}
for _, w in ipairs(Config.IgnoreWeapons) do ignored[w] = true end
local last = {}

local function report(key)
    local c = Config.Crimes[key]
    local now = GetGameTimer()
    if last[key] and now - last[key] < (c.cooldown or 10) * 1000 then return end
    last[key] = now
    if isPolice() then return end
    TriggerServerEvent('mars_heat:server:crime', key)
end

CreateThread(function()
    while true do
        local ped = cache.ped
        local sleep = 500
        if IsPedArmed(ped, 4) then
            sleep = 0
            if IsPedShooting(ped) and not ignored[GetSelectedPedWeapon(ped)] then report('shooting') end
        end
        if IsPedJacking(ped) then report('carjack') end
        Wait(sleep)
    end
end)

AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local victim, attacker = args[1], args[2]
    if attacker ~= cache.ped or victim == cache.ped then return end
    if not DoesEntityExist(victim) or not IsEntityAPed(victim) or not IsPedHuman(victim) then return end
    if GetPedType(victim) == 28 then return end
    if IsEntityDead(victim) or IsPedDeadOrDying(victim, true) then report('npc_kill') end
end)

-- ─────────────────────────────────────────────────────────────
-- police alerts
-- ─────────────────────────────────────────────────────────────
RegisterNetEvent('mars_heat:client:policeAlert', function(coords, radius, title, text)
    lib.notify({ title = ('911: %s'):format(title), description = text, type = 'warning', duration = 8000 })
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)
    local area = AddBlipForRadius(coords.x, coords.y, coords.z, radius)
    SetBlipColour(area, 1); SetBlipAlpha(area, 110)
    local pin = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(pin, 161); SetBlipColour(pin, 1); SetBlipScale(pin, 0.9)
    BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(('911: %s'):format(title)); EndTextCommandSetBlipName(pin)
    SetTimeout(Config.Police.blipSeconds * 1000, function() RemoveBlip(area); RemoveBlip(pin) end)
end)

-- ─────────────────────────────────────────────────────────────
-- /rep : your street profile
-- ─────────────────────────────────────────────────────────────
local function openProfile()
    local data = lib.callback.await('mars_heat:server:profile', false)
    if not data then return lib.notify({ title = 'Street', description = 'Your character is not loaded yet.', type = 'error' }) end
    local tier, tierIndex = Config.TierFor(data.heat)
    local mins = Config.DecayPerMinute > 0 and math.ceil(data.heat / Config.DecayPerMinute) or 0
    local options = {
        {
            title = ('Heat: %s  (%d / %d)'):format(tier.label, math.floor(data.heat), Config.MaxHeat),
            description = data.police and 'Police officers never gain heat.'
                or (data.heat >= 1 and ('Cools down fully in about %d min. Higher heat = police get called more often.'):format(mins)
                    or 'The police know nothing about you.'),
            icon = 'fa-solid fa-fire', iconColor = tier.color,
            progress = math.floor(data.heat / Config.MaxHeat * 100),
            colorScheme = tierIndex >= 4 and 'red' or tierIndex >= 3 and 'orange' or tierIndex >= 2 and 'yellow' or 'green',
            readOnly = true,
        },
    }
    for _, r in ipairs(data.rep) do
        local cur = Config.RepLevels[r.level]
        local pct = r.nextXp and math.floor((r.xp - cur.xp) / (r.nextXp - cur.xp) * 100) or 100
        options[#options + 1] = {
            title = ('%s reputation: %s  (level %d/%d)'):format(r.name, r.label, r.level, #Config.RepLevels),
            description = r.nextXp and ('%d / %d xp to the next level'):format(r.xp, r.nextXp) or ('%d xp – max level'):format(r.xp),
            icon = r.icon, progress = pct, colorScheme = 'violet', arrow = true,
            metadata = {
                { label = 'Sale prices', value = ('+%d%%'):format(math.floor((r.priceMult - 1) * 100 + 0.5)) },
                { label = 'Customers say yes', value = ('+%d%%'):format(r.acceptBonus) },
            },
            onSelect = function()
                local lines = {}
                for i, l in ipairs(Config.RepLevels) do
                    lines[#lines + 1] = ('%s **%s** – %d xp – prices +%d%%, customers +%d%%'):format(
                        i == r.level and '▶' or '•', l.label, l.xp, math.floor((l.priceMult - 1) * 100 + 0.5), l.acceptBonus)
                end
                lib.alertDialog({ header = ('%s reputation levels'):format(r.name), content = table.concat(lines, '  \n'), centered = true })
                openProfile()
            end,
        }
    end
    options[#options + 1] = {
        title = 'How do I get reputation?', icon = 'fa-solid fa-circle-question',
        description = 'Selling drugs raises Drugs and Street rep. Selling goods at the pawn shop raises Street rep. Every crime also raises your heat.',
        readOnly = true,
    }
    options[#options + 1] = {
        title = hudOn and 'Hide heat meter' or 'Show heat meter', icon = 'fa-solid fa-eye',
        onSelect = function() ExecuteCommand('heathud'); openProfile() end,
    }
    lib.registerContext({ id = 'mars_heat_profile', title = 'Street profile', options = options })
    lib.showContext('mars_heat_profile')
end

RegisterCommand('rep', openProfile, false)
RegisterCommand('heat', openProfile, false)
TriggerEvent('chat:addSuggestion', '/rep', 'Your heat and criminal reputation')
TriggerEvent('chat:addSuggestion', '/heat', 'Your heat and criminal reputation')
TriggerEvent('chat:addSuggestion', '/heathud', 'Show / hide the heat meter')

-- ─────────────────────────────────────────────────────────────
-- settings sync
-- ─────────────────────────────────────────────────────────────
RegisterNetEvent('mars_heat:client:setting', function(path, value) Config.SetPath(path, value) end)
CreateThread(function()
    for path, value in pairs(lib.callback.await('mars_heat:server:settings', false) or {}) do Config.SetPath(path, value) end
end)

-- ─────────────────────────────────────────────────────────────
-- /heatadmin
-- ─────────────────────────────────────────────────────────────
local openAdmin

local function adminNotify(ok, msg) lib.notify({ title = 'Heat admin', description = msg, type = ok and 'success' or 'error' }) end

local function openPlayer(p)
    local options = {
        { title = ('Heat: %d (%s)'):format(math.floor(p.heat), Config.TierFor(p.heat).label), icon = 'fa-solid fa-fire',
          description = 'Set a new heat value', onSelect = function()
              local input = lib.inputDialog('Set heat', { { type = 'slider', label = 'Heat', default = math.floor(p.heat), min = 0, max = Config.MaxHeat } })
              if input then adminNotify(lib.callback.await('mars_heat:admin:setHeat', false, p.id, input[1])) end
              openAdmin()
          end },
        { title = 'Clear heat (0)', icon = 'fa-solid fa-snowflake', onSelect = function()
              adminNotify(lib.callback.await('mars_heat:admin:setHeat', false, p.id, 0)); openAdmin()
          end },
    }
    for _, r in ipairs(p.rep) do
        options[#options + 1] = {
            title = ('%s rep: %d xp (%s)'):format(r.name, r.xp, Config.LevelFor(r.xp).label), icon = 'fa-solid fa-star',
            description = 'Set reputation xp',
            onSelect = function()
                local levels = {}
                for _, l in ipairs(Config.RepLevels) do levels[#levels + 1] = { value = l.xp, label = ('%s (%d xp)'):format(l.label, l.xp) } end
                local input = lib.inputDialog(('%s reputation'):format(r.name), {
                    { type = 'select', label = 'Jump to level', options = levels, clearable = true },
                    { type = 'number', label = 'Or exact xp', default = r.xp, min = 0 },
                })
                if input then
                    adminNotify(lib.callback.await('mars_heat:admin:setRep', false, p.id, r.key, input[1] or input[2]))
                end
                openAdmin()
            end,
        }
    end
    lib.registerContext({ id = 'mars_heat_admin_player', title = ('%s (ID %d)'):format(p.name, p.id), menu = 'mars_heat_admin', options = options })
    lib.showContext('mars_heat_admin_player')
end

local function openSettings()
    local options = {}
    for _, e in ipairs(Config.Editable) do
        options[#options + 1] = {
            title = ('%s: %s'):format(e.label, tostring(Config.GetPath(e.path))), icon = 'fa-solid fa-sliders',
            onSelect = function()
                local input = lib.inputDialog(e.label, { { type = 'number', label = ('%s – %s'):format(e.min, e.max), default = Config.GetPath(e.path), min = e.min, max = e.max, step = 0.1, precision = 1 } })
                if input then adminNotify(lib.callback.await('mars_heat:admin:setting', false, e.path, input[1])) end
                Wait(200); openSettings()
            end,
        }
    end
    options[#options + 1] = { title = 'Reset all settings to default', icon = 'fa-solid fa-rotate-left', onSelect = function()
        if lib.alertDialog({ header = 'Reset', content = 'Reset all heat settings to config.lua?', centered = true, cancel = true }) == 'confirm' then
            adminNotify(lib.callback.await('mars_heat:admin:reset', false))
        end
    end }
    lib.registerContext({ id = 'mars_heat_admin_settings', title = 'Heat settings', menu = 'mars_heat_admin', options = options })
    lib.showContext('mars_heat_admin_settings')
end

openAdmin = function()
    local list = lib.callback.await('mars_heat:admin:players', false) or {}
    local options = {
        { title = 'Settings ▸', description = 'Cool-down speed, police sightings, heat per crime', icon = 'fa-solid fa-gear', arrow = true, onSelect = openSettings },
    }
    for _, p in ipairs(list) do
        local tier = Config.TierFor(p.heat)
        local reps = {}
        for _, r in ipairs(p.rep) do reps[#reps + 1] = ('%s: %s'):format(r.name, Config.LevelFor(r.xp).label) end
        options[#options + 1] = {
            title = ('%d – %s'):format(p.id, p.name), description = table.concat(reps, '  •  '),
            icon = 'fa-solid fa-user', iconColor = tier.color, arrow = true,
            progress = math.floor(p.heat / Config.MaxHeat * 100),
            colorScheme = p.heat >= 60 and 'red' or p.heat >= 40 and 'orange' or p.heat >= 20 and 'yellow' or 'green',
            onSelect = function() openPlayer(p) end,
        }
    end
    lib.registerContext({ id = 'mars_heat_admin', title = 'Heat & Reputation – players (hottest first)', options = options })
    lib.showContext('mars_heat_admin')
end

RegisterNetEvent('mars_heat:client:admin', function() openAdmin() end)
