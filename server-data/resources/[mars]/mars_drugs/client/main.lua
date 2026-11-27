local plants = {}       -- [id] = plant (from server)
local plantObjects = {} -- [id] = { entity, model, dead }
local labEntities = {}
local labSnapped = false
local shopSnapped = false
local shopPed
local soldPeds = {}

-- ─────────────────────────────────────────────────────────────
-- helpers
-- ─────────────────────────────────────────────────────────────

local function notify(ok, msg)
    lib.notify({ title = 'Mars', description = msg, type = ok and 'success' or 'error' })
end

local function loadModel(model)
    if not model or not IsModelInCdimage(model) then return false end
    lib.requestModel(model, 10000)
    return true
end

local function groundZ(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    for _ = 1, 25 do
        -- look just above first (so roofs/trees are ignored), then from high up
        local found, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
        if found then return gz end
        found, gz = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
        if found then return gz end
        Wait(40)
    end
    return z
end

-- re-place an entity on the real ground once its collision is loaded
local function snapToGround(entity, isPed)
    if not DoesEntityExist(entity) then return end
    local c = GetEntityCoords(entity)
    local z = groundZ(c.x, c.y, c.z)
    FreezeEntityPosition(entity, false)
    SetEntityCoordsNoOffset(entity, c.x, c.y, z, false, false, false)
    if not isPed then PlaceObjectOnGroundProperly(entity) end
    FreezeEntityPosition(entity, true)
end

local function modelFor(p)
    local cat = Config.CategoryOf(p.strain)
    local stage = p.growth < 33 and 1 or (p.growth < 66 and 2 or 3)
    local model = cat and cat.props and cat.props[stage]
    if model and IsModelInCdimage(model) then return model end
    return Config.FallbackProps[stage]
end

local function progress(label, duration, anim, prop)
    -- a missing animation must never stop the action itself
    if anim and anim.dict and not DoesAnimDictExist(anim.dict) then anim = nil end
    local ok, result = pcall(lib.progressBar, {
        duration = duration, label = label, useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = anim, prop = prop,
    })
    if ok then return result end
    print(('[mars_drugs] progress bar error: %s'):format(result))
    return lib.progressBar({ duration = duration, label = label, canCancel = true, disable = { move = true, car = true, combat = true } })
end

local function strainLabel(key)
    return Config.Strains[key] and Config.Strains[key].label or key
end

-- ─────────────────────────────────────────────────────────────
-- settings sync (edited in game with /drugadmin)
-- ─────────────────────────────────────────────────────────────

RegisterNetEvent('mars_drugs:client:setting', function(path, value)
    Config.SetPath(path, value)
    if path:match('^Lab%.') or path:match('^Shop%.coords') then
        TriggerEvent('mars_drugs:client:respawnPlaces')
    end
end)

local function loadSettings()
    local overrides = lib.callback.await('mars_drugs:server:getSettings', false) or {}
    for path, value in pairs(overrides) do Config.SetPath(path, value) end
end

-- ─────────────────────────────────────────────────────────────
-- plant status menu
-- ─────────────────────────────────────────────────────────────

local function showStatus(id)
    local p = plants[id]
    if not p then return end
    local s = Config.Strains[p.strain] or {}
    local cat = Config.CategoryOf(p.strain)
    local q = Config.QualityFor(p.score)

    lib.registerContext({
        id = 'mars_drugs_plant',
        title = ('%s  •  %s'):format(strainLabel(p.strain), s.type or ''),
        options = {
            { title = p.dead and 'Status: dead ☠️' or ('Growth: %d%%'):format(math.floor(p.growth)), progress = p.growth, colorScheme = 'green', readOnly = true },
            { title = ('Water: %d%%'):format(math.floor(p.water)), progress = p.water, colorScheme = 'blue', readOnly = true },
            { title = ('Fertilizer: %d%%'):format(math.floor(p.food)), progress = p.food, colorScheme = 'yellow', readOnly = true },
            { title = ('Health: %d%%'):format(math.floor(p.health)), progress = p.health, colorScheme = p.health > 50 and 'green' or 'red', readOnly = true },
            { title = ('Current quality: %s'):format(q.label), description = 'Better care means higher quality.', readOnly = true },
            { title = ('Type: %s'):format(cat and cat.label or '?'),
              description = ('Growth speed x%.2f  •  Harvest x%.2f  •  Water need x%.2f'):format(s.growthMult or 1, s.yieldMult or 1, s.thirst or 1),
              readOnly = true },
        },
    })
    lib.showContext('mars_drugs_plant')
end

-- ─────────────────────────────────────────────────────────────
-- plant actions
-- ─────────────────────────────────────────────────────────────

local gardenAnim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base' }

local function doWater(id)
    if exports.ox_inventory:Search('count', 'water') < 1 then return notify(false, 'You have no water.') end
    if not progress('Watering...', 3500, { dict = 'weapon@w_sp_jerrycan', clip = 'fire' }) then return end
    notify(lib.callback.await('mars_drugs:server:water', false, id))
end

local function doFeed(id)
    if exports.ox_inventory:Search('count', 'weed_nutrition') < 1 then return notify(false, 'You have no fertilizer.') end
    if not progress('Fertilizing...', 3500, gardenAnim) then return end
    notify(lib.callback.await('mars_drugs:server:feed', false, id))
end

local function doHarvest(id)
    if not progress('Harvesting...', 7000, gardenAnim) then return end
    notify(lib.callback.await('mars_drugs:server:harvest', false, id))
end

local function doDestroy(id)
    local confirm = lib.alertDialog({ header = 'Destroy plant', content = 'Are you sure?', centered = true, cancel = true })
    if confirm ~= 'confirm' then return end
    if not progress('Destroying...', 4000, gardenAnim) then return end
    notify(lib.callback.await('mars_drugs:server:destroy', false, id))
end

local function plantTargetOptions(id)
    local growing = function() local p = plants[id] return p and not p.dead and p.growth < 100 end
    return {
        { name = 'mars_plant_status', icon = 'fa-solid fa-seedling', label = 'Plant status', onSelect = function() showStatus(id) end },
        { name = 'mars_plant_water', icon = 'fa-solid fa-droplet', label = 'Water', canInteract = growing, onSelect = function() doWater(id) end },
        { name = 'mars_plant_feed', icon = 'fa-solid fa-flask', label = 'Fertilize', canInteract = growing, onSelect = function() doFeed(id) end },
        { name = 'mars_plant_harvest', icon = 'fa-solid fa-hand-scissors', label = 'Harvest',
          canInteract = function() local p = plants[id] return p and not p.dead and p.growth >= 100 end,
          onSelect = function() doHarvest(id) end },
        { name = 'mars_plant_destroy', icon = 'fa-solid fa-fire', label = 'Destroy', onSelect = function() doDestroy(id) end },
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
    local model = modelFor(p)
    if not loadModel(model) then return end
    local z = groundZ(p.coords.x, p.coords.y, p.coords.z)
    local entity = CreateObject(model, p.coords.x, p.coords.y, z, false, false, false)
    PlaceObjectOnGroundProperly(entity)
    FreezeEntityPosition(entity, true)
    SetEntityAsMissionEntity(entity, true, true)
    if p.dead then SetEntityAlpha(entity, 140, false) end
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
                if obj and (obj.model ~= modelFor(p) or obj.dead ~= p.dead) then
                    deleteObject(id); obj = nil
                end
                if not obj then spawnObject(p) end
            elseif obj then
                deleteObject(id)
            end
        end
        Wait(1000)
    end
end)

-- live status floating above plants within a few metres
local function draw3d(x, y, z, text)
    SetTextScale(0.32, 0.32); SetTextFont(4); SetTextColour(255, 255, 255, 230)
    SetTextOutline(); SetTextCentre(true)
    SetDrawOrigin(x, y, z, 0)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(0.0, 0.0)
    ClearDrawOrigin()
end

CreateThread(function()
    while true do
        local pos, any = GetEntityCoords(cache.ped), false
        for id, p in pairs(plants) do
            local obj = plantObjects[id]
            if obj and #(pos - p.coords) < 6.0 then
                any = true
                local c = GetEntityCoords(obj.entity)
                local status
                if p.dead then status = '~r~Dead'
                elseif p.growth >= 100 then status = '~g~Ready to harvest'
                else
                    local g = math.min(99.9, p.growth + (p.rate or 0) * (GetGameTimer() - (p.syncedAt or 0)))
                    status = ('Growth ~g~%.1f%%~s~  |  Water ~b~%d%%~s~  |  Food ~y~%d%%'):format(g, math.floor(p.water), math.floor(p.food))
                end
                draw3d(c.x, c.y, c.z + 1.2, ('%s~n~%s'):format(strainLabel(p.strain), status))
            end
        end
        Wait(any and 0 or 500)
    end
end)

local function setPlant(p)
    p.coords = vec3(p.coords.x, p.coords.y, p.coords.z)
    local old, now = plants[p.id], GetGameTimer()
    -- remember how fast it grows, so the text can count up smoothly between updates
    if old and old.syncedAt and p.growth > old.growth then
        p.rate = (p.growth - old.growth) / math.max(1, now - old.syncedAt)
    else
        p.rate = old and old.rate or 0
    end
    if p.dead or p.growth >= 100 then p.rate = 0 end
    p.syncedAt = now
    plants[p.id] = p
end

RegisterNetEvent('mars_drugs:client:plantUpdated', function(p) setPlant(p) end)
RegisterNetEvent('mars_drugs:client:plantRemoved', function(id)
    plants[id] = nil
    deleteObject(id)
end)

local function loadPlants()
    loadSettings()
    for _, p in ipairs(lib.callback.await('mars_drugs:server:getPlants', false) or {}) do setPlant(p) end
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
    if not progress(('Planting %s...'):format(strainLabel(strain)), Config.PlantAnimMs, gardenAnim) then return end
    notify(lib.callback.await('mars_drugs:server:plant', false, strain, slot, vec3(spot.x, spot.y, z)))
end)

-- ─────────────────────────────────────────────────────────────
-- lab: drying rack and table
-- ─────────────────────────────────────────────────────────────

-- groups the player's items by strain + quality
local function groupItems(itemName)
    local groups = {}
    for _, slot in pairs(exports.ox_inventory:Search('slots', itemName) or {}) do
        local m = slot.metadata or {}
        if m.strain and m.quality then
            local key = m.strain .. ':' .. m.quality
            groups[key] = groups[key] or { strain = m.strain, quality = m.quality, count = 0, item = itemName }
            groups[key].count = groups[key].count + slot.count
        end
    end
    return groups
end

local function askAmount(title, max)
    local input = lib.inputDialog(title, { { type = 'number', label = 'Amount', default = max, min = 1, max = max, required = true } })
    return input and math.floor(input[1])
end

local function qualityLabel(key)
    local q = Config.QualityByKey(key)
    return q and q.label or key
end

local function openDrying()
    local options = {}
    for _, cat in pairs(Config.Categories) do
        if cat.dried then
            for _, g in pairs(groupItems(cat.harvest)) do
                options[#options + 1] = {
                    title = ('%s – %s'):format(strainLabel(g.strain), qualityLabel(g.quality)),
                    description = ('%s  •  you have %d'):format(cat.label, g.count),
                    icon = 'fa-solid fa-wind',
                    onSelect = function()
                        local count = askAmount('Dry', g.count)
                        if not count then return end
                        local duration = math.min(Config.Processing.maxMs, Config.Processing.dryMsPerItem * count)
                        if not progress('Hanging on the rack...', duration, { dict = 'amb@prop_human_bum_bin@base', clip = 'base' }) then return end
                        notify(lib.callback.await('mars_drugs:server:dry', false, g.strain, g.quality, count))
                    end,
                }
            end
        end
    end
    if #options == 0 then return notify(false, 'You have nothing to dry.') end
    lib.registerContext({ id = 'mars_drugs_dry', title = 'Drying rack', options = options })
    lib.showContext('mars_drugs_dry')
end

local function openTable()
    local options = {}
    local bags = exports.ox_inventory:Search('count', 'empty_weed_bag')
    local papers = exports.ox_inventory:Search('count', 'rolling_paper')
    local sortAnim = { dict = 'mini@repair', clip = 'fixing_a_ped' }

    for catKey, cat in pairs(Config.Categories) do
        local input = cat.dried or cat.harvest
        for _, g in pairs(groupItems(input)) do
            local maxProducts = math.min(math.floor(g.count / cat.perProduct), bags)
            if cat.extra then
                maxProducts = math.min(maxProducts, math.floor(exports.ox_inventory:Search('count', cat.extra.item) / cat.extra.count))
            end
            options[#options + 1] = {
                title = ('Pack %s – %s'):format(strainLabel(g.strain), qualityLabel(g.quality)),
                description = ('%d units + 1 bag%s each  •  you can make %d'):format(cat.perProduct, cat.extra and ' + chemicals' or '', maxProducts),
                icon = 'fa-solid fa-box', disabled = maxProducts < 1,
                onSelect = function()
                    local count = askAmount('Pack', maxProducts)
                    if not count then return end
                    local duration = math.min(Config.Processing.maxMs, Config.Processing.packMsPerItem * count)
                    if not progress('Packing...', duration, sortAnim) then return end
                    notify(lib.callback.await('mars_drugs:server:pack', false, g.strain, g.quality, count))
                end,
            }
            if catKey == 'weed' then
                local maxBuds = math.min(g.count, papers)
                options[#options + 1] = {
                    title = ('Roll joints – %s %s'):format(strainLabel(g.strain), qualityLabel(g.quality)),
                    description = ('1 bud + 1 rolling paper = %d joints'):format(Config.Processing.jointsPerBud),
                    icon = 'fa-solid fa-joint', disabled = maxBuds < 1,
                    onSelect = function()
                        local count = askAmount('Buds to roll', maxBuds)
                        if not count then return end
                        local duration = math.min(Config.Processing.maxMs, Config.Processing.rollMsPerItem * count)
                        if not progress('Rolling joints...', duration, sortAnim) then return end
                        notify(lib.callback.await('mars_drugs:server:roll', false, g.strain, g.quality, count))
                    end,
                }
            end
        end
    end
    -- fresh harvest that still has to go on the drying rack: say so instead of "nothing"
    for _, cat in pairs(Config.Categories) do
        if cat.dried then
            for _, g in pairs(groupItems(cat.harvest)) do
                options[#options + 1] = {
                    title = ('%s – %s (fresh, %d)'):format(strainLabel(g.strain), qualityLabel(g.quality), g.count),
                    description = 'Dry it on the drying rack first, then come back to pack or roll it.',
                    icon = 'fa-solid fa-wind', disabled = true,
                }
            end
        end
    end
    if #options == 0 then return notify(false, 'You have nothing to process. Harvest a plant first.') end
    lib.registerContext({ id = 'mars_drugs_table', title = 'Processing table', options = options })
    lib.showContext('mars_drugs_table')
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
    labSnapped = false
end

local function spawnLab()
    spawnLabProp(Config.Props.rack, Config.Props.rackFallback, Config.Lab.rack, {
        { name = 'mars_lab_dry', icon = 'fa-solid fa-wind', label = 'Drying rack', onSelect = openDrying },
    })
    spawnLabProp(Config.Props.table, Config.Props.tableFallback, Config.Lab.table, {
        { name = 'mars_lab_table', icon = 'fa-solid fa-box', label = 'Processing table', onSelect = openTable },
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

local function openSeedShop()
    local list = lib.callback.await('mars_drugs:server:shopList', false) or {}
    local options = {}
    for i, it in ipairs(list) do
        options[#options + 1] = {
            title = ('%s  –  $%d'):format(it.label, it.price), description = it.description,
            icon = it.seed and 'fa-solid fa-seedling' or 'fa-solid fa-box',
            image = ('nui://ox_inventory/web/images/%s.png'):format(it.image or it.name),
            onSelect = function()
                local input = lib.inputDialog(it.label, {
                    { type = 'number', label = ('Amount ($%d each)'):format(it.price), default = 1, min = 1, max = 50, required = true },
                })
                if input then notify(lib.callback.await('mars_drugs:server:shopBuy', false, i, input[1])) end
                openSeedShop()
            end,
        }
    end
    lib.registerContext({ id = 'mars_drugs_shop', title = Config.Shop.blip.label, options = options })
    lib.showContext('mars_drugs_shop')
end

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
          onSelect = function() openSeedShop() end },
    })
    shopSnapped = false
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
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName('Drug Lab'); EndTextCommandSetBlipName(blip)
    end
end)

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

        if shopPed and not shopSnapped and #(pos - Config.Shop.coords.xyz) < 30.0 then
            snapToGround(shopPed, true); shopSnapped = true
        end
        if #labEntities > 0 and not labSnapped and #(pos - Config.Lab.table.xyz) < 30.0 then
            for _, e in ipairs(labEntities) do snapToGround(e, false) end
            labSnapped = true
        end
        Wait(1000)
    end
end)

-- ─────────────────────────────────────────────────────────────
-- selling to NPCs
-- ─────────────────────────────────────────────────────────────

-- ped types that never buy: 6 cop, 27 swat, 28 animal, 29 army
local noBuyerTypes = { [6] = true, [27] = true, [28] = true, [29] = true }

local function hasSellable()
    local seen = {}
    for _, cat in pairs(Config.Categories) do
        if not seen[cat.product] then
            seen[cat.product] = true
            if exports.ox_inventory:Search('count', cat.product) > 0 then return true end
        end
    end
    return exports.ox_inventory:Search('count', 'mars_joint') > 0
end

exports.ox_target:addGlobalPed({
    { name = 'mars_sell', icon = 'fa-solid fa-cannabis', label = 'Sell product', distance = 2.0,
      canInteract = function(entity)
          if entity == shopPed or IsPedAPlayer(entity) or IsPedDeadOrDying(entity, true) then return false end
          -- only ordinary people walking around: no animals, no cops/army, no script NPCs (shops, jobs)
          if not IsPedHuman(entity) or noBuyerTypes[GetPedType(entity)] then return false end
          local pop = GetEntityPopulationType(entity)
          if pop < 1 or pop > 5 then return false end
          if IsPedInAnyVehicle(entity, false) or IsPedInAnyVehicle(cache.ped, false) or soldPeds[entity] then return false end
          return hasSellable()
      end,
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
          notify(lib.callback.await('mars_drugs:server:sell', false))
          TaskWanderStandard(ped, 10.0, 10)
      end },
})

RegisterNetEvent('mars_drugs:client:policeAlert', function(coords)
    lib.notify({ title = '911 Report', description = 'A citizen reported a drug deal.', type = 'warning', duration = 8000 })
    local blip = AddBlipForRadius(coords.x + math.random(-40, 40), coords.y + math.random(-40, 40), coords.z, 80.0)
    SetBlipColour(blip, 1); SetBlipAlpha(blip, 120)
    SetTimeout(60000, function() RemoveBlip(blip) end)
end)

-- ─────────────────────────────────────────────────────────────
-- lifecycle
-- ─────────────────────────────────────────────────────────────

AddEventHandler('mars_drugs:client:respawnPlaces', function()
    despawnLab()
    if shopPed then exports.ox_target:removeLocalEntity(shopPed); DeleteEntity(shopPed); shopPed = nil end
end)

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

print(('^2[mars_drugs] client version %s loaded^0'):format(GetResourceMetadata(GetCurrentResourceName(), 'version', 0)))
