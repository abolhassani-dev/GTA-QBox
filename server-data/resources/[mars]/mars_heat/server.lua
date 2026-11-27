-- mars_heat server: heat + reputation per character (citizenid), saved in the database.
-- Other scripts use the exports at the bottom of this file.

local players = {}   -- [src] = { cid = 'ABC', heat = 0, rep = { street = 0, drugs = 0 }, dirty = false }
local cooldowns = {} -- [src] = { [crime] = os.time() }
local overrides, defaults = {}, {}

local function notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Street', description = msg, type = kind or 'inform' })
end

local function getPlayer(src) return exports.qbx_core:GetPlayer(src) end

local function isPolice(src)
    local p = getPlayer(src)
    local job = p and p.PlayerData.job
    return job and job.type == Config.Police.jobType, job and job.onduty
end

local function isAdmin(src) return IsPlayerAceAllowed(src, 'admin') end

local function round1(x) return math.floor(x * 10 + 0.5) / 10 end

-- ─────────────────────────────────────────────────────────────
-- database
-- ─────────────────────────────────────────────────────────────
MySQL.ready(function()
    MySQL.query([[CREATE TABLE IF NOT EXISTS `mars_heat` (
        `citizenid` VARCHAR(50) NOT NULL PRIMARY KEY,
        `heat` FLOAT NOT NULL DEFAULT 0,
        `rep` LONGTEXT NULL,
        `updated` INT NOT NULL DEFAULT 0)]])
    MySQL.query([[CREATE TABLE IF NOT EXISTS `mars_heat_settings` (
        `path` VARCHAR(100) NOT NULL PRIMARY KEY,
        `value` LONGTEXT NOT NULL)]])
    Wait(500)
    for _, row in ipairs(MySQL.query.await('SELECT path, value FROM mars_heat_settings') or {}) do
        local value = json.decode(row.value)
        if defaults[row.path] == nil then defaults[row.path] = Config.GetPath(row.path) end
        if Config.SetPath(row.path, value) then overrides[row.path] = value end
    end
end)

local function save(src)
    local d = players[src]
    if not d or not d.dirty then return end
    d.dirty = false
    MySQL.query('REPLACE INTO mars_heat (citizenid, heat, rep, updated) VALUES (?, ?, ?, ?)',
        { d.cid, d.heat, json.encode(d.rep), os.time() })
end

-- push heat to the player's state bag (client HUD + police can read it)
local function publish(src)
    local d = players[src]
    if not d then return end
    Player(src).state:set('marsHeat', round1(d.heat), true)
end

local function load(src)
    local p = getPlayer(src)
    if not p then return end
    local cid = p.PlayerData.citizenid
    local row = MySQL.single.await('SELECT heat, rep, updated FROM mars_heat WHERE citizenid = ?', { cid })
    local heat, rep = 0, {}
    if row then
        local offlineMin = math.max(0, os.time() - (row.updated or 0)) / 60
        heat = math.max(0, row.heat - offlineMin * Config.OfflineDecayPerMinute)
        rep = json.decode(row.rep or '{}') or {}
    end
    for _, c in ipairs(Config.RepCategories) do rep[c.key] = rep[c.key] or 0 end
    players[src] = { cid = cid, heat = heat, rep = rep, dirty = true }
    publish(src)
end

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = player.PlayerData.source
    CreateThread(function() load(src) end)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    save(src); players[src] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    save(src); players[src] = nil; cooldowns[src] = nil
end)

AddEventHandler('onResourceStart', function(name)
    if name ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1500)
        for _, id in ipairs(GetPlayers()) do load(tonumber(id)) end
    end)
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for src in pairs(players) do save(src) end
end)

-- ─────────────────────────────────────────────────────────────
-- heat
-- ─────────────────────────────────────────────────────────────
local function setHeat(src, value, reason)
    local d = players[src]
    if not d then return 0 end
    local before = d.heat
    d.heat = math.max(0, math.min(Config.MaxHeat, value))
    d.dirty = true
    publish(src)
    local oldTier, oldIndex = Config.TierFor(before)
    local newTier, newIndex = Config.TierFor(d.heat)
    if newIndex ~= oldIndex then
        TriggerClientEvent('mars_heat:client:tier', src, newIndex, newIndex > oldIndex, reason)
    end
    return d.heat
end

local function addHeat(src, amount, reason)
    local d = players[src]
    if not d or amount == 0 then return d and d.heat or 0 end
    if amount > 0 and isPolice(src) then return d.heat end
    return setHeat(src, d.heat + amount, reason)
end

local function alertChance(src, base)
    local d = players[src]
    local heat = d and d.heat or 0
    return math.min(100, (base or 0) + heat * Config.AlertBonusPerHeat)
end

-- send an area (not the exact spot) to every on-duty police officer
local function policeAlert(coords, title, text, radius)
    radius = radius or Config.Police.alertRadius
    local area = vec3(coords.x + math.random(-30, 30), coords.y + math.random(-30, 30), coords.z)
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local cop, onduty = isPolice(id)
        if cop and onduty then
            TriggerClientEvent('mars_heat:client:policeAlert', id, area, radius, title, text)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- reputation
-- ─────────────────────────────────────────────────────────────
local function addRep(src, cat, xp)
    local d = players[src]
    if not d or not xp or xp == 0 then return 0 end
    local before = d.rep[cat] or 0
    d.rep[cat] = math.max(0, before + xp)
    d.dirty = true
    local _, oldIdx = Config.LevelFor(before)
    local level, newIdx = Config.LevelFor(d.rep[cat])
    if newIdx > oldIdx then
        local label = cat
        for _, c in ipairs(Config.RepCategories) do if c.key == cat then label = c.label end end
        notify(src, ('%s reputation is now %s! Better prices and more customers.'):format(label, level.label), 'success')
    end
    return d.rep[cat]
end

local function repInfo(src, cat)
    local d = players[src]
    local xp = d and d.rep[cat] or 0
    local level, index, nextLevel = Config.LevelFor(xp)
    return { xp = xp, level = index, label = level.label, priceMult = level.priceMult,
             acceptBonus = level.acceptBonus, nextXp = nextLevel and nextLevel.xp }
end

-- ─────────────────────────────────────────────────────────────
-- crimes
-- ─────────────────────────────────────────────────────────────
-- returns true if a witness called the police
local function crime(src, key, coords)
    local c = Config.Crimes[key]
    if not c or not players[src] then return false end
    if isPolice(src) then return false end
    coords = coords or GetEntityCoords(GetPlayerPed(src))
    addHeat(src, c.heat or 0, c.label)
    for cat, xp in pairs(c.rep or {}) do addRep(src, cat, xp) end
    local called = (c.alert or 0) > 0 and math.random(100) <= alertChance(src, c.alert)
    if called then policeAlert(coords, c.label, 'A witness called 911.') end
    return called
end

-- crimes the game detects on the player's PC (rate limited, heat only)
RegisterNetEvent('mars_heat:server:crime', function(key)
    local src = source
    local c = Config.Crimes[key]
    if not c or not c.client then return end
    cooldowns[src] = cooldowns[src] or {}
    local now = os.time()
    if cooldowns[src][key] and now - cooldowns[src][key] < (c.cooldown or 10) then return end
    cooldowns[src][key] = now
    crime(src, key)
end)

-- heat cools down; very hot players get "sighted" for the police
CreateThread(function()
    local sinceSighting = 0
    while true do
        Wait(60000)
        sinceSighting = sinceSighting + 1
        local sight = sinceSighting >= Config.Police.sightingEveryMinutes
        if sight then sinceSighting = 0 end
        for src, d in pairs(players) do
            if d.heat > 0 then setHeat(src, d.heat - Config.DecayPerMinute) end
            if sight and d.heat >= Config.Police.sightingHeat then
                policeAlert(GetEntityCoords(GetPlayerPed(src)), 'Suspect sighted',
                    ('A wanted person (%s) was seen in this area.'):format(Config.TierFor(d.heat).label),
                    Config.Police.sightingRadius)
            end
            save(src)
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- player menu data (/rep)
-- ─────────────────────────────────────────────────────────────
lib.callback.register('mars_heat:server:profile', function(src)
    local d = players[src]
    if not d then load(src); d = players[src] end
    if not d then return nil end
    local rep = {}
    for _, c in ipairs(Config.RepCategories) do
        local info = repInfo(src, c.key)
        info.key, info.name, info.icon = c.key, c.label, c.icon
        rep[#rep + 1] = info
    end
    return { heat = round1(d.heat), rep = rep, police = isPolice(src) == true }
end)

-- ─────────────────────────────────────────────────────────────
-- admin (/heatadmin)
-- ─────────────────────────────────────────────────────────────
lib.addCommand('heatadmin', { help = 'Mars heat & reputation admin', restricted = 'group.admin' }, function(src)
    TriggerClientEvent('mars_heat:client:admin', src)
end)

lib.callback.register('mars_heat:admin:players', function(src)
    if not isAdmin(src) then return {} end
    local list = {}
    for id, d in pairs(players) do
        local p = getPlayer(id)
        local name = p and ('%s %s'):format(p.PlayerData.charinfo.firstname, p.PlayerData.charinfo.lastname) or GetPlayerName(id)
        local rep = {}
        for _, c in ipairs(Config.RepCategories) do rep[#rep + 1] = { key = c.key, name = c.label, xp = d.rep[c.key] or 0 } end
        list[#list + 1] = { id = id, name = name, heat = round1(d.heat), rep = rep }
    end
    table.sort(list, function(a, b) return a.heat > b.heat end)
    return list
end)

lib.callback.register('mars_heat:admin:setHeat', function(src, target, value)
    if not isAdmin(src) then return false, 'No permission.' end
    target, value = tonumber(target), tonumber(value)
    if not players[target] or not value then return false, 'Player not found.' end
    setHeat(target, value, 'admin')
    return true, ('Heat set to %d.'):format(value)
end)

lib.callback.register('mars_heat:admin:setRep', function(src, target, cat, xp)
    if not isAdmin(src) then return false, 'No permission.' end
    target, xp = tonumber(target), tonumber(xp)
    local d = players[target]
    if not d or not xp or d.rep[cat] == nil then return false, 'Player not found.' end
    d.rep[cat] = math.max(0, math.floor(xp)); d.dirty = true
    save(target)
    return true, ('%s reputation set to %d xp (%s).'):format(cat, d.rep[cat], Config.LevelFor(d.rep[cat]).label)
end)

lib.callback.register('mars_heat:admin:setting', function(src, path, value)
    if not isAdmin(src) then return false, 'No permission.' end
    local rule
    for _, e in ipairs(Config.Editable) do if e.path == path then rule = e end end
    value = tonumber(value)
    if not rule or not value then return false, 'This setting cannot be edited.' end
    value = math.min(rule.max, math.max(rule.min, value))
    if defaults[path] == nil then defaults[path] = Config.GetPath(path) end
    Config.SetPath(path, value)
    overrides[path] = value
    MySQL.query('REPLACE INTO mars_heat_settings (path, value) VALUES (?, ?)', { path, json.encode(value) })
    TriggerClientEvent('mars_heat:client:setting', -1, path, value)
    return true, ('Saved: %s = %s'):format(rule.label, value)
end)

lib.callback.register('mars_heat:admin:reset', function(src)
    if not isAdmin(src) then return false, 'No permission.' end
    for path in pairs(overrides) do
        if defaults[path] ~= nil then
            Config.SetPath(path, defaults[path])
            TriggerClientEvent('mars_heat:client:setting', -1, path, defaults[path])
        end
        overrides[path] = nil
    end
    MySQL.query('DELETE FROM mars_heat_settings')
    return true, 'All heat settings are back to default.'
end)

lib.callback.register('mars_heat:server:settings', function() return overrides end)

lib.addCommand('heatkit', { help = 'Mars heat: test – add 25 heat to yourself', restricted = 'group.admin' }, function(src)
    addHeat(src, 25, 'test')
    notify(src, ('Heat is now %d.'):format(players[src] and players[src].heat or 0))
end)

-- ─────────────────────────────────────────────────────────────
-- exports for other scripts
-- ─────────────────────────────────────────────────────────────
exports('Crime', crime)                                   -- Crime(src, 'drug_sale' [, coords]) -> police called?
exports('AddHeat', addHeat)                               -- AddHeat(src, amount, reason)
exports('SetHeat', setHeat)
exports('GetHeat', function(src) return players[src] and players[src].heat or 0 end)
exports('GetTier', function(src) return Config.TierFor(players[src] and players[src].heat or 0) end)
exports('AlertChance', alertChance)                       -- AlertChance(src, basePercent) -> percent
exports('PoliceAlert', policeAlert)                       -- PoliceAlert(coords, title, text, radius)
exports('AddRep', addRep)                                 -- AddRep(src, 'drugs', 10)
exports('GetRep', repInfo)                                -- GetRep(src, 'drugs') -> { xp, level, label, priceMult, acceptBonus }
