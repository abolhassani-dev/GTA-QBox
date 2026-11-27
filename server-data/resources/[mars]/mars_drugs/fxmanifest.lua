fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mars_drugs'
author 'Mars Community 2'
description 'Mars drug system v2: cannabis, mushrooms, coca; quality, effects, in-game admin'
version '2.0.2'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/main.lua',
    'client/effects.lua',
    'client/admin.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
    'server/admin.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'ox_inventory',
    'ox_target',
    'qbx_core',
}
