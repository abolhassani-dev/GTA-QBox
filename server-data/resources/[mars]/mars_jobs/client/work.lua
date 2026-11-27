local npcs = {}        -- [key] = ped
local npcBlips = {}
local shift = nil      -- { key, vehicle, task = { spot, blip, entity }, done }

local function notify(ok, msg)
    lib.notify({ title = 'Jobs', description = msg, type = ok and 'success' or 'error' })
end

local function groundZ(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    for _ = 1, 25 do
        local found, gz = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
        if found then return gz end
        Wait(40)
    end
    return z
end

local function loadModel(model)
    if not model or not IsModelInCdimage(model) then return false end
    lib.requestModel(model, 10000)
    return true
end

-- ─────────────────────────────────────────────────────────────
-- settings sync
-- ─────────────────────────────────────────────────────────────

RegisterNetEvent('mars_jobs:client:setting', function(path, value)
    Config.SetPath(path, value)
    -- move NPCs/blips that changed position
    for key, ped in pairs(npcs) do
        if DoesEntityExist(ped) then exports.ox_target:removeLocalEntity(ped); DeleteEntity(ped) end
        npcs[key] = nil
    end
    for _, b in pairs(npcBlips) do RemoveBlip(b) end
    npcBlips = {}
    TriggerEvent('mars_jobs:client:refreshBlips')
end)

-- ─────────────────────────────────────────────────────────────
-- tasks
-- ─────────────────────────────────────────────────────────────

local function clearTask()
    if not shift or not shift.task then return end
    local t = shift.task
    if t.blip then RemoveBlip(t.blip) end
    if t.entity and DoesEntityExist(t.entity) then
        exports.ox_target:removeLocalEntity(t.entity)
        if IsEntityAPed(t.entity) then TaskWanderStandard(t.entity, 10.0, 10); SetPedAsNoLongerNeeded(t.entity)
        else DeleteEntity(t.entity) end
    end
    lib.hideTextUI()
    shift.task = nil
end

local function endShift(silent)
    if not shift then return end
    clearTask()
    if shift.vehicle and DoesEntityExist(shift.vehicle) then
        if GetVehiclePedIsIn(cache.ped, false) == shift.vehicle then TaskLeaveVehicle(cache.ped, shift.vehicle, 0); Wait(1500) end
        DeleteEntity(shift.vehicle)
    end
    shift = nil
    if not silent then notify(lib.callback.await('mars_jobs:server:stopShift', false)) end
end

local nextTask

local function doTask(spot)
    local w = Config.WorkJobs[shift.key]
    local a = w.action
    local ok = lib.progressBar({
        duration = a.ms, label = a.label, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = a.scenario and { scenario = a.scenario } or { dict = a.dict, clip = a.clip, flag = 1 },
        prop = a.prop,
    })
    if not ok or not shift then return end
    local success, msg, finished = lib.callback.await('mars_jobs:server:completeTask', false, shift.key, spot)
    notify(success, msg)
    if not success then return end
    clearTask()
    if finished then
        shift.finished = true
        notify(true, 'Go back to the job NPC to return your vehicle, or start a new shift there.')
    else
        nextTask()
    end
end

-- delivery: a customer (or a power box) on a random street spot
local function findStreetSpot(w)
    local origin = GetEntityCoords(cache.ped)
    for _ = 1, 30 do
        local angle = math.random() * math.pi * 2
        local d = w.minDistance + math.random() * (w.maxDistance - w.minDistance)
        local probe = vec3(origin.x + math.cos(angle) * d, origin.y + math.sin(angle) * d, origin.z)
        local found, node = GetClosestVehicleNode(probe.x, probe.y, probe.z, 1, 3.0, 0)
        if found then
            local ok, safe = GetSafeCoordForPed(node.x, node.y, node.z, false, 16)
            local spot = ok and safe or node
            if #(vec2(spot.x, spot.y) - vec2(origin.x, origin.y)) >= w.minDistance * 0.6 and not IsPointOnRoad(spot.x, spot.y, spot.z, 0) then
                return vec3(spot.x, spot.y, spot.z)
            end
        end
    end
end

local function startDelivery(w)
    local spot = findStreetSpot(w)
    if not spot then
        notify(false, 'No delivery found, trying again...')
        SetTimeout(3000, function() if shift then nextTask() end end)
        return
    end
    local blip = AddBlipForCoord(spot.x, spot.y, spot.z)
    SetBlipSprite(blip, 280); SetBlipColour(blip, 5); SetBlipRoute(blip, true); SetBlipRouteColour(blip, 5)
    shift.task = { spot = spot, blip = blip }
    notify(true, 'New job marked on your GPS.')

    CreateThread(function()
        local t = shift and shift.task
        while shift and shift.task == t do
            local d = #(GetEntityCoords(cache.ped) - spot)
            if d < 60.0 and not t.entity then
                local model = w.object or `a_m_y_business_01`
                if loadModel(model) then
                    local z = groundZ(spot.x, spot.y, spot.z)
                    if w.object then
                        t.entity = CreateObject(model, spot.x, spot.y, z, false, false, false)
                        PlaceObjectOnGroundProperly(t.entity)
                        FreezeEntityPosition(t.entity, true)
                    else
                        local models = { `a_m_y_business_01`, `a_f_y_tourist_01`, `a_m_m_skater_01`, `a_f_m_bevhills_02`, `a_m_y_hipster_02` }
                        model = models[math.random(#models)]
                        loadModel(model)
                        t.entity = CreatePed(4, model, spot.x, spot.y, z, math.random(0, 359) + 0.0, false, true)
                        SetBlockingOfNonTemporaryEvents(t.entity, true)
                        TaskStartScenarioInPlace(t.entity, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
                    end
                    SetModelAsNoLongerNeeded(model)
                    exports.ox_target:addLocalEntity(t.entity, {
                        { name = 'mars_job_task', icon = 'fa-solid fa-box', label = w.object and 'Repair' or 'Hand over order', distance = 2.5,
                          canInteract = function() return shift ~= nil and not IsPedInAnyVehicle(cache.ped, false) end,
                          onSelect = function() doTask(spot) end },
                    })
                end
            end
            Wait(1000)
        end
    end)
end

-- area: random spot inside the work area
local function startArea(w)
    local c = w.center
    local angle, r = math.random() * math.pi * 2, math.sqrt(math.random()) * w.radius
    local x, y = c.x + math.cos(angle) * r, c.y + math.sin(angle) * r
    local spot = vec3(x, y, groundZ(x, y, c.z))
    local blip = AddBlipForCoord(spot.x, spot.y, spot.z)
    SetBlipSprite(blip, 1); SetBlipColour(blip, 5); SetBlipScale(blip, 0.7)
    shift.task = { spot = spot, blip = blip }

    CreateThread(function()
        local t = shift and shift.task
        local shown = false
        while shift and shift.task == t do
            local pos = GetEntityCoords(cache.ped)
            local d = #(pos - spot)
            if d < 30.0 then
                DrawMarker(1, spot.x, spot.y, spot.z - 1.0, 0, 0, 0, 0, 0, 0, 1.2, 1.2, 0.6, 140, 90, 255, 150, false, false, 2, false, nil, nil, false)
                if d < 2.0 and not IsPedInAnyVehicle(cache.ped, false) then
                    if not shown then lib.showTextUI('[E] ' .. w.action.label:gsub('%.%.%.$', '')); shown = true end
                    if IsControlJustReleased(0, 38) then
                        lib.hideTextUI(); shown = false
                        doTask(spot)
                    end
                elseif shown then lib.hideTextUI(); shown = false end
                Wait(0)
            else
                if shown then lib.hideTextUI(); shown = false end
                Wait(500)
            end
        end
    end)
end

nextTask = function()
    if not shift then return end
    local w = Config.WorkJobs[shift.key]
    if w.kind == 'delivery' then startDelivery(w) else startArea(w) end
end

-- ─────────────────────────────────────────────────────────────
-- starting / ending a shift
-- ─────────────────────────────────────────────────────────────

local function spawnJobVehicle(w)
    if not loadModel(w.vehicle) then return end
    local n = w.npc
    local found, node, heading = GetClosestVehicleNodeWithHeading(n.x, n.y, n.z, 1, 3.0, 0)
    local pos = found and node or vec3(n.x, n.y, n.z)
    local veh = CreateVehicle(w.vehicle, pos.x, pos.y, pos.z + 0.5, found and heading or n.w, true, false)
    SetModelAsNoLongerNeeded(w.vehicle)
    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, ('WORK%03d'):format(math.random(0, 999)))
    Entity(veh).state:set('fuel', 100.0, true)
    lib.callback.await('mars_jobs:server:giveKeys', false, NetworkGetNetworkIdFromEntity(veh))
    SetVehicleDoorsLocked(veh, 1)
    return veh
end

local function startShift(key)
    if shift then return notify(false, 'You are already working.') end
    local ok, msg = lib.callback.await('mars_jobs:server:startShift', false, key)
    notify(ok, msg)
    if not ok then return end
    local w = Config.WorkJobs[key]
    shift = { key = key }
    if w.vehicle then
        shift.vehicle = spawnJobVehicle(w)
        if shift.vehicle then notify(true, 'Your work vehicle is waiting on the road.') end
    end
    nextTask()
end

-- ─────────────────────────────────────────────────────────────
-- job NPCs and blips
-- ─────────────────────────────────────────────────────────────

local function spawnNpc(key, w)
    if not loadModel(Config.NpcModel) then return end
    local n = w.npc
    local ped = CreatePed(4, Config.NpcModel, n.x, n.y, groundZ(n.x, n.y, n.z), n.w, false, true)
    FreezeEntityPosition(ped, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    exports.ox_target:addLocalEntity(ped, {
        { name = 'mars_job_start', icon = 'fa-solid fa-briefcase', label = ('Start shift – %s'):format(w.label),
          canInteract = function() return shift == nil end, onSelect = function() startShift(key) end },
        { name = 'mars_job_stop', icon = 'fa-solid fa-door-open', label = 'End shift / return vehicle',
          canInteract = function() return shift ~= nil and shift.key == key end, onSelect = function() endShift(false) end },
        { name = 'mars_job_info', icon = 'fa-solid fa-circle-info', label = 'Job info',
          onSelect = function()
              lib.alertDialog({ header = w.label, centered = true, content = ('Pay: $%d per task  \nBonus: $%d after %d tasks  \n%s'):format(
                  w.pay, w.bonus, w.tasksPerShift,
                  w.kind == 'delivery' and 'Drive to the GPS mark and hand over the order.' or 'Walk to the marked spots in the area and press E.') })
          end },
    })
    npcs[key] = ped
end

local function refreshBlips()
    for _, b in pairs(npcBlips) do RemoveBlip(b) end
    npcBlips = {}
    for key, w in pairs(Config.WorkJobs) do
        local b = AddBlipForCoord(w.npc.x, w.npc.y, w.npc.z)
        SetBlipSprite(b, w.blip.sprite); SetBlipColour(b, w.blip.color); SetBlipScale(b, 0.7); SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(w.label); EndTextCommandSetBlipName(b)
        npcBlips[key] = b
    end
end
AddEventHandler('mars_jobs:client:refreshBlips', refreshBlips)

CreateThread(function()
    local overrides = lib.callback.await('mars_jobs:server:getSettings', false) or {}
    for path, v in pairs(overrides) do Config.SetPath(path, v) end
    refreshBlips()
    while true do
        local pos = GetEntityCoords(cache.ped)
        for key, w in pairs(Config.WorkJobs) do
            local near = #(pos - w.npc.xyz) < 70.0
            if near and not npcs[key] then spawnNpc(key, w)
            elseif not near and npcs[key] then
                exports.ox_target:removeLocalEntity(npcs[key]); DeleteEntity(npcs[key]); npcs[key] = nil
            end
        end
        Wait(2000)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    endShift(true)
    for _, ped in pairs(npcs) do if DoesEntityExist(ped) then DeleteEntity(ped) end end
end)
