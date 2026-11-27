fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mars_drugs'
author 'Mars Community 2'
description 'Mars drug system – phase 1: weed (seeds, growing, quality, drying, packing, NPC selling)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
    'qbx_core',
}
