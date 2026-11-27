fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mars_pawnshop'
author 'Mars Community 2'
description 'Mars Pawn & Gold: live market prices, haggling, hot items, reputation, buy-back and gold smelting'
version '1.0.0'

ui_page 'html/index.html'
files { 'html/index.html', 'html/style.css', 'html/app.js' }

shared_scripts { '@ox_lib/init.lua', 'config.lua' }
client_script 'client.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', 'server.lua' }

dependencies { 'ox_lib', 'oxmysql', 'ox_inventory', 'ox_target', 'qbx_core' }
