-- /testlist – tick off what you have tested. Progress is saved on this PC.

local KVP = 'mars_testlist:'

local function isDone(id) return GetResourceKvpInt(KVP .. id) == 1 end
local function setDone(id, v) SetResourceKvpInt(KVP .. id, v and 1 or 0) end

local function counts(tests)
    local done = 0
    for _, t in ipairs(tests) do if isDone(t.id) then done = done + 1 end end
    return done, #tests
end

local openMain

local function openTest(section, t)
    local done = isDone(t.id)
    lib.registerContext({
        id = 'mars_testlist_test', title = t.title, menu = 'mars_testlist_section',
        options = {
            { title = 'How to test', description = t.how, icon = 'fa-solid fa-circle-info', readOnly = true },
            { title = done and 'Mark as NOT done' or 'Mark as done ✓', icon = done and 'fa-solid fa-rotate-left' or 'fa-solid fa-check',
              iconColor = done and '#eab308' or '#22c55e',
              onSelect = function() setDone(t.id, not done); openSection(section) end },
            { title = 'It did not work', description = 'Mark as failed and remember to send a screenshot + server log to the developer.',
              icon = 'fa-solid fa-bug', iconColor = '#ef4444',
              onSelect = function()
                  setDone(t.id, false)
                  SetResourceKvpInt(KVP .. 'fail:' .. t.id, 1)
                  lib.notify({ title = 'Test list', description = ('"%s" marked as failed. Send a screenshot and the server log.'):format(t.title), type = 'error', duration = 7000 })
                  openSection(section)
              end },
        },
    })
    lib.showContext('mars_testlist_test')
end

function openSection(section)
    local options = {}
    for _, t in ipairs(section.tests) do
        local done = isDone(t.id)
        local failed = GetResourceKvpInt(KVP .. 'fail:' .. t.id) == 1 and not done
        options[#options + 1] = {
            title = t.title, description = t.how,
            icon = done and 'fa-solid fa-square-check' or (failed and 'fa-solid fa-triangle-exclamation' or 'fa-regular fa-square'),
            iconColor = done and '#22c55e' or (failed and '#ef4444' or '#9ca3af'),
            arrow = true, onSelect = function() openTest(section, t) end,
        }
        if done then SetResourceKvpInt(KVP .. 'fail:' .. t.id, 0) end
    end
    local d, n = counts(section.tests)
    lib.registerContext({ id = 'mars_testlist_section', title = ('%s  (%d/%d)'):format(section.section, d, n), menu = 'mars_testlist', options = options })
    lib.showContext('mars_testlist_section')
end

openMain = function()
    local options, allDone, all = {}, 0, 0
    for _, section in ipairs(TestList) do
        local d, n = counts(section.tests)
        allDone, all = allDone + d, all + n
        options[#options + 1] = {
            title = section.section, description = ('%d of %d tested'):format(d, n),
            icon = section.icon, iconColor = d == n and '#22c55e' or nil,
            progress = math.floor(d / n * 100), colorScheme = d == n and 'green' or 'violet',
            arrow = true, onSelect = function() openSection(section) end,
        }
    end
    table.insert(options, 1, {
        title = ('Total progress: %d / %d'):format(allDone, all), progress = math.floor(allDone / all * 100),
        colorScheme = 'green', icon = 'fa-solid fa-list-check', readOnly = true,
    })
    options[#options + 1] = {
        title = 'Reset all ticks', icon = 'fa-solid fa-rotate-left',
        onSelect = function()
            if lib.alertDialog({ header = 'Reset', content = 'Clear every tick?', centered = true, cancel = true }) ~= 'confirm' then return openMain() end
            for _, section in ipairs(TestList) do
                for _, t in ipairs(section.tests) do setDone(t.id, false); SetResourceKvpInt(KVP .. 'fail:' .. t.id, 0) end
            end
            openMain()
        end,
    }
    lib.registerContext({ id = 'mars_testlist', title = 'Mars – Test Checklist', options = options })
    lib.showContext('mars_testlist')
end

RegisterCommand('testlist', openMain, false)
TriggerEvent('chat:addSuggestion', '/testlist', 'Open the test checklist')
