-- Drug effects: smoked / eaten / snorted. Effects fade in, peak, then fade out
-- so they feel natural, and they scale with product quality.

local active = nil  -- currently running effect

local consumeAnims = {
    weed   = { label = 'Smoking...',  ms = 6000, anim = { dict = 'amb@world_human_smoking@male@male_a@enter', clip = 'enter' },
               prop = { model = `prop_sh_joint_01`, bone = 47419, pos = vec3(0.015, -0.009, 0.003), rot = vec3(55.0, 0.0, 110.0) } },
    shroom = { label = 'Eating mushrooms...', ms = 4000, anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger' } },
    coca   = { label = 'Snorting...', ms = 3500, anim = { dict = 'anim@mp_player_intcelebrationmale@face_palm', clip = 'face_palm' } },
}

local function lerp(a, b, t) return a + (b - a) * t end

local function stopEffect(immediate)
    if not active then return end
    local e = active
    active = nil
    local ped = cache.ped

    if not immediate then
        -- fade out over 6 seconds
        for i = 10, 0, -1 do
            if e.timecycle then SetTimecycleModifierStrength(e.timecycleStrength * i / 10) end
            if e.shake then SetGameplayCamShakeAmplitude(e.shakeAmp * i / 10) end
            Wait(600)
        end
    end

    if e.postfx then AnimpostfxStop(e.postfx) end
    ClearTimecycleModifier()
    StopGameplayCamShaking(true)
    ResetPedMovementClipset(ped, 1.0)
    SetRunSprintMultiplierForPlayer(cache.playerId, 1.0)
    SetPedMotionBlur(ped, false)
    if e.postfx then AnimpostfxPlay('DrugsDrivingOut', 2000, false) end
end

local function startEffect(def, mult, durationSec)
    local ped = cache.ped
    local e = {
        postfx = def.postfx,
        timecycle = def.timecycle,
        timecycleStrength = math.min(1.0, (def.timecycleStrength or 0.4) * mult),
        shake = def.shake,
        shakeAmp = (def.shakeAmp or 0.3) * mult,
        endsAt = GetGameTimer() + durationSec * 1000,
    }
    active = e

    -- come-up: fade in over ~8 seconds
    if def.walk then
        lib.requestAnimSet(def.walk, 5000)
        SetPedMovementClipset(ped, def.walk, 1.0)
    end
    if e.postfx then AnimpostfxPlay(e.postfx, 0, true) end
    if e.timecycle then SetTimecycleModifier(e.timecycle) end
    if e.shake then ShakeGameplayCam(e.shake, 0.0) end
    SetPedMotionBlur(ped, true)

    for i = 1, 16 do
        if active ~= e then return end
        local t = i / 16
        if e.timecycle then SetTimecycleModifierStrength(lerp(0.0, e.timecycleStrength, t)) end
        if e.shake then SetGameplayCamShakeAmplitude(lerp(0.0, e.shakeAmp, t)) end
        Wait(500)
    end

    -- the high
    if def.runSpeed and def.runSpeed ~= 1.0 then
        SetRunSprintMultiplierForPlayer(cache.playerId, math.min(1.49, 1.0 + (def.runSpeed - 1.0) * mult))
    end

    CreateThread(function()
        while active == e and GetGameTimer() < e.endsAt do
            if def.stamina then RestorePlayerStamina(cache.playerId, 1.0) end
            -- small waves in intensity feel more natural than a flat filter
            local wave = 0.85 + math.sin(GetGameTimer() / 1800) * 0.15
            if e.timecycle then SetTimecycleModifierStrength(e.timecycleStrength * wave) end
            if e.shake then SetGameplayCamShakeAmplitude(e.shakeAmp * wave) end

            -- mushrooms: the world sometimes shifts colours and peds look strange
            if def.hallucinate and math.random(1000) <= 6 then
                AnimpostfxPlay('DrugsMichaelAliensFight', 3000, false)
            end
            Wait(250)
        end
        if active == e then stopEffect(false) end
    end)
end

local function overdose()
    local ped = cache.ped
    lib.notify({ title = 'Mars', description = 'You took too much...', type = 'error', duration = 6000 })
    AnimpostfxPlay('DeathFailOut', 0, true)
    ShakeGameplayCam('DRUNK_SHAKE', 2.0)
    SetPedToRagdoll(ped, 8000, 8000, 0, false, false, false)
    SetEntityHealth(ped, math.max(101, GetEntityHealth(ped) - Config.Overdose.damage))
    Wait(8000)
    AnimpostfxStop('DeathFailOut')
    StopGameplayCamShaking(true)
end

RegisterNetEvent('mars_drugs:client:consume', function(data)
    local def = Config.Effects[data.effect]
    if not def then return end
    local q = Config.QualityByKey(data.quality) or { effectMult = 1.0 }
    local mult = (q.effectMult or 1.0) * (def.intensity or 1.0)
    local duration = math.floor((def.duration or 60) * (q.effectMult or 1.0))

    local a = consumeAnims[data.category]
    if a then
        local ok = lib.progressBar({
            duration = a.ms, label = a.label, canCancel = false,
            disable = { car = false, combat = true }, anim = a.anim, prop = a.prop,
        })
        if not ok then return end
    end

    local ped = cache.ped
    -- immediate body effects
    if def.cough and math.random(100) <= 40 then
        lib.requestAnimDict('timetable@gardener@smoking_joint', 3000)
        TaskPlayAnim(ped, 'timetable@gardener@smoking_joint', 'idle_cough', 8.0, -8.0, 2500, 48, 0, false, false, false)
    end
    if def.armor and def.armor > 0 then AddArmourToPed(ped, math.floor(def.armor * mult)) end
    if def.health and def.health > 0 then
        SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + math.floor(def.health * mult)))
    end
    if def.stress and def.stress > 0 then
        TriggerServerEvent('hud:server:RelieveStress', math.floor(def.stress * mult))
    end

    lib.notify({ title = def.label, description = ('%s • %s quality'):format(Config.Strains[data.strain] and Config.Strains[data.strain].label or '', q.label or ''), type = 'inform' })

    if active then
        -- stacking: extend the current effect instead of restarting it
        active.endsAt = active.endsAt + duration * 500
    else
        startEffect(def, mult, duration)
    end

    if data.overdose then overdose() end
end)

-- dying or respawning clears everything
AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' and args[1] == cache.ped and IsEntityDead(cache.ped) then
        stopEffect(true)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() then stopEffect(true) end
end)
