local overrides, defaults = {}, {}     -- work job settings edited in game
local customJobs = {}                  -- [name] = job table saved from the panel
local builtinJobs = {}                 -- job names that existed before Mars added any
local shifts = {}                      -- [source] = active work shift

-- ─────────────────────────────────────────────────────────────
-- helpers
-- ─────────────────────────────────────────────────────────────

local function notify(src, msg, kind)
    TriggerClientEvent('ox_lib:notify', src, { title = 'Jobs', description = msg, type = kind or 'inform' })
end

local function isAdmin(src) return IsPlayerAceAllowed(src, 'admin') end
local function getPlayer(src) return exports.qbx_core:GetPlayer(src) end
local function pedCoords(src) return GetEntityCoords(GetPlayerPed(src)) end

local function dist2d(a, b) return #(vec2(a.x, a.y) - vec2(b.x, b.y)) end

local function toPlain(v)
    local t = type(v)
    if t == 'vector4' then return { x = v.x, y = v.y, z = v.z, w = v.w } end
    if t == 'vector3' then return { x = v.x, y = v.y, z = v.z } end
    return v
end

-- grades use integer keys; JSON needs string keys and back
local function gradesToJson(job)
    local copy = {}
    for k, v in pairs(job) do copy[k] = v end
    copy.grades = {}
    for g, data in pairs(job.grades or {}) do copy.grades[tostring(g)] = data end
    return json.encode(copy)
end

local function jobFromJson(text)
    local job = json.decode(text)
    if not job then return end
    local grades = {}
    for g, data in pairs(job.grades or {}) do grades[tonumber(g)] = data end
    job.grades = grades
    return job
end

local function applyOverride(path, value)
    if defaults[path] == nil then defaults[path] = Config.GetPath(path) end
    if Config.SetPath(path, value) then
        overrides[path] = Config.GetPath(path)
        return true
    end
end

-- ─────────────────────────────────────────────────────────────
-- startup: database, work jobs in qbx_core, custom jobs
-- ─────────────────────────────────────────────────────────────

MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `mars_jobs_custom` (
        `name` VARCHAR(50) NOT NULL, `data` LONGTEXT NOT NULL, PRIMARY KEY (`name`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `mars_jobs_settings` (
        `path` VARCHAR(100) NOT NULL, `value` VARCHAR(255) NOT NULL, PRIMARY KEY (`path`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    for _, r in ipairs(MySQL.query.await('SELECT * FROM mars_jobs_settings') or {}) do
        local v = json.decode(r.value)
        if v ~= nil then applyOverride(r.path, v) end
    end

    for name in pairs(exports.qbx_core:GetJobs()) do builtinJobs[name] = true end

    -- work jobs must exist in qbx_core (vineyard already does; keep its grades)
    local newJobs = {}
    for key, w in pairs(Config.WorkJobs) do
        if not exports.qbx_core:GetJob(key) then
            newJobs[key] = { label = w.label, defaultDuty = true, offDutyPay = false, grades = { [0] = { name = 'Worker', payment = 10 } } }
        end
    end
    if next(newJobs) then exports.qbx_core:CreateJobs(newJobs) end

    -- jobs created or edited in /jobadmin
    for _, r in ipairs(MySQL.query.await('SELECT * FROM mars_jobs_custom') or {}) do
        local job = jobFromJson(r.data)
        if job then
            customJobs[r.name] = job
            local ok, err = exports.qbx_core:CreateJob(r.name, job)
            if not ok then print(('^1[mars_jobs] could not load job %s: %s^0'):format(r.name, err)) end
        end
    end
    print(('[mars_jobs] %d work jobs, %d custom/edited jobs'):format(#Config.WorkOrder, (function() local n = 0 for _ in pairs(customJobs) do n = n + 1 end return n end)()))
end)

lib.callback.register('mars_jobs:server:getSettings', function()
    local plain = {}
    for path, v in pairs(overrides) do plain[path] = toPlain(v) end
    return plain
end)

-- ─────────────────────────────────────────────────────────────
-- work shifts
-- ─────────────────────────────────────────────────────────────

lib.callback.register('mars_jobs:server:startShift', function(src, key)
    local w = Config.WorkJobs[key]
    local player = getPlayer(src)
    if not w or not player then return false, 'Unknown job.' end
    if player.PlayerData.job.name ~= key then
        return false, ('You need the %s job. Get it at City Hall.'):format(w.label)
    end
    if dist2d(pedCoords(src), w.npc) > 15.0 then return false, 'You are too far away.' end
    shifts[src] = { key = key, done = 0, lastAt = 0, lastPos = pedCoords(src) }
    return true, ('Shift started: %d tasks, $%d each, $%d bonus at the end.'):format(w.tasksPerShift, w.pay, w.bonus)
end)

lib.callback.register('mars_jobs:server:stopShift', function(src)
    local s = shifts[src]
    shifts[src] = nil
    if not s then return false, 'You are not working.' end
    return true, ('Shift ended. Tasks done: %d.'):format(s.done)
end)

lib.callback.register('mars_jobs:server:completeTask', function(src, key, spot)
    local s = shifts[src]
    local w = Config.WorkJobs[key]
    if not s or s.key ~= key or not w or type(spot) ~= 'vector3' then return false, 'You are not working.' end

    local now = os.time()
    local here = pedCoords(src)
    if dist2d(here, spot) > Config.MaxTaskDistance then return false, 'You are too far from the job spot.' end
    if now - s.lastAt < Config.MinSecondsPerTask then return false, 'Too fast... take your time.' end
    if w.kind == 'delivery' and dist2d(here, s.lastPos) < (w.minDistance * 0.5) then
        return false, 'This delivery is too close to the last one.'
    end

    s.done = s.done + 1
    s.lastAt, s.lastPos = now, here
    local player = getPlayer(src)
    local pay = w.pay
    local msg = ('+$%d (%d/%d)'):format(pay, s.done, w.tasksPerShift)
    if s.done >= w.tasksPerShift then
        pay = pay + w.bonus
        msg = ('Shift complete! +$%d including $%d bonus. Return to the NPC or start a new shift.'):format(pay, w.bonus)
        shifts[src] = nil
    end
    player.Functions.AddMoney(Config.PayTo, pay, ('mars-job-%s'):format(key))
    return true, msg, shifts[src] == nil
end)

lib.callback.register('mars_jobs:server:giveKeys', function(src, netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh == 0 or not shifts[src] then return false end
    pcall(function() exports.qbx_vehiclekeys:GiveKeys(src, veh) end)
    return true
end)

AddEventHandler('playerDropped', function() shifts[source] = nil end)

-- ─────────────────────────────────────────────────────────────
-- admin panel
-- ─────────────────────────────────────────────────────────────

local function charName(player)
    local c = player.PlayerData.charinfo or {}
    return ('%s %s'):format(c.firstname or '?', c.lastname or '')
end

lib.callback.register('mars_jobs:admin:players', function(src)
    if not isAdmin(src) then return end
    local list = {}
    for _, id in ipairs(GetPlayers()) do
        local p = getPlayer(tonumber(id))
        if p then
            local j = p.PlayerData.job
            list[#list + 1] = {
                id = tonumber(id), name = GetPlayerName(id), char = charName(p), citizenid = p.PlayerData.citizenid,
                job = j.name, jobLabel = j.label, grade = j.grade and j.grade.level or 0,
                gradeName = j.grade and j.grade.name or '', onduty = j.onduty,
            }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)

lib.callback.register('mars_jobs:admin:jobs', function(src)
    if not isAdmin(src) then return end
    local out = {}
    for name, job in pairs(exports.qbx_core:GetJobs()) do
        local grades = {}
        for g, data in pairs(job.grades or {}) do
            grades[#grades + 1] = { level = g, name = data.name, payment = data.payment or 0, isboss = data.isboss == true }
        end
        table.sort(grades, function(a, b) return a.level < b.level end)
        out[#out + 1] = {
            name = name, label = job.label, type = job.type, grades = grades,
            custom = customJobs[name] ~= nil, builtin = builtinJobs[name] == true,
            protected = Config.ProtectedJobs[name] == true, work = Config.WorkJobs[name] ~= nil,
        }
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end)

lib.callback.register('mars_jobs:admin:setJob', function(src, target, job, grade)
    if not isAdmin(src) then return false, 'No permission.' end
    target, grade = tonumber(target), tonumber(grade) or 0
    if not target or not getPlayer(target) then return false, 'Player not online.' end
    local ok, err = exports.qbx_core:SetJob(target, job, grade)
    if not ok then return false, ('Failed: %s'):format(err or 'unknown error') end
    notify(target, ('Your job is now %s (grade %d).'):format(job, grade), 'success')
    return true, 'Job set.'
end)

lib.callback.register('mars_jobs:admin:setDuty', function(src, target, onduty)
    if not isAdmin(src) then return false, 'No permission.' end
    target = tonumber(target)
    if not target or not getPlayer(target) then return false, 'Player not online.' end
    exports.qbx_core:SetJobDuty(target, onduty == true)
    return true, onduty and 'Now on duty.' or 'Now off duty.'
end)

local function validName(name)
    return type(name) == 'string' and name:match('^[a-z][a-z0-9_]*$') and #name <= 40
end

-- create or replace a whole job definition (label, type, grades)
lib.callback.register('mars_jobs:admin:saveJob', function(src, name, job)
    if not isAdmin(src) then return false, 'No permission.' end
    if not validName(name) then return false, 'Job id must be lowercase letters, numbers or _.' end
    if type(job) ~= 'table' or type(job.label) ~= 'string' or job.label == '' then return false, 'Invalid job.' end

    local grades = {}
    for g, data in pairs(job.grades or {}) do
        local level = tonumber(g)
        if level and type(data) == 'table' and type(data.name) == 'string' then
            grades[level] = { name = data.name, payment = math.max(0, math.floor(tonumber(data.payment) or 0)),
                              isboss = data.isboss == true or nil, bankAuth = data.isboss == true or nil }
        end
    end
    if not grades[0] then return false, 'A job needs grade 0.' end

    local existing = exports.qbx_core:GetJob(name)
    local def = {
        label = job.label,
        type = (job.type ~= '' and job.type) or nil,
        defaultDuty = not existing or existing.defaultDuty ~= false,
        offDutyPay = existing and existing.offDutyPay == true or false,
        grades = grades,
    }
    local ok, err = exports.qbx_core:CreateJob(name, def)
    if not ok then return false, err end
    customJobs[name] = def
    MySQL.query('REPLACE INTO mars_jobs_custom (name, data) VALUES (?, ?)', { name, gradesToJson(def) })
    print(('[mars_jobs] %s saved job %s'):format(GetPlayerName(src), name))
    return true, ('Job %s saved.'):format(def.label)
end)

lib.callback.register('mars_jobs:admin:deleteJob', function(src, name)
    if not isAdmin(src) then return false, 'No permission.' end
    if Config.ProtectedJobs[name] or Config.WorkJobs[name] then return false, 'This job cannot be deleted.' end
    MySQL.query('DELETE FROM mars_jobs_custom WHERE name = ?', { name })
    customJobs[name] = nil
    if builtinJobs[name] then
        return true, 'Your changes to this job were removed. They disappear after the next restart.'
    end
    exports.qbx_core:RemoveJob(name)
    return true, 'Job deleted.'
end)

local function setWork(path, value)
    applyOverride(path, value)
    MySQL.query('REPLACE INTO mars_jobs_settings (path, value) VALUES (?, ?)', { path, json.encode(toPlain(value)) })
    TriggerClientEvent('mars_jobs:client:setting', -1, path, toPlain(Config.GetPath(path)))
end

lib.callback.register('mars_jobs:admin:setWork', function(src, key, field, value)
    if not isAdmin(src) then return false, 'No permission.' end
    local w = Config.WorkJobs[key]
    if not w then return false, 'Unknown work job.' end
    for _, f in ipairs(Config.EditableWorkFields) do
        if f.key == field and (not f.kinds or f.kinds[w.kind]) then
            value = tonumber(value)
            if not value then return false, 'Enter a number.' end
            value = math.min(f.max, math.max(f.min, value))
            setWork(('WorkJobs.%s.%s'):format(key, field), value)
            return true, ('%s = %s'):format(f.label, value)
        end
    end
    return false, 'This setting cannot be edited.'
end)

-- set the NPC or the work area to the admin's own position
lib.callback.register('mars_jobs:admin:setHere', function(src, key, what)
    if not isAdmin(src) then return false, 'No permission.' end
    local w = Config.WorkJobs[key]
    if not w then return false, 'Unknown work job.' end
    local c = pedCoords(src)
    if what == 'npc' then
        setWork(('WorkJobs.%s.npc'):format(key), vec4(c.x, c.y, c.z - 1.0, GetEntityHeading(GetPlayerPed(src))))
    elseif what == 'center' and w.kind == 'area' then
        setWork(('WorkJobs.%s.center'):format(key), vec3(c.x, c.y, c.z))
    else
        return false, 'Invalid option.'
    end
    return true, 'Position saved. The NPC/area moves for everyone now.'
end)

lib.addCommand('jobadmin', { help = 'Job admin panel', restricted = 'group.admin' }, function(src)
    TriggerClientEvent('mars_jobs:client:openAdmin', src)
end)
