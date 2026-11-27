-- /give: admins give any ox_inventory item to themselves or another player.
--   /give                      -> searchable menu
--   /give gold bar 5           -> 5 gold bars to yourself
--   /give 3 goldbar 5          -> 5 gold bars to player id 3

local function isAdmin(src)
    return src == 0 or IsPlayerAceAllowed(src, 'admin') or IsPlayerAceAllowed(src, 'command')
end

local function notify(src, msg, kind)
    if src == 0 then return print(msg) end
    TriggerClientEvent('ox_lib:notify', src, { title = 'Give item', description = msg, type = kind or 'inform' })
end

local function lower(s) return (s or ''):lower():gsub('[%s_%-]+', '') end

-- every item, sorted A-Z by label
local function sortedItems()
    local list = {}
    for name, item in pairs(exports.ox_inventory:Items()) do
        list[#list + 1] = { name = name, label = item.label or name }
    end
    table.sort(list, function(a, b)
        local la, lb = a.label:lower(), b.label:lower()
        if la == lb then return a.name < b.name end
        return la < lb
    end)
    return list
end

-- find items by name or label; exact match wins
local function findItems(query)
    local q = lower(query)
    local all = sortedItems()
    if q == '' then return all end
    local exact, partial = {}, {}
    for _, it in ipairs(all) do
        local n, l = lower(it.name), lower(it.label)
        if n == q or l == q then exact[#exact + 1] = it
        elseif n:find(q, 1, true) or l:find(q, 1, true) then partial[#partial + 1] = it end
    end
    return #exact > 0 and exact or partial
end

local function giveItem(src, target, name, count)
    target, count = tonumber(target), math.floor(tonumber(count) or 1)
    if not target or not GetPlayerName(target) then return false, 'That player is not online.' end
    if count < 1 or count > 1000 then return false, 'Amount must be 1-1000.' end
    local item = exports.ox_inventory:Items(name)
    if not item then return false, 'Unknown item.' end
    if not exports.ox_inventory:CanCarryItem(target, name, count) then
        return false, ('%s cannot carry %d × %s.'):format(GetPlayerName(target), count, item.label)
    end
    local ok, err = exports.ox_inventory:AddItem(target, name, count)
    if not ok then return false, ('Could not give the item (%s).'):format(tostring(err)) end
    print(('[mars_give] %s gave %d x %s to %s'):format(src == 0 and 'console' or GetPlayerName(src), count, name, GetPlayerName(target)))
    if target ~= src then notify(target, ('You received %d × %s.'):format(count, item.label), 'success') end
    return true, ('Gave %d × %s to %s.'):format(count, item.label, GetPlayerName(target))
end

RegisterCommand('give', function(src, args)
    if not isAdmin(src) then return notify(src, 'No permission.', 'error') end
    if #args == 0 then
        if src == 0 then return print('usage: give <id> <item> [amount]') end
        return TriggerClientEvent('mars_give:client:open', src, '')
    end

    -- first number = player id (optional), last number = amount (optional), rest = item
    local target, count = src, 1
    if #args >= 2 and tonumber(args[1]) then target = tonumber(table.remove(args, 1)) end
    if #args >= 2 and tonumber(args[#args]) then count = tonumber(table.remove(args)) end
    local query = table.concat(args, ' ')

    local found = findItems(query)
    if #found == 1 then
        local ok, msg = giveItem(src, target, found[1].name, count)
        return notify(src, msg, ok and 'success' or 'error')
    end
    if src == 0 then return print(('%d items match "%s" - be more exact'):format(#found, query)) end
    -- none or several matches: open the menu with this search
    TriggerClientEvent('mars_give:client:open', src, query, target, count)
end, false)

lib.callback.register('mars_give:search', function(src, query)
    if not isAdmin(src) then return {} end
    return findItems(query)
end)

lib.callback.register('mars_give:give', function(src, target, name, count)
    if not isAdmin(src) then return false, 'No permission.' end
    return giveItem(src, target, name, count)
end)

lib.callback.register('mars_give:players', function(src)
    if not isAdmin(src) then return {} end
    local list = {}
    for _, id in ipairs(GetPlayers()) do list[#list + 1] = { id = tonumber(id), name = GetPlayerName(id) } end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end)
