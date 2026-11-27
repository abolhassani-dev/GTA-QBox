Config = {}

-- ─────────────────────────────────────────────────────────────
-- HEAT: 0-100. Crimes raise it, it cools down over time.
-- High heat = police get tipped off about you more often.
-- ─────────────────────────────────────────────────────────────
Config.MaxHeat = 100
Config.DecayPerMinute = 1.5          -- heat lost per minute while online
Config.OfflineDecayPerMinute = 0.5   -- heat lost per minute while offline

Config.Tiers = {                     -- from low to high
    { min = 0,  label = 'Clean',       color = '#4ade80' },
    { min = 20, label = 'Noticed',     color = '#facc15' },
    { min = 40, label = 'Hot',         color = '#fb923c' },
    { min = 60, label = 'Wanted',      color = '#f87171' },
    { min = 80, label = 'Most Wanted', color = '#e11d48' },
}

-- every police alert chance in Mars scripts gets + (heat x this) percent
Config.AlertBonusPerHeat = 0.4

-- crimes: heat added, reputation xp, chance (%) a witness calls the police
-- client = true -> detected by the game itself (shooting, killing, carjacking)
Config.Crimes = {
    drug_sale    = { label = 'Drug deal',            heat = 3,  alert = 0,  rep = { drugs = 6, street = 1 } },
    drug_snitch  = { label = 'Drug deal reported',   heat = 8,  alert = 0 },
    fence        = { label = 'Selling stolen goods', heat = 2,  alert = 0,  rep = { street = 2 } },
    shooting     = { label = 'Shots fired',          heat = 4,  alert = 35, client = true, cooldown = 15 },
    npc_kill     = { label = 'Murder',               heat = 15, alert = 60, client = true, cooldown = 5 },
    carjack      = { label = 'Carjacking',           heat = 10, alert = 45, client = true, cooldown = 20 },
}

-- weapons that never count as shooting
Config.IgnoreWeapons = {
    `WEAPON_STUNGUN`, `WEAPON_FIREEXTINGUISHER`, `WEAPON_PETROLCAN`, `WEAPON_SNOWBALL`,
    `WEAPON_FLARE`, `WEAPON_BALL`, `WEAPON_HAZARDCAN`,
}

-- ─────────────────────────────────────────────────────────────
-- POLICE
-- ─────────────────────────────────────────────────────────────
Config.Police = {
    jobType = 'leo',             -- police never gain heat, and receive the alerts
    sightingHeat = 60,           -- from this heat, police get "suspect sighted" areas
    sightingEveryMinutes = 3,
    sightingRadius = 150.0,      -- the circle on the police map (not the exact spot)
    alertRadius = 90.0,
    blipSeconds = 60,
}

-- ─────────────────────────────────────────────────────────────
-- REPUTATION: earned by crimes, never decays. Higher level = perks.
-- priceMult: sale price multiplier   acceptBonus: + % that customers say yes
-- ─────────────────────────────────────────────────────────────
Config.RepCategories = {
    { key = 'street', label = 'Street',  icon = 'fa-solid fa-mask' },
    { key = 'drugs',  label = 'Drugs',   icon = 'fa-solid fa-cannabis' },
}

Config.RepLevels = {
    { xp = 0,    label = 'Nobody',   priceMult = 1.00, acceptBonus = 0 },
    { xp = 100,  label = 'Hustler',  priceMult = 1.05, acceptBonus = 3 },
    { xp = 300,  label = 'Dealer',   priceMult = 1.12, acceptBonus = 6 },
    { xp = 700,  label = 'Supplier', priceMult = 1.20, acceptBonus = 9 },
    { xp = 1500, label = 'Kingpin',  priceMult = 1.30, acceptBonus = 12 },
}

-- ─────────────────────────────────────────────────────────────
-- settings editable in game with /heatadmin
-- ─────────────────────────────────────────────────────────────
Config.Editable = {
    { path = 'DecayPerMinute',              label = 'Heat cool-down per minute',      min = 0,   max = 20 },
    { path = 'OfflineDecayPerMinute',       label = 'Heat cool-down offline / min',   min = 0,   max = 20 },
    { path = 'AlertBonusPerHeat',           label = 'Extra alert % per heat point',   min = 0,   max = 2 },
    { path = 'Police.sightingHeat',         label = 'Heat for police sightings',      min = 1,   max = 100 },
    { path = 'Police.sightingEveryMinutes', label = 'Minutes between sightings',      min = 1,   max = 30 },
}
for key, c in pairs(Config.Crimes) do
    Config.Editable[#Config.Editable + 1] = { path = ('Crimes.%s.heat'):format(key), label = ('Heat: %s'):format(c.label), min = 0, max = 100 }
    if c.client then
        Config.Editable[#Config.Editable + 1] = { path = ('Crimes.%s.alert'):format(key), label = ('Police call %%: %s'):format(c.label), min = 0, max = 100 }
    end
end
table.sort(Config.Editable, function(a, b) return a.label < b.label end)

-- ─────────────────────────────────────────────────────────────
-- helpers (shared)
-- ─────────────────────────────────────────────────────────────
function Config.TierFor(heat)
    local tier, index = Config.Tiers[1], 1
    for i, t in ipairs(Config.Tiers) do if heat >= t.min then tier, index = t, i end end
    return tier, index
end

function Config.LevelFor(xp)
    local level, index = Config.RepLevels[1], 1
    for i, l in ipairs(Config.RepLevels) do if xp >= l.xp then level, index = l, i end end
    return level, index, Config.RepLevels[index + 1]
end

function Config.SetPath(path, value)
    local node, keys = Config, {}
    for k in path:gmatch('[^%.]+') do keys[#keys + 1] = k end
    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if type(node) ~= 'table' then return false end
    end
    node[keys[#keys]] = value
    return true
end

function Config.GetPath(path)
    local node = Config
    for k in path:gmatch('[^%.]+') do
        if type(node) ~= 'table' then return nil end
        node = node[k]
    end
    return node
end
