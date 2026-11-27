local plants = {}       -- [id] = plant (from server)
local plantObjects = {} -- [id] = { entity = handle, model = hash }
local labEntities = {}
local shopPed
local soldPeds = {}

-- ─────────────────────────────────────────────────────────────
-- helpers
-- ─────────────────────────────────────────────────────────────

local function notify(ok, msg)
    lib.notify({ title = 'Mars', description = msg, type = ok and 'success' or 'error' })
end

local function loadModel(model)
    if not IsModelInCdimage(model) then return false end
    lib.requestModel(model, 10000)
    return true
end

local function groundZ(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    for _ = 1, 20 do
        local found, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
        if found then return gz end
        Wait(50)
    end
    return z
end

local function modelForGrowth(growth)
    if growth < 33 then return Config.Props.small end
    if growth < 66 then return Config.Props.medium end
    return Config.Props.large
end

local function progress(label, duration, anim, prop)
    return lib.progressBar({
        duration = duration,
        label = label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = anim,
        prop = prop,
    })
end

local function strainLabel(key)
    return Config.Strains[key] and Config.Strains[key].label or key
end

-- ─────────────────────────────────────────────────────────────
-- plant status menu
-- ─────────────────────────────────────────────────────────────

local function showStatus(id)
    local p = plants[id]
    if not p then return end
    local q = Config.QualityFor(p.score)

    lib.registerContext({
        id = 'mars_drugs_plant',
        title = ('🌿 %s'):format(strainLabel(p.strain)),
        options = {
            { title = p.dead and 'Status: dead ☠️' or ('Growth: %d%%'):format(math.floor(p.growth)), progress = p.growth, colorScheme = 'green', readOnly = true },
            { title = ('Water: %d%%'):format(math.floor(p.water)), progress = p.water, colorScheme = 'blue', readOnly = true },
            { title = ('Fertilizer: %d%%'):format(math.floor(p.food)), progress = p.food, colorScheme = 'yellow', readOnly = true },
            { title = ('Health: %d%%'):format(math.floor(p.health)), progress = p.health, colorScheme = p.health > 50 and 'green' or 'red', readOnly = true },
            { title = ('Current quality: %s'):format(q.label), description = 'Better care means higher quality.', readOnly = true },
        },
    })
    lib.showContext('mars_drugs_plant')
end

-- ─────────────────────────────────────────────────────────────
-- plant actions
-- ─────────────────────────────────────────────────────────────

local function doWater(id)
    if exports.ox_inventory:Search('count', 'water') < 1 then return notify(false, 'You have no water.') end
    if not progress('Watering...', 4000, { dict = 'weapon@w_sp_jerrycan', clip = 'fire' }) then return end
    notify(lib.callback.await('mars_drugs:server:water', false, id))
end

local function doFeed(id)
    if exports.ox_inventory:Search('count', 'weed_nutrition') < 1 then return notify(false, 'You have no fertilizer.') end
    if not progress('Fertilizing...', 4000, { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base' }) then return end
    notify(lib.callback.await('mars_drugs:server:feed', false, id))
end

local function doHarvest(id)
    if not progress('Harvesting...', 8000, { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base' }) then return end
    notify(lib.callback.await('mars_drugs:server:harvest', false, id))
end

local function doDestroy(id)
    local confirm = lib.alertDialog({ header = 'Destroy plant', content = 'Are you sure?', centered = true, cancel = true })
    if confirm ~= 'confirm' then return end
    if not progress('Destroying...', 5000, { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base' }) then return end
    notify(lib.callback.await('mars_drugs:server:destroy', false, id))
end

local function plantTargetOptions(id)
    return {
        { name = 'mars_plant_status', icon = 'fa-solid fa-seedling', label = 'Plant status',
          onSelect = function() showStatus(id) end },
        { name = 'mars_plant_water', icon = 'fa-solid fa-droplet', label = 'Water',
          canInteract = function() local p = plants[id] return p and not p.dead and p.growth < 100 end,
          onSelect = function() doWater(id) end },
        { name = 'mars_plant_feed', icon = 'fa-solid fa-flask', label = 'Fertilize',
          canInteract = function() local p = plants[id] return p and not p.dead and p.growth < 100 end,
          onSelect = function() doFeed(id) end },
        { name = 'mars_plant_harvest', icon = 'fa-solid fa-hand-scissors', label = 'Harvest',
          canInteract = function() local p = plants[id] return p and not p.dead and p.growth >= 100 end,
          onSelect = function() doHarvest(id) end },
        { name = 'mars_plant_destroy', icon = 'fa-solid fa-fire', label = 'Destroy',
          onSelect = function() doDestroy(id) end },
    }
end

-- ─────────────────────────────────────────────────────────────
-- plant props (spawned locally near the player)
-- ─────────────────────────────────────────────────────────────

local function deleteObject(id)
    local obj = plantObjects[id]
    if obj then
        exports.ox_target:removeLocalEntity(obj.entity)
        if DoesEntityExist(obj.entity) then DeleteEntity(obj.entity) end
        plantObjects[id] = nil
    end
end

local function spawnObject(p)
    local model = modelForGrowth(p.growth)
    if not loadModel(model) then return end
    local entity = CreateObject(model, p.coords.x, p.coords.y, p.coords.z, false, false, false)
    FreezeEntityPosition(entity, true)
    SetEntityAsMissionEntity(entity, true, true)
    if p.dead then SetEntityAlpha(entity, 150, false) end
    SetModelAsNoLongerNeeded(model)
    exports.ox_target:addLocalEntity(entity, plantTargetOptions(p.id))
    plantObjects[p.id] = { entity = entity, model = model, dead = p.dead }
end

CreateThread(function()
    while true do
        local pos = GetEntityCoords(cache.ped)
        for id, p in pairs(plants) do
            local inRange = #(pos - p.coords) < Config.SpawnDistance
            local obj = plantObjects[id]
            if inRange then
                if obj and (obj.model ~= modelForGrowth(p.growth) or obj.dead ~= p.dead) then
                    deleteObject(id)
                    obj = nil
                end
                if not obj then spawnObject(p) end
            elseif obj then
                deleteObject(id)
            end
        end
        Wait(1500)
    end
end)

local function setPlant(p)
    p.coords = vec3(p.coords.x, p.coords.y, p.coords.z)
    plants[p.id] = p
end

RegisterNetEvent('mars_drugs:client:plantUpdated', function(p) setPlant(p) end)

RegisterNetEvent('mars_drugs:client:plantRemoved', function(id)
    plants[id] = nil
    deleteObject(id)
end)

local function loadPlants()
    local list = lib.callback.await('mars_drugs:server:getPlants', false) or {}
    for _, p in ipairs(list) do setPlant(p) end
end

-- ─────────────────────────────────────────────────────────────
-- planting
-- ─────────────────────────────────────────────────────────────

RegisterNetEvent('mars_drugs:client:startPlanting', function(strain, slot)
    local ped = cache.ped
    if IsPedInAnyVehicle(ped, false) then return notify(false, 'You cannot plant inside a vehicle.') end
    if GetInteriorFromEntity(ped) ~= 0 then return notify(false, 'You can only plant outdoors.') end

    local spot = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.8, 0.0)
    local z = groundZ(spot.x, spot.y, spot.z)

    if not progress(('Planting %s...'):format(strainLabel(strain)), Config.PlantAnimMs,
        { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base' }) then return end

    notify(lib.callback.await('mars_drugs:server:plant', false, strain, slot, vec3(spot.x, spot.y, z)))
end)

-- ─────────────────────────────────────────────────────────────
-- lab: drying rack and packing table
-- ─────────────────────────────────────────────────────────────

local function groupProducts(itemName)
    local groups = {}
    for _, slot in pairs(exports.ox_inventory:Search('slots', itemName) or {}) do
        local m = slot.metadata or {}
        if m.strain and m.quality then
            local key = m.strain .. ':' .. m.quality
            groups[key] = groups[key] or { strain = m.strain, quality = m.quality, count = 0 }
            groups[key].count = groups[key].count + slot.count
        end
    end
    return groups
end

local function chooseAndRun(itemName, title, emptyMsg, perUnit, maxFn, run)
    local groups = groupProducts(itemName)
    local options = {}
    for _, g in pairs(groups) do
        local q = Config.QualityByKey(g.quality)
        local max = maxFn(g)
        options[#options + 1] = {
            title = ('%s – %s'):format(strainLabel(g.strain), q and q.label or g.quality),
            description = ('You have: %d'):format(g.count),
            disabled = max < 1,
            onSelect = function()
                local input = lib.inputDialog(title, {
                    { type = 'number', label = 'Amount', default = max, min = 1, max = max, required = true },
                })
                if not input then return end
                local count = math.floor(input[1])
                local duration = math.min(Config.Processing.maxMs, perUnit * count)
                run(g, count, duration)
            end,
        }
    end
    if #options == 0 then return notify(false, emptyMsg) end
    lib.registerContext({ id = 'mars_drugs_process', title = title, options = options })
    lib.showContext('mars_drugs_process')
end

local function openDrying()
    chooseAndRun('mars_weed_wet', 'Dry buds', 'You have no wet buds.', Config.Processing.dryMsPerItem,
        function(g) return g.count end,
        function(g, count, duration)
            if not progress('Hanging buds on the rack...', duration, { dict = 'anim@amb@business@weed@weed_inspecting_lo_med_hi@', clip = 'weed_crouch_checkingleaves_idle_01_inspector' }) then return end
            notify(lib.callback.await('mars_drugs:server:dry', false, g.strain, g.quality, count))
        end)
end

local function openPacking()
    local bagsHave = exports.ox_inventory:Search('count', 'empty_weed_bag')
    chooseAndRun('mars_weed_dry', 'Pack bags', 'You have no dry buds.', Config.Processing.packMsPerItem,
        function(g) return math.min(math.floor(g.count / Config.Processing.budsPerBag), bagsHave) end,
        function(g, count, duration)
            if not progress('Packing...', duration, { dict = 'anim@amb@business@weed@weed_sorting_seated@', clip = 'sorter_right_sort_v3_sorter02' }) then return end
            notify(lib.callback.await('mars_drugs:server:pack', false, g.strain, g.quality, count))
        end)
end

local function spawnLabProp(model, fallback, c, options)
    if not loadModel(model) then
        model = fallback
        if not loadModel(model) then return end
    end
    local z = groundZ(c.x, c.y, c.z)
    local entity = CreateObject(model, c.x, c.y, z, false, false, false)
    SetEntityHeading(entity, c.w)
    PlaceObjectOnGroundProperly(entity)
    FreezeEntityPosition(entity, true)
    SetModelAsNoLongerNeeded(model)
    exports.ox_target:addLocalEntity(entity, options)
    labEntities[#labEntities + 1] = entity
end

local function spawnLab()
    spawnLabProp(Config.Props.rack, Config.Props.rackFallback, Config.Lab.rack, {
        { name = 'mars_lab_dry', icon = 'fa-solid fa-wind', label = 'Dry buds', onSelect = openDrying },
    })
    spawnLabProp(Config.Props.table, Config.Props.tableFallback, Config.Lab.table, {
        { name = 'mars_lab_pack', icon = 'fa-solid fa-box', label = 'Pack bags', onSelect = openPacking },
    })
end

local function despawnLab()
    for _, e in ipairs(labEntities) do
        exports.ox_target:removeLocalEntity(e)
        if DoesEntityExist(e) then DeleteEntity(e) end
    end
    labEntities = {}
end

-- ─────────────────────────────────────────────────────────────
-- seed shop NPC
-- ─────────────────────────────────────────────────────────────

local function spawnShopPed()
    local c = Config.Shop.coords
    if not loadModel(Config.Shop.ped) then return end
    local z = groundZ(c.x, c.y, c.z)
    shopPed = CreatePed(4, Config.Shop.ped, c.x, c.y, z, c.w, false, true)
    FreezeEntityPosition(shopPed, true)
    SetEntityInvincible(shopPed, true)
    SetBlockingOfNonTemporaryEvents(shopPed, true)
    TaskStartScenarioInPlace(shopPed, 'WORLD_HUMAN_SMOKING_POT', 0, true)
    SetModelAsNoLongerNeeded(Config.Shop.ped)
    exports.ox_target:addLocalEntity(shopPed, {
        { name = 'mars_shop', icon = 'fa-solid fa-store', label = 'Buy seeds & supplies',
          onSelect = function() exports.ox_inventory:openInventory('shop', { type = 'mars_drugs_shop' }) end },
    })
end

CreateThread(function()
    local b = Config.Shop.blip
    if b then
        local c = Config.Shop.coords
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, b.sprite); SetBlipColour(blip, b.color); SetBlipScale(blip, 0.8)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(b.label); EndTextCommandSetBlipName(blip)
    end
    if Config.Lab.blip then
        local c = Config.Lab.table
        local blip = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(blip, 496); SetBlipColour(blip, 2); SetBlipAsShortRange(blip, true)
    end
end)

-- spawn shop ped / lab props only when close
CreateThread(function()
    while true do
        local pos = GetEntityCoords(cache.ped)
        local shopNear = #(pos - Config.Shop.coords.xyz) < 80.0
        if shopNear and not shopPed then spawnShopPed()
        elseif not shopNear and shopPed then
            exports.ox_target:removeLocalEntity(shopPed)
            DeleteEntity(shopPed); shopPed = nil
        end

        local labNear = #(pos - Config.Lab.table.xyz) < 80.0
        if labNear and #labEntities == 0 then spawnLab()
        elseif not labNear and #labEntities > 0 then despawnLab() end
        Wait(2000)
    end
end)

-- ─────────────────────────────────────────────────────────────
-- selling to NPCs
-- ─────────────────────────────────────────────────────────────

local function canSellTo(entity)
    if entity == shopPed or IsPedAPlayer(entity) or IsPedDeadOrDying(entity, true) then return false end
    if IsPedInAnyVehicle(entity, false) or IsPedInAnyVehicle(cache.ped, false) then return false end
    if soldPeds[entity] then return false end
    return exports.ox_inventory:Search('count', 'mars_weed_bag') > 0
end

exports.ox_target:addGlobalPed({
    { name = 'mars_sell', icon = 'fa-solid fa-cannabis', label = 'Sell product', distance = 2.0,
      canInteract = function(entity) return canSellTo(entity) end,
      onSelect = function(data)
          local ped = data.entity
          soldPeds[ped] = true
          ClearPedTasks(ped)
          TaskTurnPedToFaceEntity(ped, cache.ped, 1500)
          TaskTurnPedToFaceEntity(cache.ped, ped, 1500)
          Wait(1000)
          FreezeEntityPosition(ped, true)
          local done = progress('Dealing...', Config.Selling.animMs, { dict = 'mp_common', clip = 'givetake1_a' })
          FreezeEntityPosition(ped, false)
          if not done then return end
          local ok, msg = lib.callback.await('mars_drugs:server:sell', false)
          notify(ok, msg)
          TaskWanderStandard(ped, 10.0, 10)
      end },
})

-- ─────────────────────────────────────────────────────────────
-- police alert
-- ─────────────────────────────────────────────────────────────

RegisterNetEvent('mars_drugs:client:policeAlert', function(coords)
    lib.notify({ title = '911 Report', description = 'A citizen reported a drug deal.', type = 'warning', duration = 8000 })
    local blip = AddBlipForRadius(coords.x + math.random(-40, 40), coords.y + math.random(-40, 40), coords.z, 80.0)
    SetBlipColour(blip, 1); SetBlipAlpha(blip, 120)
    SetTimeout(60000, function() RemoveBlip(blip) end)
end)

-- ─────────────────────────────────────────────────────────────
-- lifecycle
-- ─────────────────────────────────────────────────────────────

AddEventHandler('QBCore:Client:OnPlayerLoaded', loadPlants)
AddEventHandler('onResourceStart', function(name)
    if name == GetCurrentResourceName() then loadPlants() end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    for id in pairs(plantObjects) do deleteObject(id) end
    despawnLab()
    if shopPed then DeleteEntity(shopPed) end
end)
