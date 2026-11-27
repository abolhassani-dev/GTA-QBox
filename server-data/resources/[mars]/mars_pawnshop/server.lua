local market = {}      -- [item] = { saturation, stock }
local hot = {}         -- [item] = true
local hotUntil = 0
local mood = {}        -- [item] = daily random factor
local rep = {}         -- [citizenid] = xp
local annoyed = {}     -- [citizenid] = { [item] = os.time() until }
local history = {}     -- [citizenid] = { ...last sales }
local overrides, defaults = {}, {}
local ticketCounter = math.random(10000, 49999)

-- ─────────────────────────────────────────────────────────────
-- helpers
-- ─────────────────────────────────────────────────────────────

local function getPlayer(src) return exports.qbx_core:GetPlayer(src) end
local function cid(src) local p = getPlayer(src) return p and p.PlayerData.citizenid end

local function near(src)
    local p = GetEntityCoords(GetPlayerPed(src))
    local c = Config.Npc.coords
    return #(vec2(p.x, p.y) - vec2(c.x, c.y)) < 8.0
end

local function levelFor(xp)
    local idx = 1
    for i, l in ipairs(Config.Reputation.levels) do if xp >= l.xp then idx = i end end
    return idx, Config.Reputation.levels[idx], Config.Reputation.levels[idx + 1]
end

local function itemLabel(name)
    local item = exports.ox_inventory:Items(name)
    return item and item.label or name
end

local function marketOf(name)
    market[name] = market[name] or { saturation = 0, stock = 0 }
    return market[name]
end

local function rotateHot()
    hot = {}
    local names = {}
    for name in pairs(Config.Items) do names[#names + 1] = name end
    for i = 1, math.min(Config.Hot.count, #names) do
        local pick = table.remove(names, math.random(#names))
        hot[pick] = true
    end
    for name in pairs(Config.Items) do
        mood[name] = 1 + (math.random() * 2 - 1) * Config.Market.randomSpread
    end
    hotUntil = os.time() + Config.Hot.rotateMinutes * 60
end

-- price the shop pays for one unit right now
local function unitPrice(name, citizenid)
    local def = Config.Items[name]
    if not def then return 0 end
    local m = marketOf(name)
    local base = (def.min + def.max) / 2 * (mood[name] or 1)
    local price = base * (1 - m.saturation)
    if hot[name] then price = price * Config.Hot.multiplier end
    local _, level = levelFor(rep[citizenid] or 0)
    price = price * (1 + level.bonus)
    local a = annoyed[citizenid] and annoyed[citizenid][name]
    if a and a > os.time() then price = price * (1 - Config.Haggle.annoyedPenalty) end
    return math.max(1, math.floor(price))
end

local function buyPrice(name)
    local def = Config.Items[name]
    return math.floor((def.min + def.max) / 2 * Config.BuyBack.markup)
end

local function saveMarket(name)
    local m = marketOf(name)
    MySQL.query('REPLACE INTO mars_pawn_market (item, saturation, stock) VALUES (?, ?, ?)', { name, m.saturation, m.stock })
end

local function addXp(citizenid, amount)
    rep[citizenid] = (rep[citizenid] or 0) + amount
    MySQL.query('REPLACE INTO mars_pawn_rep (citizenid, xp) VALUES (?, ?)', { citizenid, rep[citizenid] })
end

local function pushHistory(citizenid, entry)
    history[citizenid] = history[citizenid] or {}
    table.insert(history[citizenid], 1, entry)
    while #history[citizenid] > Config.HistorySize do table.remove(history[citizenid]) end
    MySQL.query('REPLACE INTO mars_pawn_history (citizenid, data) VALUES (?, ?)', { citizenid, json.encode(history[citizenid]) })
end

local function alertPolice(src)
    local c = GetEntityCoords(GetPlayerPed(src))
    for _, id in ipairs(GetPlayers()) do
        local p = getPlayer(tonumber(id))
        local job = p and p.PlayerData.job
        if job and job.type == Config.Police.jobType and job.onduty then
            TriggerClientEvent('mars_pawn:client:policeAlert', tonumber(id), c)
        end
    end
end

-- ─────────────────────────────────────────────────────────────
-- database
-- ─────────────────────────────────────────────────────────────

MySQL.ready(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `mars_pawn_market` (
        `item` VARCHAR(60) NOT NULL, `saturation` FLOAT NOT NULL DEFAULT 0, `stock` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`item`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `mars_pawn_rep` (
        `citizenid` VARCHAR(50) NOT NULL, `xp` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`citizenid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `mars_pawn_history` (
        `citizenid` VARCHAR(50) NOT NULL, `data` LONGTEXT NOT NULL,
        PRIMARY KEY (`citizenid`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `mars_pawn_smelter` (
        `id` INT NOT NULL AUTO_INCREMENT, `citizenid` VARCHAR(50) NOT NULL, `item` VARCHAR(60) NOT NULL,
        `count` INT NOT NULL, `ready_at` INT NOT NULL, PRIMARY KEY (`id`), KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `mars_pawn_settings` (
        `path` VARCHAR(100) NOT NULL, `value` VARCHAR(255) NOT NULL,
        PRIMARY KEY (`path`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    for _, r in ipairs(MySQL.query.await('SELECT * FROM mars_pawn_settings') or {}) do
        local v = json.decode(r.value)
        if v ~= nil then
            if defaults[r.path] == nil then defaults[r.path] = Config.GetPath(r.path) end
            Config.SetPath(r.path, v); overrides[r.path] = v
        end
    end
    for _, r in ipairs(MySQL.query.await('SELECT * FROM mars_pawn_market') or {}) do
        market[r.item] = { saturation = r.saturation, stock = r.stock }
    end
    for _, r in ipairs(MySQL.query.await('SELECT * FROM mars_pawn_rep') or {}) do rep[r.citizenid] = r.xp end
    for _, r in ipairs(MySQL.query.await('SELECT * FROM mars_pawn_history') or {}) do history[r.citizenid] = json.decode(r.data) or {} end
    rotateHot()
end)

-- prices slowly recover; hot items rotate
CreateThread(function()
    while true do
        Wait(60000)
        for name, m in pairs(market) do
            if m.saturation > 0 then
                m.saturation = math.max(0, m.saturation - Config.Market.recoveryPerMinute)
                saveMarket(name)
            end
        end
        if os.time() >= hotUntil then rotateHot() end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- state sent to the UI
-- ─────────────────────────────────────────────────────────────

local function smelterJobs(citizenid)
    local rows = MySQL.query.await('SELECT * FROM mars_pawn_smelter WHERE citizenid = ? ORDER BY ready_at', { citizenid }) or {}
    local now, list = os.time(), {}
    for _, r in ipairs(rows) do
        list[#list + 1] = { id = r.id, item = r.item, label = itemLabel(r.item), count = r.count, left = math.max(0, r.ready_at - now) }
    end
    return list
end

local function buildState(src)
    local citizenid = cid(src)
    local xp = rep[citizenid] or 0
    local idx, level, nextLevel = levelFor(xp)

    local sell = {}
    for name, def in pairs(Config.Items) do
        local count = exports.ox_inventory:GetItemCount(src, name)
        local m = marketOf(name)
        sell[#sell + 1] = {
            name = name, label = itemLabel(name), category = def.category, count = count,
            price = unitPrice(name, citizenid), hot = hot[name] == true,
            trend = m.saturation > 0.15 and 'down' or (m.saturation > 0.02 and 'soft' or 'up'),
            melt = def.melt ~= nil,
            annoyed = annoyed[citizenid] and annoyed[citizenid][name] and annoyed[citizenid][name] > os.time() or false,
        }
    end
    table.sort(sell, function(a, b)
        if (a.count > 0) ~= (b.count > 0) then return a.count > 0 end
        if a.hot ~= b.hot then return a.hot end
        return a.price > b.price
    end)

    local stock = {}
    for name, m in pairs(market) do
        if m.stock > 0 and Config.Items[name] then
            stock[#stock + 1] = { name = name, label = itemLabel(name), count = m.stock, price = buyPrice(name) }
        end
    end
    table.sort(stock, function(a, b) return a.label < b.label end)

    local black
    if idx >= Config.BlackMarket.minLevel then
        black = {}
        for _, it in ipairs(Config.BlackMarket.items) do
            black[#black + 1] = { name = it.name, label = itemLabel(it.name), price = it.price }
        end
    end

    local hotList = {}
    for name in pairs(hot) do hotList[#hotList + 1] = itemLabel(name) end

    return {
        shop = Config.ShopName,
        sell = sell, stock = stock, black = black,
        hot = hotList, hotLeft = math.max(0, hotUntil - os.time()),
        haggle = (function()
            local list = {}
            for i, h in ipairs(Config.Haggle) do list[i] = { label = h.label, chance = h.chance, bonus = h.bonus } end
            return { list = list, repBonus = Config.Haggle.repChanceBonus }
        end)(),
        rep = {
            xp = xp, levelXp = level.xp, level = idx, label = level.label, bonus = level.bonus,
            nextXp = nextLevel and nextLevel.xp or nil, nextLabel = nextLevel and nextLevel.label or nil,
            blackAt = Config.BlackMarket.minLevel, blackLabel = Config.Reputation.levels[Config.BlackMarket.minLevel].label,
        },
        smelter = smelterJobs(citizenid),
        history = history[citizenid] or {},
        cash = getPlayer(src).PlayerData.money.cash or 0,
    }
end

lib.callback.register('mars_pawn:server:state', function(src)
    if not near(src) or not cid(src) then return end
    return buildState(src)
end)

-- ─────────────────────────────────────────────────────────────
-- selling (with optional haggling)
-- ─────────────────────────────────────────────────────────────

lib.callback.register('mars_pawn:server:sell', function(src, name, count, haggleLevel)
    local citizenid = cid(src)
    if not near(src) or not citizenid then return { ok = false, msg = 'You are not at the shop.' } end
    local def = Config.Items[name]
    count = math.floor(tonumber(count) or 0)
    if not def or count < 1 then return { ok = false, msg = 'Invalid item.' } end
    if exports.ox_inventory:GetItemCount(src, name) < count then return { ok = false, msg = 'You do not have that many.' } end

    local price = unitPrice(name, citizenid)
    local h = haggleLevel and Config.Haggle[tonumber(haggleLevel)]
    local haggled = false
    if h then
        local idx = levelFor(rep[citizenid] or 0)
        local chance = h.chance + (idx - 1) * Config.Haggle.repChanceBonus
        if math.random(100) <= chance then
            price = math.floor(price * (1 + h.bonus))
            haggled = true
        else
            annoyed[citizenid] = annoyed[citizenid] or {}
            annoyed[citizenid][name] = os.time() + Config.Haggle.annoyedMinutes * 60
            return { ok = false, refused = true, msg = ('"Get out of here with that price." He lowers his offers on %s for %d minutes.'):format(itemLabel(name), Config.Haggle.annoyedMinutes), state = buildState(src) }
        end
    end

    -- each unit sold pushes the price down a little: charge the average
    local m = marketOf(name)
    local total = 0
    for i = 0, count - 1 do
        local sat = math.min(Config.Market.maxSaturation, m.saturation + i * Config.Market.saturationPerUnit)
        total = total + price * (1 - sat) / (1 - m.saturation)
    end
    total = math.floor(total)

    if not exports.ox_inventory:RemoveItem(src, name, count) then return { ok = false, msg = 'Sale failed.' } end
    getPlayer(src).Functions.AddMoney('cash', total, 'mars-pawnshop')

    m.saturation = math.min(Config.Market.maxSaturation, m.saturation + count * Config.Market.saturationPerUnit)
    m.stock = math.min(Config.BuyBack.maxStock, m.stock + count)
    saveMarket(name)
    addXp(citizenid, total)

    ticketCounter = ticketCounter + 1
    local ticket = {
        no = ('MPG-%d'):format(ticketCounter), item = itemLabel(name), count = count, total = total,
        unit = math.floor(total / count), haggled = haggled, hot = hot[name] == true, date = os.date('%Y-%m-%d %H:%M'),
    }
    pushHistory(citizenid, ticket)

    if total >= Config.Police.minValue and math.random(100) <= Config.Police.chance then alertPolice(src) end
    return { ok = true, ticket = ticket, state = buildState(src) }
end)

-- ─────────────────────────────────────────────────────────────
-- buy-back and black market
-- ─────────────────────────────────────────────────────────────

local function pay(src, amount)
    local player = getPlayer(src)
    if (player.PlayerData.money.cash or 0) >= amount then return player.Functions.RemoveMoney('cash', amount, 'mars-pawnshop') end
    return false
end

lib.callback.register('mars_pawn:server:buy', function(src, name, count)
    if not near(src) then return { ok = false, msg = 'You are not at the shop.' } end
    count = math.floor(tonumber(count) or 0)
    local m = market[name]
    if not Config.Items[name] or not m or count < 1 or m.stock < count then return { ok = false, msg = 'Not in stock.' } end
    local cost = buyPrice(name) * count
    if not exports.ox_inventory:CanCarryItem(src, name, count) then return { ok = false, msg = 'You cannot carry that.' } end
    if not pay(src, cost) then return { ok = false, msg = 'Not enough cash.' } end
    exports.ox_inventory:AddItem(src, name, count)
    m.stock = m.stock - count
    saveMarket(name)
    return { ok = true, msg = ('Bought %d × %s for $%d.'):format(count, itemLabel(name), cost), state = buildState(src) }
end)

lib.callback.register('mars_pawn:server:buyBlack', function(src, name, count)
    local citizenid = cid(src)
    if not near(src) or not citizenid then return { ok = false, msg = 'You are not at the shop.' } end
    if levelFor(rep[citizenid] or 0) < Config.BlackMarket.minLevel then return { ok = false, msg = 'He does not know you well enough.' } end
    count = math.floor(tonumber(count) or 0)
    local entry
    for _, it in ipairs(Config.BlackMarket.items) do if it.name == name then entry = it end end
    if not entry or count < 1 or count > 10 then return { ok = false, msg = 'Invalid item.' } end
    if not exports.ox_inventory:CanCarryItem(src, name, count) then return { ok = false, msg = 'You cannot carry that.' } end
    if not pay(src, entry.price * count) then return { ok = false, msg = 'Not enough cash.' } end
    exports.ox_inventory:AddItem(src, name, count)
    return { ok = true, msg = ('Bought %d × %s. Keep it quiet.'):format(count, itemLabel(name)), state = buildState(src) }
end)

-- ─────────────────────────────────────────────────────────────
-- smelter
-- ─────────────────────────────────────────────────────────────

lib.callback.register('mars_pawn:server:melt', function(src, name, count)
    local citizenid = cid(src)
    if not near(src) or not citizenid then return { ok = false, msg = 'You are not at the shop.' } end
    local def = Config.Items[name]
    count = math.floor(tonumber(count) or 0)
    if not def or not def.melt or count < 1 then return { ok = false, msg = 'This cannot be melted.' } end
    if #smelterJobs(citizenid) >= Config.Smelter.maxJobs then return { ok = false, msg = 'The smelter is full. Collect first.' } end
    if not exports.ox_inventory:RemoveItem(src, name, count) then return { ok = false, msg = 'You do not have that many.' } end
    MySQL.insert.await('INSERT INTO mars_pawn_smelter (citizenid, item, count, ready_at) VALUES (?, ?, ?, ?)',
        { citizenid, name, count, os.time() + count * Config.Smelter.secondsPerUnit })
    return { ok = true, msg = ('%d × %s in the furnace.'):format(count, itemLabel(name)), state = buildState(src) }
end)

lib.callback.register('mars_pawn:server:collect', function(src)
    local citizenid = cid(src)
    if not near(src) or not citizenid then return { ok = false, msg = 'You are not at the shop.' } end
    local rows = MySQL.query.await('SELECT * FROM mars_pawn_smelter WHERE citizenid = ? AND ready_at <= ?', { citizenid, os.time() }) or {}
    if #rows == 0 then return { ok = false, msg = 'Nothing is ready yet.' } end
    local got = {}
    for _, r in ipairs(rows) do
        local def = Config.Items[r.item]
        if def and def.melt then
            for reward, per in pairs(def.melt) do
                local amount = per * r.count
                exports.ox_inventory:AddItem(src, reward, amount)
                got[#got + 1] = ('%d × %s'):format(amount, itemLabel(reward))
            end
        end
        MySQL.query('DELETE FROM mars_pawn_smelter WHERE id = ?', { r.id })
    end
    return { ok = true, msg = 'Collected: ' .. table.concat(got, ', '), state = buildState(src) }
end)

-- ─────────────────────────────────────────────────────────────
-- admin
-- ─────────────────────────────────────────────────────────────

local function isAdmin(src) return IsPlayerAceAllowed(src, 'admin') end

lib.callback.register('mars_pawn:admin:data', function(src)
    if not isAdmin(src) then return end
    local items = {}
    for name, def in pairs(Config.Items) do
        local m = marketOf(name)
        items[#items + 1] = { name = name, label = itemLabel(name), min = def.min, max = def.max, saturation = m.saturation, stock = m.stock, hot = hot[name] == true }
    end
    table.sort(items, function(a, b) return a.label < b.label end)
    local settings = {}
    for _, e in ipairs(Config.Editable) do settings[#settings + 1] = { path = e.path, label = e.label, min = e.min, max = e.max, value = Config.GetPath(e.path) } end
    return { items = items, settings = settings }
end)

local function saveSetting(path, value)
    if defaults[path] == nil then defaults[path] = Config.GetPath(path) end
    Config.SetPath(path, value); overrides[path] = value
    MySQL.query('REPLACE INTO mars_pawn_settings (path, value) VALUES (?, ?)', { path, json.encode(value) })
end

lib.callback.register('mars_pawn:admin:set', function(src, path, value)
    if not isAdmin(src) then return false, 'No permission.' end
    value = tonumber(value)
    if not value then return false, 'Enter a number.' end
    for _, e in ipairs(Config.Editable) do
        if e.path == path then
            saveSetting(path, math.min(e.max, math.max(e.min, value)))
            return true, 'Saved.'
        end
    end
    local item, field = path:match('^Items%.([%w_]+)%.(min)$')
    if not item then item, field = path:match('^Items%.([%w_]+)%.(max)$') end
    if item and Config.Items[item] then
        saveSetting(('Items.%s.%s'):format(item, field), math.max(1, math.floor(value)))
        return true, 'Saved.'
    end
    return false, 'This setting cannot be edited.'
end)

lib.callback.register('mars_pawn:admin:action', function(src, action)
    if not isAdmin(src) then return false, 'No permission.' end
    if action == 'resetMarket' then
        for name, m in pairs(market) do m.saturation = 0; saveMarket(name) end
        return true, 'All prices are back to normal.'
    elseif action == 'rotateHot' then
        rotateHot()
        return true, 'New hot items picked.'
    end
    return false, 'Unknown action.'
end)

lib.addCommand('pawnkit', { help = 'Pawn shop: give test items', restricted = 'group.admin' }, function(src)
    for name in pairs(Config.Items) do exports.ox_inventory:AddItem(src, name, 3) end
    getPlayer(src).Functions.AddMoney('cash', 20000, 'pawn-test')
    TriggerClientEvent('ox_lib:notify', src, { title = 'Pawn', description = 'Test items and $20,000 cash given.', type = 'success' })
end)

lib.addCommand('pawnadmin', { help = 'Pawn shop admin panel', restricted = 'group.admin' }, function(src)
    TriggerClientEvent('mars_pawn:client:openAdmin', src)
end)
