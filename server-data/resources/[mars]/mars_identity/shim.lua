--[[
    Mars Community 2 – VMP identity shim
    ------------------------------------
    VMP players usually have no Rockstar license, so qbx_core rejects them with
    "No Valid Rockstar License found". This file is loaded at the very top of
    qbx_core's server scripts (see tools/install.ps1). When a player has no
    'license' / 'license2' identifier, it builds a stable one from another
    identifier (steam, discord, ...) and makes the identifier natives return it.
    Players who DO have a real license are left untouched.

    Convars (server.cfg):
      set mars:identityShim "true"                       -- turn the shim on/off
      set mars:licenseFallback "steam,discord,fivem,xbl,live"  -- priority order
]]

if GetConvar('mars:identityShim', 'true') ~= 'true' then return end

local fallbackOrder = {}
for idType in GetConvar('mars:licenseFallback', 'steam,discord,fivem,xbl,live'):gmatch('[^,%s]+') do
    fallbackOrder[#fallbackOrder + 1] = idType
end

local nativeGetNum = GetNumPlayerIdentifiers
local nativeGetId = GetPlayerIdentifier
local nativeGetByType = GetPlayerIdentifierByType

---@param src string|integer
---@return string[]
local function buildIdentifiers(src)
    local ids = {}
    local byType = {}
    local count = nativeGetNum(src) or 0

    for i = 0, count - 1 do
        local id = nativeGetId(src, i)
        if id then
            ids[#ids + 1] = id
            local idType = id:match('^([^:]+):')
            if idType then byType[idType] = id end
        end
    end

    if byType.license or byType.license2 then return ids end

    for _, idType in ipairs(fallbackOrder) do
        local id = byType[idType]
        if id then
            local synthetic = ('%s_%s'):format(idType, id:sub(#idType + 2))
            ids[#ids + 1] = 'license:' .. synthetic
            ids[#ids + 1] = 'license2:' .. synthetic
            break
        end
    end

    return ids
end

function GetNumPlayerIdentifiers(src)
    return #buildIdentifiers(src)
end

function GetPlayerIdentifier(src, index)
    return buildIdentifiers(src)[(tonumber(index) or 0) + 1]
end

function GetPlayerIdentifiers(src)
    return buildIdentifiers(src)
end

function GetPlayerIdentifierByType(src, idType)
    local real = nativeGetByType(src, idType)
    if real or (idType ~= 'license' and idType ~= 'license2') then return real end

    local prefix = idType .. ':'
    for _, id in ipairs(buildIdentifiers(src)) do
        if id:sub(1, #prefix) == prefix then return id end
    end
end
