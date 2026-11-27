Config = {}

Config.ShopName = 'Mars Pawn & Gold'
Config.Npc = { model = `s_m_m_highsec_01`, coords = vec4(412.34, 314.81, 103.13, 207.0) }
Config.Blip = { sprite = 431, color = 5, scale = 0.8 }
Config.Hours = { open = 0, close = 24 }       -- in-game hours; 0-24 = always open

-- base price range per item (the shop pays somewhere in between)
-- melt: what the smelter turns one unit into
Config.Items = {
    goldchain      = { min = 120, max = 180, category = 'Jewelry', melt = { goldbar = 1 } },
    ['10kgoldchain'] = { min = 200, max = 280, category = 'Jewelry', melt = { goldbar = 2 } },
    diamond_ring   = { min = 300, max = 420, category = 'Jewelry', melt = { diamond = 1, goldbar = 1 } },
    rolex          = { min = 450, max = 650, category = 'Jewelry', melt = { diamond = 1, goldbar = 2 } },
    goldbar        = { min = 900, max = 1200, category = 'Precious' },
    diamond        = { min = 700, max = 950,  category = 'Precious' },
    painting       = { min = 500, max = 900,  category = 'Art' },
    laptop         = { min = 350, max = 500,  category = 'Electronics' },
    tablet         = { min = 200, max = 320,  category = 'Electronics' },
    iphone         = { min = 250, max = 380,  category = 'Electronics' },
    samsungphone   = { min = 200, max = 320,  category = 'Electronics' },
    small_tv       = { min = 150, max = 220,  category = 'Electronics' },
    microwave      = { min = 80,  max = 130,  category = 'Household' },
    toaster        = { min = 40,  max = 70,   category = 'Household' },
}

-- market: every unit sold makes that item cheaper for a while
Config.Market = {
    saturationPerUnit = 0.02,   -- -2% per unit sold
    maxSaturation = 0.5,        -- never below 50% of the base price
    recoveryPerMinute = 0.01,   -- +1% back every minute
    randomSpread = 0.05,        -- ±5% daily mood
}

-- hot items: picked every few hours, pay extra
Config.Hot = { count = 3, multiplier = 1.5, rotateMinutes = 120 }

-- haggling: ask for more; refusal makes the owner annoyed for a while
Config.Haggle = {
    { bonus = 0.10, chance = 75, label = '+10%' },
    { bonus = 0.20, chance = 50, label = '+20%' },
    { bonus = 0.35, chance = 25, label = '+35%' },
    annoyedPenalty = 0.10,      -- -10% offers on that item while annoyed
    annoyedMinutes = 3,
    repChanceBonus = 3,         -- +3% chance per reputation level
}

-- reputation: earned from sales value, better prices per level
Config.Reputation = {
    levels = {
        { xp = 0,     label = 'Stranger', bonus = 0.00 },
        { xp = 2000,  label = 'Regular',  bonus = 0.04 },
        { xp = 8000,  label = 'Trusted',  bonus = 0.08 },
        { xp = 20000, label = 'Partner',  bonus = 0.13 },
        { xp = 50000, label = 'Family',   bonus = 0.20 },
    },
}

-- buy-back: what players sell goes into stock, others can buy it
Config.BuyBack = { markup = 1.4, maxStock = 25 }

-- black market: hidden tab, unlocked at this reputation level
Config.BlackMarket = {
    minLevel = 4,
    items = {
        { name = 'lockpick',         price = 250 },
        { name = 'advancedlockpick', price = 900 },
        { name = 'electronickit',    price = 1500 },
        { name = 'trojan_usb',       price = 2500 },
        { name = 'drill',            price = 4000 },
        { name = 'thermite',         price = 6000 },
        { name = 'security_card_01', price = 8000 },
    },
}

Config.HistorySize = 20

-- smelter: melt jewelry into gold bars and diamonds
Config.Smelter = { secondsPerUnit = 30, maxJobs = 3 }

-- big sales can make someone call the police
Config.Police = { minValue = 4000, chance = 15, jobType = 'leo' }

-- editable in /pawnadmin
Config.Editable = {
    { path = 'Hot.multiplier',              label = 'Hot item multiplier',      min = 1,   max = 5 },
    { path = 'Market.saturationPerUnit',    label = 'Price drop per unit sold', min = 0,   max = 0.2 },
    { path = 'Market.recoveryPerMinute',    label = 'Price recovery per minute', min = 0,  max = 0.2 },
    { path = 'BuyBack.markup',              label = 'Buy-back markup',          min = 1,   max = 5 },
    { path = 'Smelter.secondsPerUnit',      label = 'Smelt time per unit (s)',  min = 1,   max = 3600 },
    { path = 'Police.chance',               label = 'Police tip-off chance %',  min = 0,   max = 100 },
    { path = 'Police.minValue',             label = 'Police tip-off min. sale $', min = 0, max = 1000000 },
}

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
