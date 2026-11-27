-- /drugadmin – in-game settings panel (admins only; the server checks again)

local openMain

local function fmt(v)
    if type(v) == 'number' then
        return (v == math.floor(v)) and tostring(math.floor(v)) or ('%.2f'):format(v)
    end
    return tostring(v)
end

local function edit(path, label, min, max, back)
    local current = Config.GetPath(path)
    local input = lib.inputDialog(label, {
        { type = 'number', label = ('%s (%s – %s)'):format(label, fmt(min), fmt(max)), default = current, min = min, max = max, step = 0.01, required = true },
    })
    if input then
        local ok, msg = lib.callback.await('mars_drugs:admin:set', false, path, input[1])
        lib.notify({ title = 'Drug admin', description = msg, type = ok and 'success' or 'error' })
    end
    if back then back() end
end

local function openStrain(key)
    local s = Config.Strains[key]
    local options = {
        { title = s.enabled == false and '❌ Disabled (click to enable)' or '✅ Enabled (click to disable)',
          onSelect = function()
              local ok, msg = lib.callback.await('mars_drugs:admin:set', false, ('Strains.%s.enabled'):format(key), s.enabled == false)
              lib.notify({ title = 'Drug admin', description = msg, type = ok and 'success' or 'error' })
              openStrain(key)
          end },
    }
    for _, f in ipairs(Config.EditableStrainFields) do
        options[#options + 1] = {
            title = ('%s: %s'):format(f.label, fmt(s[f.key])),
            onSelect = function() edit(('Strains.%s.%s'):format(key, f.key), f.label, f.min, f.max, function() openStrain(key) end) end,
        }
    end
    lib.registerContext({ id = 'mars_drugadmin_strain', title = s.label, menu = 'mars_drugadmin_strains', options = options })
    lib.showContext('mars_drugadmin_strain')
end

local function openStrains()
    local options = {}
    for _, key in ipairs(Config.StrainOrder) do
        local s = Config.Strains[key]
        if s then
            options[#options + 1] = {
                title = ('%s%s'):format(s.enabled == false and '❌ ' or '', s.label),
                description = ('%s • seed $%s • sell $%s • growth x%s'):format(s.type, fmt(s.seedPrice), fmt(s.basePrice), fmt(s.growthMult)),
                arrow = true,
                onSelect = function() openStrain(key) end,
            }
        end
    end
    lib.registerContext({ id = 'mars_drugadmin_strains', title = 'Strains', menu = 'mars_drugadmin', options = options })
    lib.showContext('mars_drugadmin_strains')
end

local function openEffect(key)
    local e = Config.Effects[key]
    local options = {}
    for _, f in ipairs(Config.EditableEffectFields) do
        options[#options + 1] = {
            title = ('%s: %s'):format(f.label, fmt(e[f.key] or 0)),
            onSelect = function() edit(('Effects.%s.%s'):format(key, f.key), f.label, f.min, f.max, function() openEffect(key) end) end,
        }
    end
    lib.registerContext({ id = 'mars_drugadmin_effect', title = ('Effect: %s'):format(e.label), menu = 'mars_drugadmin_effects', options = options })
    lib.showContext('mars_drugadmin_effect')
end

local function openEffects()
    local options = {}
    for key, e in pairs(Config.Effects) do
        options[#options + 1] = {
            title = e.label, description = ('%s • %ss • x%s'):format(key, fmt(e.duration), fmt(e.intensity or 1)),
            arrow = true, onSelect = function() openEffect(key) end,
        }
    end
    lib.registerContext({ id = 'mars_drugadmin_effects', title = 'Effects', menu = 'mars_drugadmin', options = options })
    lib.showContext('mars_drugadmin_effects')
end

openMain = function()
    local options = {}
    for _, e in ipairs(Config.Editable) do
        options[#options + 1] = {
            title = ('%s: %s'):format(e.label, fmt(Config.GetPath(e.path))),
            icon = 'fa-solid fa-sliders',
            onSelect = function() edit(e.path, e.label, e.min, e.max, openMain) end,
        }
    end
    options[#options + 1] = { title = 'Strains ▸', description = 'Prices, growth speed, harvest size, enable/disable', icon = 'fa-solid fa-seedling', arrow = true, onSelect = openStrains }
    options[#options + 1] = { title = 'Effects ▸', description = 'Duration, intensity, stress relief, armor, run speed', icon = 'fa-solid fa-wand-magic-sparkles', arrow = true, onSelect = openEffects }
    options[#options + 1] = {
        title = 'Reset everything to defaults', icon = 'fa-solid fa-rotate-left',
        onSelect = function()
            if lib.alertDialog({ header = 'Reset', content = 'Reset all drug settings to config.lua?', centered = true, cancel = true }) ~= 'confirm' then return end
            local ok, msg = lib.callback.await('mars_drugs:admin:reset', false)
            lib.notify({ title = 'Drug admin', description = msg, type = ok and 'success' or 'error' })
        end,
    }
    lib.registerContext({ id = 'mars_drugadmin', title = 'Mars Drugs – Settings', options = options })
    lib.showContext('mars_drugadmin')
end

RegisterNetEvent('mars_drugs:client:openAdmin', openMain)
