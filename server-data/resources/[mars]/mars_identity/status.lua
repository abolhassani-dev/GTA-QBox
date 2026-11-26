-- Prints every connecting player's identifiers to the server console, so we can
-- see exactly what VMP provides (useful while debugging; turn off later).
if GetConvar('mars:logIdentifiers', 'true') ~= 'true' then return end

AddEventHandler('playerConnecting', function(name)
    local src = source
    local ids = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id and not id:find('^ip:') then ids[#ids + 1] = id end
    end
    print(('[mars_identity] %s connecting with: %s'):format(name, #ids > 0 and table.concat(ids, ', ') or 'NO IDENTIFIERS'))
end)
