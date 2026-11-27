Config = {}

-- ─────────────────────────────────────────────────────────────
--  Mars Jobs
--  * /jobadmin – manage players' jobs, create/edit jobs and pay, tune work jobs
--  * Legal work jobs below. Players take them at City Hall, then talk to the
--    job NPC to start a shift. Everything marked (editable) can be changed in
--    game; positions can be set to "where I stand" from the panel.
-- ─────────────────────────────────────────────────────────────

-- jobs that can never be deleted from the panel (their pay can still be edited)
Config.ProtectedJobs = { unemployed = true, police = true, ambulance = true }

-- kind = 'delivery': drive to a random customer on the street and hand over the order
-- kind = 'area':     walk to random spots in an area and work there (no vehicle)
Config.WorkJobs = {
    pizza = {
        label = 'Pizza Delivery', kind = 'delivery',
        npc = vec4(-1285.30, -1387.20, 4.45, 290.0),     -- (editable: set here)
        vehicle = `faggio`,
        pay = 120, bonus = 300, tasksPerShift = 8,          -- (editable)
        minDistance = 300.0, maxDistance = 1400.0,          -- customer distance from you
        prop = `prop_pizza_box_01`,
        action = { label = 'Handing over the pizza...', ms = 3000, dict = 'mp_common', clip = 'givetake1_a' },
        blip = { sprite = 267, color = 5 },
    },
    postal = {
        label = 'GoPostal Courier', kind = 'delivery',
        npc = vec4(-232.16, -915.15, 32.31, 340.0),
        vehicle = `boxville2`,
        pay = 170, bonus = 450, tasksPerShift = 6,
        minDistance = 400.0, maxDistance = 2000.0,
        prop = `prop_cs_cardbox_01`,
        action = { label = 'Delivering the package...', ms = 3500, dict = 'mp_common', clip = 'givetake1_a' },
        blip = { sprite = 478, color = 46 },
    },
    electrician = {
        label = 'Electrician', kind = 'delivery',
        npc = vec4(734.00, -1083.00, 22.17, 90.0),
        vehicle = `burrito`,
        pay = 200, bonus = 500, tasksPerShift = 5,
        minDistance = 300.0, maxDistance = 1800.0,
        object = `prop_elecbox_10`,                         -- spawned at the job spot instead of a customer
        action = { label = 'Repairing the power box...', ms = 9000, scenario = 'WORLD_HUMAN_WELDING' },
        blip = { sprite = 354, color = 5 },
    },
    vineyard = {
        label = 'Vineyard Picker', kind = 'area',
        npc = vec4(-1888.00, 2050.00, 140.95, 160.0),
        center = vec3(-1870.00, 2090.00, 136.00), radius = 40.0,   -- (editable: set here)
        pay = 60, bonus = 250, tasksPerShift = 15,
        action = { label = 'Picking grapes...', ms = 5000, dict = 'amb@prop_human_bum_bin@base', clip = 'base' },
        blip = { sprite = 85, color = 27 },
    },
    miner = {
        label = 'Quarry Miner', kind = 'area',
        npc = vec4(2944.00, 2746.00, 43.40, 280.0),
        center = vec3(2955.00, 2790.00, 41.00), radius = 35.0,
        pay = 85, bonus = 300, tasksPerShift = 12,
        action = { label = 'Mining...', ms = 7000, dict = 'melee@large_wpn@streamed_core', clip = 'ground_attack_on_spot',
                   prop = { model = `prop_tool_pickaxe`, bone = 57005, pos = vec3(0.08, -0.4, -0.1), rot = vec3(80.0, 0.0, 175.0) } },
        blip = { sprite = 618, color = 47 },
    },
    lumberjack = {
        label = 'Lumberjack', kind = 'area',
        npc = vec4(-552.38, 5348.54, 74.74, 70.0),
        center = vec3(-575.00, 5410.00, 60.00), radius = 45.0,
        pay = 80, bonus = 300, tasksPerShift = 12,
        action = { label = 'Chopping wood...', ms = 7000, dict = 'melee@large_wpn@streamed_core', clip = 'ground_attack_on_spot',
                   prop = { model = `prop_w_me_hatchet`, bone = 57005, pos = vec3(0.1, -0.1, -0.02), rot = vec3(80.0, 0.0, 175.0) } },
        blip = { sprite = 285, color = 21 },
    },
}

Config.WorkOrder = { 'pizza', 'postal', 'electrician', 'vineyard', 'miner', 'lumberjack' }

Config.NpcModel = `s_m_m_gentransport`
Config.PayTo = 'bank'          -- 'bank' or 'cash'
Config.MinSecondsPerTask = 20  -- anti-abuse: fastest allowed time between two paid tasks
Config.MaxTaskDistance = 12.0  -- server check: player must be this close to the task spot

-- fields of a work job editable in /jobadmin
Config.EditableWorkFields = {
    { key = 'pay',           label = 'Pay per task ($)',      min = 0,   max = 100000 },
    { key = 'bonus',         label = 'Shift bonus ($)',       min = 0,   max = 100000 },
    { key = 'tasksPerShift', label = 'Tasks per shift',       min = 1,   max = 100 },
    { key = 'minDistance',   label = 'Min. delivery distance', min = 50,  max = 5000, kinds = { delivery = true } },
    { key = 'maxDistance',   label = 'Max. delivery distance', min = 100, max = 8000, kinds = { delivery = true } },
    { key = 'radius',        label = 'Work area radius',       min = 5,   max = 200,  kinds = { area = true } },
}

-- ── helpers ──
function Config.SetPath(path, value)
    local node, keys = Config, {}
    for k in path:gmatch('[^%.]+') do keys[#keys + 1] = k end
    for i = 1, #keys - 1 do
        node = node[keys[i]]
        if type(node) ~= 'table' then return false end
    end
    -- positions are stored as plain tables in the database
    if type(value) == 'table' and value.x and value.y and value.z then
        value = value.w and vec4(value.x, value.y, value.z, value.w) or vec3(value.x, value.y, value.z)
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
