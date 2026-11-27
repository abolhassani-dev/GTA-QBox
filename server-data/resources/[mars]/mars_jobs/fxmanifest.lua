fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mars_jobs'
author 'Mars Community 2'
description 'Mars jobs: in-game job admin panel (/jobadmin) and legal work jobs'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

client_scripts {
    'client/work.lua',
    'client/admin.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'qbx_core',
}
