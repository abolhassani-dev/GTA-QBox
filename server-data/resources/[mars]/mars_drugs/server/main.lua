local plants = {}          -- [id] = plant
local sellCooldown = {}

-- ─────────────────────────────────────────────────────────────
-- helpers
-- ─────────────────────────────────────────────────────────────

local function notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Mars', description = msg, type = kind or 'inform' })
end

local function getPlayer(src) return exports.qbx_core:GetPlayer(src) end

local function citizenId(src)
    local player = getPlayer(src)
    return player and player.PlayerData.citizenid
end

local function isPolice(src)
    local player = getPlayer(src)
    local job = player and player.PlayerData.job
    return job and job.type == Config.PoliceJobType and job.onduty
end

local function playerCoords(src) return GetEntityCoords(GetPlayerPed(src)) end

-- horizontal distance only: the lab props and plants are placed on the real
-- ground, which can be a few metres above/below the height in config.lua
local function near(src, coords, maxDist)
    local p = playerCoords(src)
    return #(vec2(p.x, p.y) - vec2(coords.x, coords.y)) <= maxDist
end

local function publicPlant(p)
    return {
        id = p.id, owner = p.owner, strain = p.strain, coords = p.coords,
        growth = p.growth, water = p.water, food = p.food, health = p.health,
        score = p.score, dead = p.dead,
    }
end

local function syncPlant(p) TriggerClientEvent('mars_drugs:client:plantUpdated', -1, publicPlant(p)) end

local function removePlant(id)
    plants[id] = nil
    MySQL.query('DELETE FROM mars_drug_plants WHERE id = ?', { id })
    TriggerClientEvent('mars_drugs:client:plantRemoved', -1, id)
end

local function savePlant(p)
    MySQL.update('UPDATE mars_drug_plants SET growth = ?, water = ?, food = ?, health = ?, score = ?, ticks = ?, dead = ? WHERE id = ?',
        { p.growth, p.water, p.food, p.health, p.score, p.ticks, p.dead and 1 or 0, p.id })
end

-- ─────────────────────────────────────────────────────────────
-- settings (editable in game, stored in the database)
-- ─────────────────────────────────────────────────────────────

local overrides = {}  -- [path] = value
local defaults = {}   -- [path] = original value from config.lua

local function applyOverride(path, value)
    if defaults[path] == nil then defaults[path] = Config.GetPath(path) end
    if Config.SetPath(path, value) then
        overrides[path] = value
        return true
    end
    return false
end

lib.callback.register('mars_drugs:server:getSettings', function() return overrides end)

-- shared with server/admin.lua
MarsDrugs = {
    plants = plants,
    applyOverride = applyOverride,
    overrides = overrides,
    defaults = defaults,
    syncPlant = syncPlant,
    savePlant = savePlant,
    near = near,
    notify = notify,
}

-- ─────────────────────────────────────────────────────────────
-- database
-- ─────────────────────────────────────────────────────────────

MySQL.ready(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mars_drug_plants` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(50) NOT NULL,
            `strain` VARCHAR(50) NOT NULL,
            `x` FLOAT NOT NULL, `y` FLOAT NOT NULL, `z` FLOAT NOT NULL,
            `growth` FLOAT NOT NULL DEFAULT 0,
            `water` FLOAT NOT NULL DEFAULT 50,
            `food` FLOAT NOT NULL DEFAULT 50,
            `health` FLOAT NOT NULL DEFAULT 100,
            `score` FLOAT NOT NULL DEFAULT 100,
            `ticks` INT NOT NULL DEFAULT 0,
            `dead` TINYINT(1) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `mars_drugs_settings` (
            `path` VARCHAR(100) NOT NULL,
            `value` VARCHAR(255) NOT NULL,
            PRIMARY KEY (`path`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    local settingCount = 0
    for _, r in ipairs(MySQL.query.await('SELECT * FROM mars_drugs_settings') or {}) do
        local value = json.decode(r.value)
        if value ~= nil and applyOverride(r.path, value) then settingCount = settingCount + 1 end
    end

    local rows = MySQL.query.await('SELECT * FROM mars_drug_plants') or {}
    for _, r in ipairs(rows) do
        if Config.Strains[r.strain] then
            plants[r.id] = {
                id = r.id, owner = r.owner, strain = r.strain, coords = vec3(r.x, r.y, r.z),
                growth = r.growth, water = r.water, food = r.food, health = r.health,
                score = r.score, ticks = r.ticks, dead = r.dead == 1 or r.dead == true,
            }
        end
    end
    print(('[mars_drugs] loaded %d plants, %d custom settings'):format(#rows, settingCount))
end)

-- ─────────────────────────────────────────────────────────────
-- growth loop
-- ─────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        Wait(Config.TickSeconds * 1000)
        local perMin = Config.TickSeconds / 60
        local baseGrowth = 100 / math.max(0.1, Config.GrowthMinutes) * perMin

        for _, p in pairs(plants) do
            local strain = Config.Strains[p.strain]
            if strain and not p.dead and p.growth < 100 then
                p.water = math.max(0, p.water - Config.WaterDecayPerMinute * perMin * (strain.thirst or 1))
                p.food = math.max(0, p.food - Config.FoodDecayPerMinute * perMin)

                if p.water > 0 and p.food > 0 then
                    p.health = math.min(100, p.health + Config.HealthGainPerMinute * perMin)
                else
                    p.health = math.max(0, p.health - Config.HealthLossPerMinute * perMin)
                end

                local tickScore = p.health * (p.water >= 30 and 1.0 or 0.6) * (p.food >= 30 and 1.0 or 0.6)
                p.score = (p.score * p.ticks + tickScore) / (p.ticks + 1)
                p.ticks = p.ticks + 1

                if p.health <= 0 then
                    p.dead = true
                else
                    p.growth = math.min(100, p.growth + baseGrowth * (strain.growthMult or 1) * (p.health / 100))
                end

                savePlant(p)
                syncPlant(p)
            end
        end
    end
end)

lib.callback.register('mars_drugs:server:getPlants', function()
    local list = {}
    for _, p in pairs(plants) do list[#list + 1] = publicPlant(p) end
    return list
end)

-- ─────────────────────────────────────────────────────────────
-- usable items: seeds and consumables
-- ─────────────────────────────────────────────────────────────

local doses = {} -- [src] = { timestamps }

local function useSeed(source, item)
    local strain = item and item.metadata and item.metadata.strain
    if not strain or not Config.Strains[strain] then return notify(source, 'This seed is broken.', 'error') end
    TriggerClientEvent('mars_drugs:client:startPlanting', source, strain, item.slot)
end

local function useConsumable(itemName)
    return function(source, item)
        local m = item and item.metadata or {}
        local strain = Config.Strains[m.strain]
        if not strain or not Config.Effects[strain.effect] then return notify(source, 'This item cannot be used.', 'error') end
        if not exports.ox_inventory:RemoveItem(source, itemName, 1, nil, item.slot) then return end

        local now = os.time()
        local recent = {}
        for _, t in ipairs(doses[source] or {}) do
            if now - t < Config.Overdose.windowSeconds then recent[#recent + 1] = t end
        end
        recent[#recent + 1] = now
        doses[source] = recent

        TriggerClientEvent('mars_drugs:client:consume', source, {
            item = itemName,
            category = strain.category,
            strain = m.strain,
            quality = m.quality or 'medium',
            effect = strain.effect,
            overdose = #recent > Config.Overdose.threshold,
        })
    end
end

CreateThread(function()
    Wait(1000)
    exports.qbx_core:CreateUseableItem('mars_seed', useSeed)
    exports.qbx_core:CreateUseableItem('mars_weed_seed', useSeed) -- items from v1
    local done = {}
    for _, cat in pairs(Config.Categories) do
        if cat.consumable and not done[cat.consumable] then
            done[cat.consumable] = true
            exports.qbx_core:CreateUseableItem(cat.consumable, useConsumable(cat.consumable))
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- planting
-- ─────────────────────────────────────────────────────────────

lib.callback.register('mars_drugs:server:plant', function(src, strain, slot, coords)
    local cid = citizenId(src)
    local s = Config.Strains[strain]
    if not cid or not s or type(coords) ~= 'vector3' and type(coords) ~= 'table' then return false, 'Could not plant.' end
    if s.enabled == false then return false, 'This strain is disabled.' end
    coords = vec3(coords.x, coords.y, coords.z)
    if not near(src, coords, 3.0) then return false, 'You are too far away.' end

    local owned = 0
    for _, p in pairs(plants) do
        if p.owner == cid and not p.dead then owned = owned + 1 end
        if #(p.coords - coords) < Config.PlantSpacing then return false, 'Too close to another plant.' end
    end
    if owned >= Config.MaxPlantsPerPlayer then
        return false, ('You can only have %d plants.'):format(Config.MaxPlantsPerPlayer)
    end

    local item = exports.ox_inventory:GetSlot(src, slot)
    if not item or (item.name ~= 'mars_seed' and item.name ~= 'mars_weed_seed') or not item.metadata or item.metadata.strain ~= strain then
        return false, 'Seed not found.'
    end
    if not exports.ox_inventory:RemoveItem(src, item.name, 1, nil, slot) then return false, 'Seed not found.' end

    local id = MySQL.insert.await('INSERT INTO mars_drug_plants (owner, strain, x, y, z) VALUES (?, ?, ?, ?, ?)',
        { cid, strain, coords.x, coords.y, coords.z })
    local p = { id = id, owner = cid, strain = strain, coords = coords,
        growth = 0, water = 50, food = 50, health = 100, score = 100, ticks = 0, dead = false }
    plants[id] = p
    syncPlant(p)
    return true, ('%s planted. Keep it watered and fertilized!'):format(s.label)
end)

-- ─────────────────────────────────────────────────────────────
-- plant care
-- ─────────────────────────────────────────────────────────────

local function getNearPlant(src, id)
    local p = plants[id]
    if not p then return nil, 'Plant not found.' end
    if not near(src, p.coords, 3.0) then return nil, 'You are too far away.' end
    return p
end

lib.callback.register('mars_drugs:server:water', function(src, id)
    local p, err = getNearPlant(src, id)
    if not p then return false, err end
    if p.dead then return false, 'This plant is dead.' end
    if not exports.ox_inventory:RemoveItem(src, 'water', 1) then return false, 'You have no water.' end
    p.water = math.min(100, p.water + Config.WaterPerUse)
    savePlant(p); syncPlant(p)
    return true, 'You watered the plant.'
end)

lib.callback.register('mars_drugs:server:feed', function(src, id)
    local p, err = getNearPlant(src, id)
    if not p then return false, err end
    if p.dead then return false, 'This plant is dead.' end
    if not exports.ox_inventory:RemoveItem(src, 'weed_nutrition', 1) then return false, 'You have no fertilizer.' end
    p.food = math.min(100, p.food + Config.FoodPerUse)
    savePlant(p); syncPlant(p)
    return true, 'You fertilized the plant.'
end)

lib.callback.register('mars_drugs:server:harvest', function(src, id)
    local p, err = getNearPlant(src, id)
    if not p then return false, err end
    if p.dead then return false, 'This plant is dead.' end
    if p.growth < 100 then return false, 'The plant is not fully grown yet.' end
    if p.owner ~= citizenId(src) and not Config.AllowHarvestByOthers then return false, 'This plant is not yours.' end

    local strain = Config.Strains[p.strain]
    local cat = Config.Categories[strain.category]
    local quality = Config.QualityFor(p.score)
    local base = Config.Yield.min + (Config.Yield.max - Config.Yield.min) * (p.score / 100)
    local amount = math.max(1, math.floor(base * (strain.yieldMult or 1) + 0.5))
    local meta = Config.ProductMeta(p.strain, quality.key)

    if not exports.ox_inventory:CanCarryItem(src, cat.harvest, amount, meta) then
        return false, 'Not enough space in your inventory.'
    end
    exports.ox_inventory:AddItem(src, cat.harvest, amount, meta)
    removePlant(id)
    local nextStep = cat.dried and ' Dry it on the drying rack at the lab (/druglab), then pack it at the table.'
        or ' Take it to the processing table at the lab.'
    return true, ('Harvested %d × %s (%s quality).%s'):format(amount, strain.label, quality.label, nextStep)
end)

lib.callback.register('mars_drugs:server:destroy', function(src, id)
    local p, err = getNearPlant(src, id)
    if not p then return false, err end
    if not (p.dead or p.owner == citizenId(src) or isPolice(src)) then
        return false, 'Only the owner or the police can destroy this plant.'
    end
    removePlant(id)
    return true, 'Plant destroyed.'
end)

-- ─────────────────────────────────────────────────────────────
-- processing
-- ─────────────────────────────────────────────────────────────

local function validStrainQuality(strain, quality)
    return Config.Strains[strain] and Config.QualityByKey(quality)
end

-- drying rack: harvest item -> dried item
lib.callback.register('mars_drugs:server:dry', function(src, strain, quality, count)
    if not near(src, Config.Lab.rack, 6.0) then return false, 'You must be at the drying rack.' end
    if not validStrainQuality(strain, quality) then return false, 'Error.' end
    local cat = Config.CategoryOf(strain)
    if not cat.dried then return false, 'This does not need drying.' end
    count = math.floor(tonumber(count) or 0)
    if count < 1 then return false, 'Invalid amount.' end

    local meta = Config.ProductMeta(strain, quality)
    if exports.ox_inventory:GetItemCount(src, cat.harvest, meta, true) < count then return false, 'You do not have that many.' end
    exports.ox_inventory:RemoveItem(src, cat.harvest, count, meta)
    exports.ox_inventory:AddItem(src, cat.dried, count, meta)
    return true, ('%d dried.'):format(count)
end)

-- packing table: (dried or harvest) x perProduct + container (+ extra) -> product
lib.callback.register('mars_drugs:server:pack', function(src, strain, quality, products)
    if not near(src, Config.Lab.table, 6.0) then return false, 'You must be at the packing table.' end
    if not validStrainQuality(strain, quality) then return false, 'Error.' end
    local cat = Config.CategoryOf(strain)
    products = math.floor(tonumber(products) or 0)
    if products < 1 then return false, 'Invalid amount.' end

    local input = cat.dried or cat.harvest
    local meta = Config.ProductMeta(strain, quality)
    local need = products * cat.perProduct
    if exports.ox_inventory:GetItemCount(src, input, meta, true) < need then
        return false, ('%d products need %d units.'):format(products, need)
    end
    if exports.ox_inventory:GetItemCount(src, cat.container) < products then
        return false, ('You need %d empty bags.'):format(products)
    end
    if cat.extra and exports.ox_inventory:GetItemCount(src, cat.extra.item) < products * cat.extra.count then
        return false, ('You need %d × chemicals.'):format(products * cat.extra.count)
    end
    if not exports.ox_inventory:CanCarryItem(src, cat.product, products, meta) then
        return false, 'Not enough space in your inventory.'
    end

    exports.ox_inventory:RemoveItem(src, input, need, meta)
    exports.ox_inventory:RemoveItem(src, cat.container, products)
    if cat.extra then exports.ox_inventory:RemoveItem(src, cat.extra.item, products * cat.extra.count) end
    exports.ox_inventory:AddItem(src, cat.product, products, meta)
    return true, ('%d packed.'):format(products)
end)

-- rolling joints: 1 dry bud + 1 rolling paper -> jointsPerBud joints
lib.callback.register('mars_drugs:server:roll', function(src, strain, quality, buds)
    if not near(src, Config.Lab.table, 6.0) then return false, 'You must be at the table.' end
    if not validStrainQuality(strain, quality) then return false, 'Error.' end
    local cat, catKey = Config.CategoryOf(strain)
    if catKey ~= 'weed' then return false, 'Only cannabis can be rolled.' end
    buds = math.floor(tonumber(buds) or 0)
    if buds < 1 then return false, 'Invalid amount.' end

    local meta = Config.ProductMeta(strain, quality)
    if exports.ox_inventory:GetItemCount(src, cat.dried, meta, true) < buds then return false, 'Not enough dry buds.' end
    if exports.ox_inventory:GetItemCount(src, 'rolling_paper') < buds then return false, 'Not enough rolling papers.' end
    local joints = buds * Config.Processing.jointsPerBud
    if not exports.ox_inventory:CanCarryItem(src, 'mars_joint', joints, meta) then return false, 'Not enough space in your inventory.' end

    exports.ox_inventory:RemoveItem(src, cat.dried, buds, meta)
    exports.ox_inventory:RemoveItem(src, 'rolling_paper', buds)
    exports.ox_inventory:AddItem(src, 'mars_joint', joints, meta)
    return true, ('Rolled %d joints.'):format(joints)
end)

-- ─────────────────────────────────────────────────────────────
-- selling to NPCs (any packed product or joints)
-- ─────────────────────────────────────────────────────────────

local function sellableItems()
    local list, seen = {}, {}
    for _, cat in pairs(Config.Categories) do
        if not seen[cat.product] then seen[cat.product] = true; list[#list + 1] = cat.product end
    end
    list[#list + 1] = 'mars_joint'
    return list
end

local function alertPolice(coords)
    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId)
        if isPolice(id) then TriggerClientEvent('mars_drugs:client:policeAlert', id, coords) end
    end
end

-- optional: mars_heat (heat + reputation)
local function heatApi() return GetResourceState('mars_heat') == 'started' and exports.mars_heat or nil end

lib.callback.register('mars_drugs:server:sell', function(src)
    local now = os.time()
    if sellCooldown[src] and now - sellCooldown[src] < Config.Selling.cooldownSeconds then return false, 'Wait a moment...' end
    sellCooldown[src] = now

    local candidates = {}
    for _, itemName in ipairs(sellableItems()) do
        for _, slot in pairs(exports.ox_inventory:Search(src, 'slots', itemName) or {}) do
            candidates[#candidates + 1] = slot
        end
    end
    if #candidates == 0 then return false, 'You have nothing to sell.' end
    local slot = candidates[math.random(#candidates)]

    local heat = heatApi()
    local rep = heat and heat:GetRep(src, 'drugs')
    if math.random(100) > Config.Selling.acceptChance + (rep and rep.acceptBonus or 0) then
        local chance = heat and heat:AlertChance(src, Config.Selling.policeAlertChance) or Config.Selling.policeAlertChance
        if math.random(100) <= chance then
            alertPolice(playerCoords(src))
            if heat then heat:Crime(src, 'drug_snitch') end
            return false, 'The customer refused and called the police!'
        end
        return false, 'The customer refused.'
    end

    local strain, q = Config.Strains[slot.metadata.strain], Config.QualityByKey(slot.metadata.quality)
    if not strain or not q then return false, 'This product cannot be sold.' end
    local cat = Config.Categories[strain.category]

    local amount = math.random(1, math.min(Config.Selling.maxPerDeal, slot.count))
    local unit = strain.basePrice * q.priceMult * (cat.priceMult or 1)
    if slot.name == 'mars_joint' then unit = unit * Config.Selling.jointPriceMult end
    local price = math.floor(unit * amount * (math.random(90, 110) / 100) * (rep and rep.priceMult or 1))

    if not exports.ox_inventory:RemoveItem(src, slot.name, amount, nil, slot.slot) then return false, 'Sale failed.' end
    getPlayer(src).Functions.AddMoney('cash', price, 'mars-drugs-sale')
    if heat then heat:Crime(src, 'drug_sale') end
    return true, ('Sold %d × %s (%s) for $%d.'):format(amount, strain.label, q.label, price)
end)

AddEventHandler('playerDropped', function()
    sellCooldown[source] = nil
    doses[source] = nil
end)

-- ─────────────────────────────────────────────────────────────
-- seed shop
-- ─────────────────────────────────────────────────────────────

function MarsDrugs.registerShop()
    local inventory = {}
    for _, key in ipairs(Config.StrainOrder) do
        local s = Config.Strains[key]
        if s and s.enabled ~= false then
            inventory[#inventory + 1] = { name = 'mars_seed', price = s.seedPrice, metadata = Config.SeedMeta(key) }
        end
    end
    for _, item in ipairs(Config.Shop.extra) do inventory[#inventory + 1] = item end

    for _ = 1, 60 do
        local ok = pcall(function()
            exports.ox_inventory:RegisterShop('mars_drugs_shop', { name = Config.Shop.blip.label, inventory = inventory })
        end)
        if ok then return true end
        Wait(1000)
    end
    print('^1[mars_drugs] could not register the seed shop (ox_inventory not ready)^0')
end

CreateThread(function()
    Wait(2000) -- let the database settings load first
    MarsDrugs.registerShop()
end)

-- our own shop menu (the NPC talks to these, no ox_inventory shop needed)
local function shopItems()
    local list = {}
    for _, key in ipairs(Config.StrainOrder) do
        local s = Config.Strains[key]
        if s and s.enabled ~= false then
            local meta = Config.SeedMeta(key)
            list[#list + 1] = { name = 'mars_seed', label = meta.label, description = meta.description,
                                price = s.seedPrice, metadata = meta, seed = true }
        end
    end
    for _, item in ipairs(Config.Shop.extra) do
        local def = exports.ox_inventory:Items(item.name)
        list[#list + 1] = { name = item.name, label = def and def.label or item.name, price = item.price }
    end
    return list
end

lib.callback.register('mars_drugs:server:shopList', function()
    local list = shopItems()
    for _, it in ipairs(list) do it.metadata = nil end
    return list
end)

lib.callback.register('mars_drugs:server:shopBuy', function(src, index, amount)
    if not near(src, Config.Shop.coords.xyz, 6.0) then return false, 'You are too far from the shop.' end
    local item = shopItems()[tonumber(index) or 0]
    amount = math.floor(tonumber(amount) or 0)
    if not item or amount < 1 or amount > 50 then return false, 'Invalid amount.' end
    if not exports.ox_inventory:CanCarryItem(src, item.name, amount, item.metadata) then
        return false, 'You cannot carry that much.'
    end
    local player = getPlayer(src)
    if not player then return false, 'Try again.' end
    local cost = item.price * amount
    local paid = player.Functions.RemoveMoney('cash', cost, 'garden-supplies')
        or player.Functions.RemoveMoney('bank', cost, 'garden-supplies')
    if not paid then return false, ('You need $%d (cash or bank).'):format(cost) end
    exports.ox_inventory:AddItem(src, item.name, amount, item.metadata)
    return true, ('Bought %d × %s for $%d.'):format(amount, item.label, cost)
end)

-- ─────────────────────────────────────────────────────────────
-- admin test commands
-- ─────────────────────────────────────────────────────────────

lib.addCommand('drugkit', { help = 'Mars drugs: give test items', restricted = 'group.admin' }, function(src)
    for _, key in ipairs(Config.StrainOrder) do
        exports.ox_inventory:AddItem(src, 'mars_seed', 1, Config.SeedMeta(key))
    end
    exports.ox_inventory:AddItem(src, 'water', 15)
    exports.ox_inventory:AddItem(src, 'weed_nutrition', 8)
    exports.ox_inventory:AddItem(src, 'empty_weed_bag', 30)
    exports.ox_inventory:AddItem(src, 'rolling_paper', 20)
    exports.ox_inventory:AddItem(src, 'mars_chemicals', 5)
    notify(src, 'Test items given.', 'success')
end)

lib.addCommand('druggrow', { help = 'Mars drugs: fully grow plants near you', restricted = 'group.admin' }, function(src)
    local n = 0
    for _, p in pairs(plants) do
        if not p.dead and near(src, p.coords, 15.0) then
            p.growth = 100; savePlant(p); syncPlant(p); n = n + 1
        end
    end
    notify(src, ('%d plants fully grown.'):format(n), 'success')
end)

lib.addCommand('druglab', { help = 'Mars drugs: teleport to the lab', restricted = 'group.admin' }, function(src)
    local c = Config.Lab.table
    SetEntityCoords(GetPlayerPed(src), c.x + 2.0, c.y, c.z + 1.0, false, false, false, false)
end)

lib.addCommand('drugshop', { help = 'Mars drugs: teleport to the seed shop', restricted = 'group.admin' }, function(src)
    local c = Config.Shop.coords
    SetEntityCoords(GetPlayerPed(src), c.x + 1.5, c.y, c.z + 1.0, false, false, false, false)
end)
