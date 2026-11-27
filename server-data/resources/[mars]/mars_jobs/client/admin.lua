-- /jobadmin – job admin panel (the server checks admin rights on every action)

local openMain, openPlayers, openJobs, openWork, openOverview, gradeActions, openTakeJob

local function result(ok, msg)
    lib.notify({ title = 'Job admin', description = msg, type = ok and 'success' or 'error' })
end

-- ── players ──

local function pickGrade(job, cb)
    local options = {}
    for _, g in ipairs(job.grades) do
        options[#options + 1] = {
            title = ('%d – %s%s'):format(g.level, g.name, g.isboss and ' (boss)' or ''),
            description = ('Salary $%d'):format(g.payment),
            onSelect = function() cb(g.level) end,
        }
    end
    lib.registerContext({ id = 'mars_jobadmin_grade', title = ('%s – grade'):format(job.label), menu = 'mars_jobadmin_pickjob', options = options })
    lib.showContext('mars_jobadmin_grade')
end

local function pickJob(target)
    local jobs = lib.callback.await('mars_jobs:admin:jobs', false) or {}
    local options = {}
    for _, job in ipairs(jobs) do
        options[#options + 1] = {
            title = job.label, description = ('%s%s • %d grades'):format(job.name, job.type and (' • ' .. job.type) or '', #job.grades),
            arrow = true,
            onSelect = function()
                pickGrade(job, function(level)
                    result(lib.callback.await('mars_jobs:admin:setJob', false, target.id, job.name, level))
                    openPlayers()
                end)
            end,
        }
    end
    lib.registerContext({ id = 'mars_jobadmin_pickjob', title = ('Set job – %s'):format(target.char), menu = 'mars_jobadmin_player', options = options })
    lib.showContext('mars_jobadmin_pickjob')
end

local function openPlayer(p)
    lib.registerContext({
        id = 'mars_jobadmin_player', title = ('[%d] %s'):format(p.id, p.char), menu = 'mars_jobadmin_players',
        options = {
            { title = ('Job: %s – %s (grade %d)'):format(p.jobLabel or p.job, p.gradeName, p.grade),
              description = ('Citizen ID %s • %s'):format(p.citizenid, p.onduty and 'on duty' or 'off duty'), readOnly = true },
            { title = 'Set job ▸', icon = 'fa-solid fa-briefcase', arrow = true, onSelect = function() pickJob(p) end },
            { title = p.onduty and 'Set off duty' or 'Set on duty', icon = 'fa-solid fa-clock',
              onSelect = function() result(lib.callback.await('mars_jobs:admin:setDuty', false, p.id, not p.onduty)); openPlayers() end },
            { title = 'Fire (make unemployed)', icon = 'fa-solid fa-user-xmark',
              onSelect = function() result(lib.callback.await('mars_jobs:admin:setJob', false, p.id, 'unemployed', 0)); openPlayers() end },
        },
    })
    lib.showContext('mars_jobadmin_player')
end

openPlayers = function()
    local players = lib.callback.await('mars_jobs:admin:players', false) or {}
    local options = {}
    for _, p in ipairs(players) do
        options[#options + 1] = {
            title = ('[%d] %s'):format(p.id, p.char),
            description = ('%s • %s %s (%d)%s'):format(p.name, p.jobLabel or p.job, p.gradeName, p.grade, p.onduty and ' • on duty' or ''),
            arrow = true, onSelect = function() openPlayer(p) end,
        }
    end
    if #options == 0 then options[1] = { title = 'No players online', readOnly = true } end
    lib.registerContext({ id = 'mars_jobadmin_players', title = 'Players', menu = 'mars_jobadmin', options = options })
    lib.showContext('mars_jobadmin_players')
end

-- ── jobs: create / edit / delete ──

local function toSaveFormat(job)
    local grades = {}
    for _, g in ipairs(job.grades) do
        grades[tostring(g.level)] = { name = g.name, payment = g.payment, isboss = g.isboss }
    end
    return { label = job.label, type = job.type or '', grades = grades }
end

local function saveJob(job)
    result(lib.callback.await('mars_jobs:admin:saveJob', false, job.name, toSaveFormat(job)))
end

local openJob

local function editGrade(job, g)
    local input = lib.inputDialog(('%s – grade %d'):format(job.label, g.level), {
        { type = 'input', label = 'Grade name', default = g.name, required = true },
        { type = 'number', label = 'Salary ($ per pay cycle)', default = g.payment, min = 0, max = 100000, required = true },
        { type = 'checkbox', label = 'Boss (can manage employees)', checked = g.isboss },
    })
    if not input then return openJob(job) end
    g.name, g.payment, g.isboss = input[1], math.floor(input[2]), input[3] == true
    saveJob(job)
    openJob(job)
end

-- choose an online player, then give them job + grade
local function giveToPlayer(job, g, back)
    local players = lib.callback.await('mars_jobs:admin:players', false) or {}
    local options = {}
    for _, p in ipairs(players) do
        options[#options + 1] = {
            title = ('[%d] %s'):format(p.id, p.char),
            description = ('now: %s – %s'):format(p.jobLabel or p.job, p.gradeName),
            onSelect = function()
                result(lib.callback.await('mars_jobs:admin:setJob', false, p.id, job.name, g.level))
                back()
            end,
        }
    end
    if #options == 0 then options[1] = { title = 'No players online', readOnly = true } end
    lib.registerContext({ id = 'mars_jobadmin_giveto', title = ('Give %s – %s to...'):format(job.label, g.name), menu = 'mars_jobadmin_gradeact', options = options })
    lib.showContext('mars_jobadmin_giveto')
end

gradeActions = function(job, g)
    lib.registerContext({
        id = 'mars_jobadmin_gradeact', title = ('%s – %s'):format(job.label, g.name), menu = 'mars_jobadmin_job',
        options = {
            { title = 'Give to me', description = ('Make yourself %s %s'):format(job.label, g.name), icon = 'fa-solid fa-user-check',
              onSelect = function() result(lib.callback.await('mars_jobs:admin:setJob', false, cache.serverId, job.name, g.level)) end },
            { title = 'Give to a player ▸', icon = 'fa-solid fa-user-plus', arrow = true,
              onSelect = function() giveToPlayer(job, g, function() openJob(job) end) end },
            { title = 'Edit name / salary / boss', icon = 'fa-solid fa-pen', onSelect = function() editGrade(job, g) end },
        },
    })
    lib.showContext('mars_jobadmin_gradeact')
end

openJob = function(job)
    local options = {
        { title = ('Label: %s'):format(job.label), description = ('id: %s • type: %s'):format(job.name, job.type or 'none'), icon = 'fa-solid fa-pen',
          onSelect = function()
              local input = lib.inputDialog('Edit job', {
                  { type = 'input', label = 'Label (shown in game)', default = job.label, required = true },
                  { type = 'select', label = 'Type', default = job.type or '', options = {
                      { value = '', label = 'None' }, { value = 'leo', label = 'Police (leo)' }, { value = 'ems', label = 'Medical (ems)' },
                      { value = 'mechanic', label = 'Mechanic' }, { value = 'realestate', label = 'Real estate' } } },
              })
              if input then job.label, job.type = input[1], input[2] ~= '' and input[2] or nil; saveJob(job) end
              openJob(job)
          end },
    }
    options[#options + 1] = {
        title = ('Online now: %d (on duty %d)'):format(job.online.count, job.online.duty),
        description = #job.online.names > 0 and table.concat(job.online.names, '\n') or 'Nobody from this job is online.',
        icon = 'fa-solid fa-users', readOnly = true,
    }
    for _, g in ipairs(job.grades) do
        options[#options + 1] = {
            title = ('Grade %d – %s%s'):format(g.level, g.name, g.isboss and ' (boss)' or ''),
            description = ('Salary $%d • give this grade to me or a player, or edit it'):format(g.payment), icon = 'fa-solid fa-ranking-star',
            arrow = true, onSelect = function() gradeActions(job, g) end,
        }
    end
    options[#options + 1] = {
        title = 'Add grade', icon = 'fa-solid fa-plus',
        onSelect = function()
            local level = #job.grades > 0 and (job.grades[#job.grades].level + 1) or 0
            local g = { level = level, name = 'New grade', payment = 0, isboss = false }
            job.grades[#job.grades + 1] = g
            editGrade(job, g)
        end,
    }
    if #job.grades > 1 then
        options[#options + 1] = {
            title = 'Remove highest grade', icon = 'fa-solid fa-minus',
            onSelect = function() table.remove(job.grades); saveJob(job); openJob(job) end,
        }
    end
    if not job.protected and not job.work then
        options[#options + 1] = {
            title = job.builtin and 'Undo my changes to this job' or 'Delete job', icon = 'fa-solid fa-trash',
            onSelect = function()
                if lib.alertDialog({ header = 'Delete', content = ('Delete %s?'):format(job.label), centered = true, cancel = true }) ~= 'confirm' then return openJob(job) end
                result(lib.callback.await('mars_jobs:admin:deleteJob', false, job.name))
                openJobs()
            end,
        }
    end
    lib.registerContext({ id = 'mars_jobadmin_job', title = job.label, menu = 'mars_jobadmin_jobs', options = options })
    lib.showContext('mars_jobadmin_job')
end

local function createJob()
    local input = lib.inputDialog('Create job', {
        { type = 'input', label = 'Job id (lowercase, e.g. lawyer2)', required = true },
        { type = 'input', label = 'Label (shown in game)', required = true },
        { type = 'number', label = 'Number of grades', default = 3, min = 1, max = 10, required = true },
        { type = 'number', label = 'Starting salary', default = 50, min = 0, max = 100000, required = true },
    })
    if not input then return openJobs() end
    local job = { name = input[1]:lower(), label = input[2], grades = {} }
    for i = 0, math.floor(input[3]) - 1 do
        job.grades[#job.grades + 1] = { level = i, name = ('Grade %d'):format(i), payment = math.floor(input[4] * (1 + i * 0.25)), isboss = i == math.floor(input[3]) - 1 }
    end
    saveJob(job)
    openJobs()
end

openJobs = function()
    local jobs = lib.callback.await('mars_jobs:admin:jobs', false) or {}
    local options = { { title = 'Create new job', icon = 'fa-solid fa-plus', onSelect = createJob } }
    for _, job in ipairs(jobs) do
        local top = job.grades[#job.grades]
        options[#options + 1] = {
            title = ('%s%s'):format(job.label, job.online.count > 0 and ('  👥 %d'):format(job.online.count) or ''),
            description = ('%s • %d grades • up to $%d • online %d, on duty %d%s'):format(job.name, #job.grades, top and top.payment or 0,
                job.online.count, job.online.duty, job.custom and ' • edited' or ''),
            arrow = true, onSelect = function() openJob(job) end,
        }
    end
    lib.registerContext({ id = 'mars_jobadmin_jobs', title = 'Jobs', menu = 'mars_jobadmin', options = options })
    lib.showContext('mars_jobadmin_jobs')
end

-- ── work jobs (pizza, postal, ...) ──

local function openWorkJob(key)
    local w = Config.WorkJobs[key]
    local options = {}
    for _, f in ipairs(Config.EditableWorkFields) do
        if not f.kinds or f.kinds[w.kind] then
            options[#options + 1] = {
                title = ('%s: %s'):format(f.label, tostring(w[f.key])), icon = 'fa-solid fa-sliders',
                onSelect = function()
                    local input = lib.inputDialog(f.label, { { type = 'number', label = ('%s (%s – %s)'):format(f.label, f.min, f.max), default = w[f.key], min = f.min, max = f.max, required = true } })
                    if input then
                        result(lib.callback.await('mars_jobs:admin:setWork', false, key, f.key, input[1]))
                        Wait(200)
                    end
                    openWorkJob(key)
                end,
            }
        end
    end
    options[#options + 1] = {
        title = 'Move job NPC to my position', icon = 'fa-solid fa-location-dot',
        onSelect = function() result(lib.callback.await('mars_jobs:admin:setHere', false, key, 'npc')); openWorkJob(key) end,
    }
    if w.kind == 'area' then
        options[#options + 1] = {
            title = 'Set work area center to my position', icon = 'fa-solid fa-crosshairs',
            onSelect = function() result(lib.callback.await('mars_jobs:admin:setHere', false, key, 'center')); openWorkJob(key) end,
        }
    end
    options[#options + 1] = {
        title = 'Teleport to job NPC', icon = 'fa-solid fa-person-walking-arrow-right',
        onSelect = function()
            local n = w.npc
            SetEntityCoords(cache.ped, n.x + 1.5, n.y, n.z + 0.5, false, false, false, false)
        end,
    }
    lib.registerContext({ id = 'mars_jobadmin_workjob', title = w.label, menu = 'mars_jobadmin_work', options = options })
    lib.showContext('mars_jobadmin_workjob')
end

openWork = function()
    local options = {}
    for _, key in ipairs(Config.WorkOrder) do
        local w = Config.WorkJobs[key]
        options[#options + 1] = {
            title = w.label, description = ('$%d per task • %d tasks • $%d bonus'):format(w.pay, w.tasksPerShift, w.bonus),
            arrow = true, onSelect = function() openWorkJob(key) end,
        }
    end
    lib.registerContext({ id = 'mars_jobadmin_work', title = 'Work jobs', menu = 'mars_jobadmin', options = options })
    lib.showContext('mars_jobadmin_work')
end

openTakeJob = function()
    local jobs = lib.callback.await('mars_jobs:admin:jobs', false) or {}
    local options = {}
    for _, job in ipairs(jobs) do
        options[#options + 1] = {
            title = job.label, description = ('%s • %d grades'):format(job.name, #job.grades), arrow = true,
            onSelect = function()
                local gopts = {}
                for _, g in ipairs(job.grades) do
                    gopts[#gopts + 1] = {
                        title = ('%d – %s%s'):format(g.level, g.name, g.isboss and ' (boss)' or ''),
                        description = ('Salary $%d'):format(g.payment),
                        onSelect = function()
                            result(lib.callback.await('mars_jobs:admin:setJob', false, cache.serverId, job.name, g.level))
                        end,
                    }
                end
                lib.registerContext({ id = 'mars_jobadmin_take_grade', title = ('%s – choose grade'):format(job.label), menu = 'mars_jobadmin_take', options = gopts })
                lib.showContext('mars_jobadmin_take_grade')
            end,
        }
    end
    lib.registerContext({ id = 'mars_jobadmin_take', title = 'Take a job', menu = 'mars_jobadmin', options = options })
    lib.showContext('mars_jobadmin_take')
end

openOverview = function()
    local jobs = lib.callback.await('mars_jobs:admin:jobs', false) or {}
    table.sort(jobs, function(a, b)
        if a.online.count ~= b.online.count then return a.online.count > b.online.count end
        return a.label < b.label
    end)
    local options = {}
    for _, job in ipairs(jobs) do
        options[#options + 1] = {
            title = ('%s — %d online / %d on duty'):format(job.label, job.online.count, job.online.duty),
            description = #job.online.names > 0 and table.concat(job.online.names, '\n') or nil,
            icon = job.online.count > 0 and 'fa-solid fa-circle' or 'fa-regular fa-circle',
            iconColor = job.online.duty > 0 and '#22c55e' or (job.online.count > 0 and '#eab308' or '#6b7280'),
            arrow = true, onSelect = function() openJob(job) end,
        }
    end
    lib.registerContext({ id = 'mars_jobadmin_overview', title = 'Jobs overview', menu = 'mars_jobadmin', options = options })
    lib.showContext('mars_jobadmin_overview')
end

openMain = function()
    lib.registerContext({
        id = 'mars_jobadmin', title = 'Mars – Job Admin',
        options = {
            { title = 'Take a job (me) ▸', description = 'Pick any job and grade for yourself', icon = 'fa-solid fa-id-badge', arrow = true, onSelect = function() openTakeJob() end },
            { title = 'Overview ▸', description = 'Every job with how many people work there right now', icon = 'fa-solid fa-table-list', arrow = true, onSelect = function() openOverview() end },
            { title = 'Players ▸', description = 'See everyone\'s job, set job and grade, duty, fire', icon = 'fa-solid fa-users', arrow = true, onSelect = openPlayers },
            { title = 'Jobs ▸', description = 'Create jobs, edit grades and salaries', icon = 'fa-solid fa-briefcase', arrow = true, onSelect = openJobs },
            { title = 'Work jobs ▸', description = 'Pizza, courier, electrician, vineyard, miner, lumberjack', icon = 'fa-solid fa-person-digging', arrow = true, onSelect = openWork },
        },
    })
    lib.showContext('mars_jobadmin')
end

RegisterNetEvent('mars_jobs:client:openAdmin', openMain)
