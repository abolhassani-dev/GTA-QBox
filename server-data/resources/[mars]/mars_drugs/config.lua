Config = {}

-- ─────────────────────────────────────────────────────────────
--  Mars Drugs – phase 1 (weed)
--  All times are in real-life minutes/seconds. Lower them for testing.
-- ─────────────────────────────────────────────────────────────

Config.Debug = false

-- ── Planting ──
Config.MaxPlantsPerPlayer = 6      -- living plants a single character may own
Config.PlantSpacing = 1.5          -- minimum metres between two plants
Config.PlantAnimMs = 6000          -- planting animation length

-- ── Growing ──
Config.TickSeconds = 60            -- how often plants update
Config.GrowthMinutes = 30          -- minutes to reach 100% with perfect care
Config.WaterDecay = 4              -- water lost per tick (0-100 scale)
Config.FoodDecay = 3               -- fertilizer lost per tick
Config.WaterPerUse = 40            -- one water bottle adds this much
Config.FoodPerUse = 50             -- one fertilizer adds this much
Config.HealthLossPerTick = 10      -- health lost per tick while thirsty or hungry
Config.HealthGainPerTick = 2       -- health regained per tick while cared for
Config.AllowHarvestByOthers = true -- anyone may harvest (steal) a fully grown plant
Config.PoliceJobType = 'leo'       -- qbx job type that may destroy any plant

-- Harvest yield (wet buds) scales with the final quality score
Config.Yield = { min = 4, max = 12 }

-- ── Strains (sold as seeds in the shop) ──
Config.Strains = {
    og_kush         = { label = 'OG Kush',         seedPrice = 120, basePrice = 100 },
    northern_lights = { label = 'Northern Lights', seedPrice = 150, basePrice = 120 },
    purple_haze     = { label = 'Purple Haze',     seedPrice = 180, basePrice = 140 },
    amnesia         = { label = 'Amnesia Haze',    seedPrice = 220, basePrice = 170 },
}

-- ── Quality tiers (score = average care during the whole growth) ──
-- Ordered from best to worst; the first tier whose `min` is reached is used.
Config.Qualities = {
    { key = 'exotic', label = 'Exotic', min = 90, priceMult = 2.2 },
    { key = 'high',   label = 'High',    min = 70, priceMult = 1.5 },
    { key = 'medium', label = 'Medium',   min = 40, priceMult = 1.0 },
    { key = 'low',    label = 'Low',    min = 0,  priceMult = 0.6 },
}

-- ── Processing (drying rack + packing table) ──
Config.Processing = {
    dryMsPerItem = 1500,   -- drying time per wet bud (progress bar, capped below)
    packMsPerItem = 2000,  -- packing time per bag
    maxMs = 60000,         -- longest progress bar
    budsPerBag = 2,        -- dry buds needed for one bag (+ 1 empty bag)
}

-- Secret lab: drying rack and packing table spawn here (Grapeseed farmland).
-- Move them with /vec4 from the admin tools and paste the result here.
Config.Lab = {
    rack  = vec4(2224.30, 5577.10, 53.85, 90.0),
    table = vec4(2222.40, 5574.60, 53.80, 90.0),
    blip  = false,          -- secret by default
}

-- ── Seed shop (NPC) ──
Config.Shop = {
    ped    = `a_m_y_hippy_01`,
    coords = vec4(-1171.42, -1571.00, 4.66, 124.0), -- Vespucci beach, "Smoke on the Water"
    blip   = { sprite = 140, color = 25, label = 'Garden Supplies' },
    extra  = {
        { name = 'water',          price = 10 },
        { name = 'weed_nutrition', price = 60 },
        { name = 'empty_weed_bag', price = 5 },
    },
}

-- ── Selling to NPCs ──
Config.Selling = {
    acceptChance = 70,        -- % chance a ped buys
    policeAlertChance = 25,   -- % chance a refused deal alerts the police
    maxPerDeal = 3,           -- bags sold in one deal (random 1..max)
    cooldownSeconds = 8,      -- per player, between deals
    animMs = 4000,
}

-- ── Props (base-game Bikers DLC models, no streaming needed) ──
Config.Props = {
    small  = `bkr_prop_weed_01_small_01b`,
    medium = `bkr_prop_weed_med_01b`,
    large  = `bkr_prop_weed_lrg_01b`,
    rack   = `bkr_prop_weed_drying_01a`,
    table  = `bkr_prop_weed_table_01a`,
    rackFallback  = `prop_rub_table_02`,
    tableFallback = `prop_table_03`,
}

Config.SpawnDistance = 60.0   -- plants/props spawn when the player is this close

-- ── Helpers shared by client and server ──

---@param score number 0-100
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

-- Metadata is built the same way everywhere so ox_inventory stacks and
-- matches items exactly (strain + quality).
function Config.SeedMeta(strain)
    return { strain = strain, description = ('Strain: %s'):format(Config.Strains[strain].label) }
end

function Config.ProductMeta(strain, quality)
    local q = Config.QualityByKey(quality)
    return {
        strain = strain,
        quality = quality,
        description = ('Strain: %s | Quality: %s'):format(Config.Strains[strain].label, q and q.label or quality),
    }
end
