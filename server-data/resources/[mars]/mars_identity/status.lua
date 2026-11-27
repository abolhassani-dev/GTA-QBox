-- Prints every connecting player's raw identifiers and hardware-token count to
-- the server console, so we can see exactly what VMP provides (debug aid).
if GetConvar('mars:logIdentifiers', 'true') ~= 'true' then return end

AddEventHandler('playerConnecting', function(name)
    local src = source
    local ids = {}
    for i = 0, GetNumPlayerIdentifiers(src) - 1 do
        local id = GetPlayerIdentifier(src, i)
        if id then ids[#ids + 1] = id:find('^ip:') and 'ip:<hidden>' or id end
    end
    local tokens = GetNumPlayerTokens and GetNumPlayerTokens(src) or 0
    print(('[mars_identity] %s connecting with: %s | hardware tokens: %d'):format(
        name, #ids > 0 and table.concat(ids, ', ') or 'NO IDENTIFIERS', tokens))
end)
