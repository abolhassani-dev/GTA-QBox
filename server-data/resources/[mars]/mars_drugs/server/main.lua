local plants = {}          -- [id] = plant
local sellCooldown = {}    -- [source] = os.time() of last deal

-- ─────────────────────────────────────────────────────────────
-- helpers
-- ─────────────────────────────────────────────────────────────

local function notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Mars', description = msg, type = kind or 'inform' })
end

local function getPlayer(src)
    return exports.qbx_core:GetPlayer(src)
end

local function citizenId(src)
    local player = getPlayer(src)
    return player and player.PlayerData.citizenid
end

local function isPolice(src)
    local player = getPlayer(src)
    local job = player and player.PlayerData.job
    return job and job.type == Config.PoliceJobType and job.onduty
end

local function playerCoords(src)
    return GetEntityCoords(GetPlayerPed(src))
end

local function near(src, coords, maxDist)
    return #(playerCoords(src) - vec3(coords.x, coords.y, coords.z)) <= maxDist
end

---Public view of a plant sent to clients
local function publicPlant(p)
    return {
        id = p.id, owner = p.owner, strain = p.strain,
        coords = p.coords, growth = p.growth, water = p.water,
        food = p.food, health = p.health, score = p.score, dead = p.dead,
    }
end

local function syncPlant(p)
    TriggerClientEvent('mars_drugs:client:plantUpdated', -1, publicPlant(p))
end

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

    local rows = MySQL.query.await('SELECT * FROM mars_drug_plants') or {}
    for _, r in ipairs(rows) do
        if Config.Strains[r.strain] then
            plants[r.id] = {
                id = r.id, owner = r.owner, strain = r.strain,
                coords = vec3(r.x, r.y, r.z),
                growth = r.growth, water = r.water, food = r.food,
                health = r.health, score = r.score, ticks = r.ticks,
                dead = r.dead == 1 or r.dead == true,
            }
        end
    end
    print(('[mars_drugs] loaded %d plants'):format(#rows))
end)

-- ─────────────────────────────────────────────────────────────
-- growth loop
-- ─────────────────────────────────────────────────────────────

CreateThread(function()
    local growthPerTick = 100 / ((Config.GrowthMinutes * 60) / Config.TickSeconds)

    while true do
        Wait(Config.TickSeconds * 1000)

        for _, p in pairs(plants) do
            if not p.dead and p.growth < 100 then
                p.water = math.max(0, p.water - Config.WaterDecay)
                p.food = math.max(0, p.food - Config.FoodDecay)

                local cared = p.water > 0 and p.food > 0
                if cared then
                    p.health = math.min(100, p.health + Config.HealthGainPerTick)
                else
                    p.health = math.max(0, p.health - Config.HealthLossPerTick)
                end

                -- quality: running average of how well the plant was kept this tick
                local tickScore = p.health
                    * (p.water >= 30 and 1.0 or 0.6)
                    * (p.food >= 30 and 1.0 or 0.6)
                p.score = (p.score * p.ticks + tickScore) / (p.ticks + 1)
                p.ticks = p.ticks + 1

                if p.health <= 0 then
                    p.dead = true
                else
                    p.growth = math.min(100, p.growth + growthPerTick * (p.health / 100))
                end

                savePlant(p)
                syncPlant(p)
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- client data
-- ─────────────────────────────────────────────────────────────

lib.callback.register('mars_drugs:server:getPlants', function()
    local list = {}
    for _, p in pairs(plants) do list[#list + 1] = publicPlant(p) end
    return list
end)

-- ─────────────────────────────────────────────────────────────
-- seeds: using the item starts planting on the client
-- ─────────────────────────────────────────────────────────────

CreateThread(function()
    Wait(1000)
    exports.qbx_core:CreateUseableItem('mars_weed_seed', function(source, item)
        local strain = item and item.metadata and item.metadata.strain
        if not strain or not Config.Strains[strain] then
            return notify(source, 'این بذر خراب است.', 'error')
        end
        TriggerClientEvent('mars_drugs:client:startPlanting', source, strain, item.slot)
    end)
end)

lib.callback.register('mars_drugs:server:plant', function(src, strain, slot, coords)
    local cid = citizenId(src)
    if not cid or not Config.Strains[strain] or type(coords) ~= 'vector3' and type(coords) ~= 'table' then
        return false, 'خطا در کاشت.'
    end
    coords = vec3(coords.x, coords.y, coords.z)

    if not near(src, coords, 3.0) then return false, 'خیلی دور هستید.' end

    local owned = 0
    for _, p in pairs(plants) do
        if p.owner == cid and not p.dead then owned = owned + 1 end
        if #(p.coords - coords) < Config.PlantSpacing then
            return false, 'اینجا خیلی نزدیک به یک گیاه دیگر است.'
        end
    end
    if owned >= Config.MaxPlantsPerPlayer then
        return false, ('حداکثر %d گیاه می‌توانید داشته باشید.'):format(Config.MaxPlantsPerPlayer)
    end

    local item = exports.ox_inventory:GetSlot(src, slot)
    if not item or item.name ~= 'mars_weed_seed' or not item.metadata or item.metadata.strain ~= strain then
        return false, 'بذر پیدا نشد.'
    end
    if not exports.ox_inventory:RemoveItem(src, 'mars_weed_seed', 1, nil, slot) then
        return false, 'بذر پیدا نشد.'
    end

    local id = MySQL.insert.await('INSERT INTO mars_drug_plants (owner, strain, x, y, z) VALUES (?, ?, ?, ?, ?)',
        { cid, strain, coords.x, coords.y, coords.z })

    local p = {
        id = id, owner = cid, strain = strain, coords = coords,
        growth = 0, water = 50, food = 50, health = 100, score = 100, ticks = 0, dead = false,
    }
    plants[id] = p
    syncPlant(p)
    return true, ('%s کاشته شد. یادتان نرود آب و کود بدهید!'):format(Config.Strains[strain].label)
end)

-- ─────────────────────────────────────────────────────────────
-- plant care
-- ─────────────────────────────────────────────────────────────

local function getNearPlant(src, id)
    local p = plants[id]
    if not p then return nil, 'گیاه پیدا نشد.' end
    if not near(src, p.coords, 3.0) then return nil, 'خیلی دور هستید.' end
    return p
end

lib.callback.register('mars_drugs:server:water', function(src, id)
    local p, err = getNearPlant(src, id)
    if not p then return false, err end
    if p.dead then return false, 'این گیاه مرده است.' end
    if not exports.ox_inventory:RemoveItem(src, 'water', 1) then return false, 'آب ندارید.' end
    p.water = math.min(100, p.water + Config.WaterPerUse)
    savePlant(p); syncPlant(p)
    return true, 'به گیاه آب دادید.'
end)

lib.callback.register('mars_drugs:server:feed', function(src, id)
    local p, err = getNearPlant(src, id)
    if not p then return false, err end
    if p.dead then return false, 'این گیاه مرده است.' end
    if not exports.ox_inventory:RemoveItem(src, 'weed_nutrition', 1) then return false, 'کود ندارید.' end
    p.food = math.min(100, p.food + Config.FoodPerUse)
    savePlant(p); syncPlant(p)
    return true, 'به گیاه کود دادید.'
end)

lib.callback.register('mars_drugs:server:harvest', function(src, id)
    local p, err = getNearPlant(src, id)
    if not p then return false, err end
    if p.dead then return false, 'این گیاه مرده است.' end
    if p.growth < 100 then return false, 'گیاه هنوز کامل رشد نکرده.' end

    local cid = citizenId(src)
    if p.owner ~= cid and not Config.AllowHarvestByOthers then return false, 'این گیاه مال شما نیست.' end

    local quality = Config.QualityFor(p.score)
    local amount = math.floor(Config.Yield.min + (Config.Yield.max - Config.Yield.min) * (p.score / 100) + 0.5)
    local meta = Config.ProductMeta(p.strain, quality.key)

    if not exports.ox_inventory:CanCarryItem(src, 'mars_weed_wet', amount, meta) then
        return false, 'جای کافی در کیف ندارید.'
    end
    exports.ox_inventory:AddItem(src, 'mars_weed_wet', amount, meta)
    removePlant(id)
    return true, ('%d گل خیس %s با کیفیت «%s» برداشت کردید.'):format(amount, Config.Strains[p.strain].label, quality.label)
end)

lib.callback.register('mars_drugs:server:destroy', function(src, id)
    local p, err = getNearPlant(src, id)
    if not p then return false, err end
    if not (p.dead or p.owner == citizenId(src) or isPolice(src)) then
        return false, 'فقط صاحب گیاه یا پلیس می‌تواند آن را از بین ببرد.'
    end
    removePlant(id)
    return true, 'گیاه از بین رفت.'
end)

-- ─────────────────────────────────────────────────────────────
-- processing: drying rack and packing table
-- ─────────────────────────────────────────────────────────────

lib.callback.register('mars_drugs:server:dry', function(src, strain, quality, count)
    if not near(src, Config.Lab.rack, 4.0) then return false, 'باید کنار خشک‌کن باشید.' end
    if not Config.Strains[strain] or not Config.QualityByKey(quality) then return false, 'خطا.' end
    count = math.floor(tonumber(count) or 0)
    if count < 1 then return false, 'تعداد نامعتبر است.' end

    local meta = Config.ProductMeta(strain, quality)
    local have = exports.ox_inventory:GetItemCount(src, 'mars_weed_wet', meta, true)
    if have < count then return false, 'به این تعداد گل خیس ندارید.' end

    exports.ox_inventory:RemoveItem(src, 'mars_weed_wet', count, meta)
    exports.ox_inventory:AddItem(src, 'mars_weed_dry', count, meta)
    return true, ('%d گل خشک شد.'):format(count)
end)

lib.callback.register('mars_drugs:server:pack', function(src, strain, quality, bags)
    if not near(src, Config.Lab.table, 4.0) then return false, 'باید کنار میز بسته‌بندی باشید.' end
    if not Config.Strains[strain] or not Config.QualityByKey(quality) then return false, 'خطا.' end
    bags = math.floor(tonumber(bags) or 0)
    if bags < 1 then return false, 'تعداد نامعتبر است.' end

    local meta = Config.ProductMeta(strain, quality)
    local needBuds = bags * Config.Processing.budsPerBag
    if exports.ox_inventory:GetItemCount(src, 'mars_weed_dry', meta, true) < needBuds then
        return false, ('برای %d بسته، %d گل خشک لازم است.'):format(bags, needBuds)
    end
    if exports.ox_inventory:GetItemCount(src, 'empty_weed_bag') < bags then
        return false, ('%d کیسه‌ی خالی لازم است.'):format(bags)
    end
    if not exports.ox_inventory:CanCarryItem(src, 'mars_weed_bag', bags, meta) then
        return false, 'جای کافی در کیف ندارید.'
    end

    exports.ox_inventory:RemoveItem(src, 'mars_weed_dry', needBuds, meta)
    exports.ox_inventory:RemoveItem(src, 'empty_weed_bag', bags)
    exports.ox_inventory:AddItem(src, 'mars_weed_bag', bags, meta)
    return true, ('%d بسته آماده شد.'):format(bags)
end)

-- ─────────────────────────────────────────────────────────────
-- selling to NPCs
-- ─────────────────────────────────────────────────────────────

local function alertPolice(coords)
    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId)
        if isPolice(id) then
            TriggerClientEvent('mars_drugs:client:policeAlert', id, coords)
        end
    end
end

lib.callback.register('mars_drugs:server:sell', function(src)
    local now = os.time()
    if sellCooldown[src] and now - sellCooldown[src] < Config.Selling.cooldownSeconds then
        return false, 'کمی صبر کنید...'
    end
    sellCooldown[src] = now

    local slots = exports.ox_inventory:Search(src, 'slots', 'mars_weed_bag')
    local slot = slots and slots[1]
    if not slot then return false, 'جنسی برای فروش ندارید.' end

    if math.random(100) > Config.Selling.acceptChance then
        if math.random(100) <= Config.Selling.policeAlertChance then
            alertPolice(playerCoords(src))
            return false, 'مشتری قبول نکرد و به پلیس زنگ زد!'
        end
        return false, 'مشتری قبول نکرد.'
    end

    local strain, quality = slot.metadata.strain, slot.metadata.quality
    local strainCfg, q = Config.Strains[strain], Config.QualityByKey(quality)
    if not strainCfg or not q then return false, 'این جنس قابل فروش نیست.' end

    local amount = math.random(1, math.min(Config.Selling.maxPerDeal, slot.count))
    local price = math.floor(strainCfg.basePrice * q.priceMult * amount * (math.random(90, 110) / 100))

    if not exports.ox_inventory:RemoveItem(src, 'mars_weed_bag', amount, nil, slot.slot) then
        return false, 'خطا در فروش.'
    end
    getPlayer(src).Functions.AddMoney('cash', price, 'mars-drugs-sale')
    return true, ('%d بسته %s (%s) را به %d$ فروختید.'):format(amount, strainCfg.label, q.label, price)
end)

AddEventHandler('playerDropped', function()
    sellCooldown[source] = nil
end)

-- ─────────────────────────────────────────────────────────────
-- seed shop (ox_inventory)
-- ─────────────────────────────────────────────────────────────

CreateThread(function()
    local inventory = {}
    for key, strain in pairs(Config.Strains) do
        inventory[#inventory + 1] = { name = 'mars_weed_seed', price = strain.seedPrice, metadata = Config.SeedMeta(key) }
    end
    for _, item in ipairs(Config.Shop.extra) do inventory[#inventory + 1] = item end

    -- ox_inventory finishes loading after the database is ready, so its
    -- shop export may not exist yet: retry for up to a minute.
    for _ = 1, 60 do
        local ok = pcall(function()
            exports.ox_inventory:RegisterShop('mars_drugs_shop', {
                name = Config.Shop.blip.label,
                inventory = inventory,
            })
        end)
        if ok then return end
        Wait(1000)
    end
    print('^1[mars_drugs] could not register the seed shop (ox_inventory not ready)^0')
end)

-- ─────────────────────────────────────────────────────────────
-- admin test commands
-- ─────────────────────────────────────────────────────────────

lib.addCommand('drugkit', { help = 'Mars drugs: give test items', restricted = 'group.admin' }, function(src)
    for key in pairs(Config.Strains) do
        exports.ox_inventory:AddItem(src, 'mars_weed_seed', 2, Config.SeedMeta(key))
    end
    exports.ox_inventory:AddItem(src, 'water', 10)
    exports.ox_inventory:AddItem(src, 'weed_nutrition', 5)
    exports.ox_inventory:AddItem(src, 'empty_weed_bag', 20)
    notify(src, 'وسایل تست داده شد.', 'success')
end)

lib.addCommand('druggrow', { help = 'Mars drugs: fully grow plants near you', restricted = 'group.admin' }, function(src)
    local n = 0
    for _, p in pairs(plants) do
        if not p.dead and near(src, p.coords, 15.0) then
            p.growth = 100
            savePlant(p); syncPlant(p)
            n = n + 1
        end
    end
    notify(src, ('%d گیاه کامل رشد کرد.'):format(n), 'success')
end)

lib.addCommand('druglab', { help = 'Mars drugs: teleport to the lab', restricted = 'group.admin' }, function(src)
    local c = Config.Lab.table
    SetEntityCoords(GetPlayerPed(src), c.x + 2.0, c.y, c.z + 1.0, false, false, false, false)
end)

lib.addCommand('drugshop', { help = 'Mars drugs: teleport to the seed shop', restricted = 'group.admin' }, function(src)
    local c = Config.Shop.coords
    SetEntityCoords(GetPlayerPed(src), c.x + 1.5, c.y, c.z + 1.0, false, false, false, false)
end)
