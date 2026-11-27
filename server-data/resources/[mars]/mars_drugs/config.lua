Config = {}

-- ─────────────────────────────────────────────────────────────
--  Mars Drugs v2 – weed, magic mushrooms, coca / cocaine
--  Most numbers here can also be changed in game with /drugadmin
--  (changes are saved in the database and override this file).
-- ─────────────────────────────────────────────────────────────

Config.Debug = false

-- ── Planting ──
Config.MaxPlantsPerPlayer = 8
Config.PlantSpacing = 1.2
Config.PlantAnimMs = 5000

-- ── Growing ──
Config.TickSeconds = 10              -- server update interval
Config.GrowthMinutes = 2             -- minutes to 100% for a strain with growthMult 1.0
Config.WaterDecayPerMinute = 18      -- water lost per minute (x strain thirst)
Config.FoodDecayPerMinute = 12       -- fertilizer lost per minute
Config.HealthLossPerMinute = 40      -- while dry or hungry
Config.HealthGainPerMinute = 10      -- while cared for
Config.WaterPerUse = 45
Config.FoodPerUse = 55
Config.AllowHarvestByOthers = true
Config.PoliceJobType = 'leo'

Config.Yield = { min = 3, max = 10 } -- base harvest, x strain yieldMult, scaled by quality

-- ── Plant categories: what a plant turns into and how it is processed ──
Config.Categories = {
    weed = {
        label = 'Cannabis',
        harvest = 'mars_weed_wet',        -- item from the plant
        dried = 'mars_weed_dry',          -- after the drying rack (nil = no drying step)
        product = 'mars_weed_bag',        -- packed for sale
        perProduct = 2,                   -- harvested/dried units per packed product
        container = 'empty_weed_bag',
        extra = nil,                      -- extra item needed per product
        consumable = 'mars_joint',        -- item that is used (smoked)
        props = { `bkr_prop_weed_01_small_01b`, `bkr_prop_weed_med_01b`, `bkr_prop_weed_lrg_01b` },
        priceMult = 1.0,
    },
    shroom = {
        label = 'Magic Mushrooms',
        harvest = 'mars_shroom_fresh',
        dried = 'mars_shroom_dry',
        product = 'mars_shroom_bag',
        perProduct = 3,
        container = 'empty_weed_bag',
        extra = nil,
        consumable = 'mars_shroom_bag',
        props = { `prop_stoneshroom1`, `prop_stoneshroom1`, `prop_stoneshroom2` },
        priceMult = 1.4,
    },
    coca = {
        label = 'Coca',
        harvest = 'mars_coca_leaf',
        dried = nil,
        product = 'mars_cocaine_bag',
        perProduct = 4,
        container = 'empty_weed_bag',
        extra = { item = 'mars_chemicals', count = 1 },
        consumable = 'mars_cocaine_bag',
        props = { `prop_plant_fern_02a`, `prop_plant_fern_02a`, `prop_plant_fern_01a` },
        priceMult = 2.2,
    },
}

-- fallback props if a model is missing from the game files
Config.FallbackProps = { `bkr_prop_weed_01_small_01b`, `bkr_prop_weed_med_01b`, `bkr_prop_weed_lrg_01b` }

-- ── Strains ──
-- type:       indica (calm, bigger harvest) / sativa (energetic, faster) / hybrid
-- growthMult: >1 grows faster      yieldMult: >1 bigger harvest
-- thirst:     >1 needs more water  effect: key in Config.Effects
Config.Strains = {
    -- cannabis
    og_kush         = { category = 'weed', label = 'OG Kush',         type = 'hybrid', seedPrice = 120, basePrice = 95,  growthMult = 1.0,  yieldMult = 1.0,  thirst = 1.0, effect = 'weed_hybrid', enabled = true },
    northern_lights = { category = 'weed', label = 'Northern Lights', type = 'indica', seedPrice = 140, basePrice = 105, growthMult = 0.85, yieldMult = 1.3,  thirst = 0.9, effect = 'weed_indica', enabled = true },
    purple_haze     = { category = 'weed', label = 'Purple Haze',     type = 'sativa', seedPrice = 160, basePrice = 120, growthMult = 1.2,  yieldMult = 0.85, thirst = 1.2, effect = 'weed_sativa', enabled = true },
    amnesia         = { category = 'weed', label = 'Amnesia Haze',    type = 'sativa', seedPrice = 200, basePrice = 150, growthMult = 1.1,  yieldMult = 0.9,  thirst = 1.3, effect = 'weed_sativa', enabled = true },
    white_widow     = { category = 'weed', label = 'White Widow',     type = 'hybrid', seedPrice = 170, basePrice = 130, growthMult = 1.0,  yieldMult = 1.1,  thirst = 1.0, effect = 'weed_hybrid', enabled = true },
    blue_dream      = { category = 'weed', label = 'Blue Dream',      type = 'hybrid', seedPrice = 190, basePrice = 140, growthMult = 0.95, yieldMult = 1.15, thirst = 1.1, effect = 'weed_hybrid', enabled = true },
    gelato          = { category = 'weed', label = 'Gelato',          type = 'indica', seedPrice = 240, basePrice = 175, growthMult = 0.8,  yieldMult = 1.2,  thirst = 1.0, effect = 'weed_indica', enabled = true },
    sour_diesel     = { category = 'weed', label = 'Sour Diesel',     type = 'sativa', seedPrice = 210, basePrice = 160, growthMult = 1.25, yieldMult = 0.8,  thirst = 1.4, effect = 'weed_sativa', enabled = true },
    -- mushrooms
    liberty_cap     = { category = 'shroom', label = 'Liberty Cap',    type = 'psilocybin', seedPrice = 220, basePrice = 160, growthMult = 0.9,  yieldMult = 1.0, thirst = 1.5, effect = 'shroom_mild',   enabled = true },
    golden_teacher  = { category = 'shroom', label = 'Golden Teacher', type = 'psilocybin', seedPrice = 300, basePrice = 230, growthMult = 0.75, yieldMult = 0.9, thirst = 1.6, effect = 'shroom_strong', enabled = true },
    -- coca
    bolivian_coca   = { category = 'coca', label = 'Bolivian Coca',  type = 'stimulant', seedPrice = 350, basePrice = 260, growthMult = 0.7, yieldMult = 1.0, thirst = 1.2, effect = 'cocaine', enabled = true },
    colombian_coca  = { category = 'coca', label = 'Colombian Coca', type = 'stimulant', seedPrice = 450, basePrice = 330, growthMult = 0.6, yieldMult = 1.1, thirst = 1.3, effect = 'cocaine', enabled = true },
}

-- display order in menus and in the shop
Config.StrainOrder = {
    'og_kush', 'northern_lights', 'purple_haze', 'amnesia', 'white_widow', 'blue_dream', 'gelato', 'sour_diesel',
    'liberty_cap', 'golden_teacher', 'bolivian_coca', 'colombian_coca',
}

-- ── Quality tiers (best first) ──
Config.Qualities = {
    { key = 'exotic', label = 'Exotic', min = 90, priceMult = 2.2, effectMult = 1.35 },
    { key = 'high',   label = 'High',   min = 70, priceMult = 1.5, effectMult = 1.15 },
    { key = 'medium', label = 'Medium', min = 40, priceMult = 1.0, effectMult = 1.0 },
    { key = 'low',    label = 'Low',    min = 0,  priceMult = 0.6, effectMult = 0.7 },
}

-- ── Effects when consuming ──
-- duration in seconds (x quality effectMult). All visual names are base-game.
Config.Effects = {
    weed_indica = {
        label = 'Relaxed', duration = 90, intensity = 1.0,
        postfx = 'DrugsMichaelAliensFightIn', timecycle = 'spectator5', timecycleStrength = 0.45,
        shake = 'DRUNK_SHAKE', shakeAmp = 0.35, walk = 'move_m@drunk@slightlydrunk',
        stress = 35, armor = 10, health = 10, runSpeed = 1.0, hunger = 0,
        cough = true,
    },
    weed_sativa = {
        label = 'Uplifted', duration = 75, intensity = 1.0,
        postfx = 'DrugsDrivingIn', timecycle = 'drug_drive_blend01', timecycleStrength = 0.35,
        shake = 'HAND_SHAKE', shakeAmp = 0.25, walk = 'move_m@hipster@a',
        stress = 25, armor = 0, health = 0, runSpeed = 1.08,
        cough = true,
    },
    weed_hybrid = {
        label = 'Balanced high', duration = 80, intensity = 1.0,
        postfx = 'DrugsMichaelAliensFightIn', timecycle = 'drug_flying_base', timecycleStrength = 0.3,
        shake = 'DRUNK_SHAKE', shakeAmp = 0.25, walk = 'move_m@drunk@slightlydrunk',
        stress = 30, armor = 5, health = 5, runSpeed = 1.03,
        cough = true,
    },
    shroom_mild = {
        label = 'Tripping', duration = 120, intensity = 1.0,
        postfx = 'DrugsTrevorClownsFight', timecycle = 'drug_wobbly', timecycleStrength = 0.6,
        shake = 'FAMILY5_DRUG_TRIP_SHAKE', shakeAmp = 0.5, walk = 'move_m@drunk@moderatedrunk',
        stress = 20, armor = 0, health = 0, runSpeed = 0.95,
        hallucinate = true,
    },
    shroom_strong = {
        label = 'Heavy trip', duration = 160, intensity = 1.2,
        postfx = 'DrugsTrevorClownsFight', timecycle = 'drug_wobbly', timecycleStrength = 0.9,
        shake = 'FAMILY5_DRUG_TRIP_SHAKE', shakeAmp = 0.9, walk = 'move_m@drunk@verydrunk',
        stress = 15, armor = 0, health = 0, runSpeed = 0.9,
        hallucinate = true,
    },
    cocaine = {
        label = 'Rush', duration = 60, intensity = 1.0,
        postfx = 'DrugsDrivingIn', timecycle = 'drug_drive_blend01', timecycleStrength = 0.25,
        shake = 'HAND_SHAKE', shakeAmp = 0.6, walk = 'move_m@quick',
        stress = 10, armor = 20, health = 0, runSpeed = 1.25,
        stamina = true,
    },
}

-- taking too much in a short time
Config.Overdose = {
    windowSeconds = 300,   -- doses counted in this window
    threshold = 4,         -- more doses than this -> overdose
    damage = 60,
}

-- ── Processing ──
Config.Processing = {
    dryMsPerItem = 1200,
    packMsPerItem = 1800,
    rollMsPerItem = 1500,
    jointsPerBud = 2,      -- 1 dry bud + 1 rolling paper = 2 joints
    maxMs = 45000,
}

Config.Lab = {
    rack  = vec4(2224.30, 5577.10, 53.85, 90.0),
    table = vec4(2222.40, 5574.60, 53.80, 90.0),
    blip  = false,
}

Config.Shop = {
    ped    = `a_m_y_hippy_01`,
    coords = vec4(-1171.42, -1571.00, 4.66, 124.0),
    blip   = { sprite = 140, color = 25, label = 'Garden Supplies' },
    extra  = {
        { name = 'water',          price = 10 },
        { name = 'weed_nutrition', price = 60 },
        { name = 'empty_weed_bag', price = 5 },
        { name = 'rolling_paper',  price = 3 },
        { name = 'mars_chemicals', price = 120 },
    },
}

Config.Selling = {
    acceptChance = 70,
    policeAlertChance = 25,
    maxPerDeal = 3,
    cooldownSeconds = 8,
    animMs = 4000,
    jointPriceMult = 0.35, -- a joint sells for this share of a bag
}

Config.Props = {
    rack  = `bkr_prop_weed_drying_02a`,
    table = `bkr_prop_weed_table_01a`,
    rackFallback  = `prop_rub_table_02`,
    tableFallback = `prop_table_03`,
}

Config.SpawnDistance = 60.0

-- ─────────────────────────────────────────────────────────────
-- In-game editable settings (/drugadmin). Each entry: path in Config,
-- label, min, max. Strain and effect fields are added automatically.
-- ─────────────────────────────────────────────────────────────
Config.Editable = {
    { path = 'GrowthMinutes',             label = 'Growth time (minutes)',          min = 0.5, max = 240 },
    { path = 'MaxPlantsPerPlayer',        label = 'Max plants per player',          min = 1,   max = 100 },
    { path = 'WaterDecayPerMinute',       label = 'Water loss per minute',          min = 0,   max = 100 },
    { path = 'FoodDecayPerMinute',        label = 'Fertilizer loss per minute',     min = 0,   max = 100 },
    { path = 'Yield.min',                 label = 'Harvest minimum',                min = 1,   max = 100 },
    { path = 'Yield.max',                 label = 'Harvest maximum',                min = 1,   max = 200 },
    { path = 'Selling.acceptChance',      label = 'NPC buy chance (%)',             min = 0,   max = 100 },
    { path = 'Selling.policeAlertChance', label = 'Police alert chance (%)',        min = 0,   max = 100 },
    { path = 'Selling.maxPerDeal',        label = 'Max items per deal',             min = 1,   max = 20 },
    { path = 'Overdose.threshold',        label = 'Overdose after this many doses', min = 1,   max = 20 },
}
Config.EditableStrainFields = {
    { key = 'seedPrice',  label = 'Seed price',            min = 0,    max = 100000 },
    { key = 'basePrice',  label = 'Base sell price',       min = 0,    max = 100000 },
    { key = 'growthMult', label = 'Growth speed (x)',      min = 0.1,  max = 10 },
    { key = 'yieldMult',  label = 'Harvest size (x)',      min = 0.1,  max = 10 },
    { key = 'thirst',     label = 'Water need (x)',        min = 0.1,  max = 5 },
}
Config.EditableEffectFields = {
    { key = 'duration',  label = 'Duration (seconds)', min = 5,   max = 1800 },
    { key = 'intensity', label = 'Intensity (x)',      min = 0.1, max = 3 },
    { key = 'stress',    label = 'Stress relief',      min = 0,   max = 100 },
    { key = 'armor',     label = 'Armor given',        min = 0,   max = 100 },
    { key = 'runSpeed',  label = 'Run speed (x)',      min = 0.5, max = 1.49 },
}

-- ── Helpers shared by client and server ──

function Config.QualityFor(score)
    for _, q in ipairs(Config.Qualities) do
        if score >= q.min then return q end
    end
    return Config.Qualities[#Config.Qualities]
end

function Config.QualityByKey(key)
    for _, q in ipairs(Config.Qualities) do
        if q.key == key then return q end
    end
end

function Config.CategoryOf(strain)
    local s = Config.Strains[strain]
    return s and Config.Categories[s.category], s and s.category
end

function Config.SeedMeta(strain)
    local s = Config.Strains[strain]
    return {
        strain = strain,
        label = ('%s Seed'):format(s.label),
        description = ('%s • %s'):format(Config.Categories[s.category].label, s.type),
    }
end

function Config.ProductMeta(strain, quality)
    local s = Config.Strains[strain]
    local q = Config.QualityByKey(quality)
    return {
        strain = strain,
        quality = quality,
        description = ('%s • %s quality'):format(s and s.label or strain, q and q.label or quality),
    }
end

-- settings paths like 'Selling.acceptChance' or 'Strains.og_kush.seedPrice'
function Config.SetPath(path, value)
    local node = Config
    local keys = {}
    for k in path:gmatch('[^%.]+') do keys[#keys + 1] = k end
    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if type(node) ~= 'table' then return false end
    end
    -- positions saved in the database come back as plain {x,y,z,w} tables
    if type(value) == 'table' and value.x and value.y and value.z then
        value = value.w and vec4(value.x, value.y, value.z, value.w) or vec3(value.x, value.y, value.z)
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
