local function notify(ok, msg)
    lib.notify({ title = 'Give item', description = msg, type = ok and 'success' or 'error' })
end

local openSearch

local function openResults(query, target, count)
    local items = lib.callback.await('mars_give:search', false, query) or {}
    if #items == 0 then
        notify(false, ('No item matches "%s".'):format(query))
        return openSearch(query, target, count)
    end
    local options = {
        { title = ('Search: %s'):format(query ~= '' and query or 'all items'), description = 'Change search / player / amount',
          icon = 'fa-solid fa-magnifying-glass', onSelect = function() openSearch(query, target, count) end },
    }
    for i = 1, math.min(#items, 300) do
        local it = items[i]
        options[#options + 1] = {
            title = it.label, description = it.name,
            image = ('nui://ox_inventory/web/images/%s.png'):format(it.name),
            onSelect = function()
                notify(lib.callback.await('mars_give:give', false, target, it.name, count))
                openResults(query, target, count)
            end,
        }
    end
    lib.registerContext({
        id = 'mars_give_results',
        title = ('Give %d × … to ID %d  (%d items, A-Z)'):format(count, target, #items),
        options = options,
    })
    lib.showContext('mars_give_results')
end

openSearch = function(query, target, count)
    local players = lib.callback.await('mars_give:players', false) or {}
    local playerOptions = {}
    for _, p in ipairs(players) do
        playerOptions[#playerOptions + 1] = { value = p.id, label = ('%d – %s'):format(p.id, p.name) }
    end
    local input = lib.inputDialog('Give item', {
        { type = 'input', label = 'Item name (empty = all items)', default = query or '', placeholder = 'e.g. gold bar' },
        { type = 'select', label = 'Player', options = playerOptions, default = target or cache.serverId, required = true },
        { type = 'number', label = 'Amount', default = count or 1, min = 1, max = 1000, required = true },
    })
    if not input then return end
    openResults(input[1] or '', tonumber(input[2]) or cache.serverId, input[3] or 1)
end

RegisterNetEvent('mars_give:client:open', function(query, target, count)
    target, count = target or cache.serverId, count or 1
    if query and query ~= '' then openResults(query, target, count) else openSearch('', target, count) end
end)

TriggerEvent('chat:addSuggestion', '/give', 'Admin: give an item (empty = menu)', {
    { name = 'id', help = 'player id (optional, default you)' },
    { name = 'item', help = 'item name or label, e.g. gold bar' },
    { name = 'amount', help = 'amount (optional)' },
})
