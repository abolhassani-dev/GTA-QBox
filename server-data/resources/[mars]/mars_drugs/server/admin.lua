-- /drugadmin: edit Mars drugs settings in game. Changes are saved in the
-- mars_drugs_settings table and pushed live to the server and all clients.

local function isAdmin(src)
    return IsPlayerAceAllowed(src, 'admin')
end

-- which paths may be edited, and their limits
local function ruleFor(path)
    for _, e in ipairs(Config.Editable) do
        if e.path == path then return { type = 'number', min = e.min, max = e.max } end
    end
    local strain, field = path:match('^Strains%.([%w_]+)%.([%w_]+)$')
    if strain and Config.Strains[strain] then
        if field == 'enabled' then return { type = 'boolean' } end
        for _, f in ipairs(Config.EditableStrainFields) do
            if f.key == field then return { type = 'number', min = f.min, max = f.max } end
        end
    end
    local effect, efield = path:match('^Effects%.([%w_]+)%.([%w_]+)$')
    if effect and Config.Effects[effect] then
        for _, f in ipairs(Config.EditableEffectFields) do
            if f.key == efield then return { type = 'number', min = f.min, max = f.max } end
        end
    end
end

local function affectsShop(path)
    return path:match('%.seedPrice$') or path:match('%.enabled$')
end

local function setSetting(path, value)
    MarsDrugs.applyOverride(path, value)
    MySQL.query('REPLACE INTO mars_drugs_settings (path, value) VALUES (?, ?)', { path, json.encode(value) })
    TriggerClientEvent('mars_drugs:client:setting', -1, path, value)
    if affectsShop(path) then CreateThread(MarsDrugs.registerShop) end
end

lib.callback.register('mars_drugs:admin:set', function(src, path, value)
    if not isAdmin(src) then return false, 'No permission.' end
    if type(path) ~= 'string' then return false, 'Invalid setting.' end
    local rule = ruleFor(path)
    if not rule then return false, 'This setting cannot be edited.' end

    if rule.type == 'boolean' then
        value = value == true
    else
        value = tonumber(value)
        if not value then return false, 'Enter a number.' end
        value = math.min(rule.max, math.max(rule.min, value))
        if path == 'Yield.min' and value > Config.Yield.max then return false, 'Minimum cannot be above maximum.' end
        if path == 'Yield.max' and value < Config.Yield.min then return false, 'Maximum cannot be below minimum.' end
    end

    setSetting(path, value)
    print(('[mars_drugs] %s changed %s = %s'):format(GetPlayerName(src), path, tostring(value)))
    return true, ('Saved: %s = %s'):format(path, tostring(value))
end)

lib.callback.register('mars_drugs:admin:reset', function(src)
    if not isAdmin(src) then return false, 'No permission.' end
    for path in pairs(MarsDrugs.overrides) do
        local default = MarsDrugs.defaults[path]
        if default ~= nil then
            Config.SetPath(path, default)
            TriggerClientEvent('mars_drugs:client:setting', -1, path, default)
        end
        MarsDrugs.overrides[path] = nil
    end
    MySQL.query('DELETE FROM mars_drugs_settings')
    CreateThread(MarsDrugs.registerShop)
    return true, 'All settings reset to config.lua.'
end)

lib.addCommand('drugadmin', { help = 'Mars drugs: settings panel', restricted = 'group.admin' }, function(src)
    TriggerClientEvent('mars_drugs:client:openAdmin', src)
end)
