fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mars_heat'
author 'Mars Community 2'
description 'Heat (how hot the police are on you) and criminal reputation (street, drugs) with perks'
version '1.0.0'

shared_scripts { '@ox_lib/init.lua', 'config.lua' }
client_script 'client.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', 'server.lua' }

ui_page 'html/index.html'
files { 'html/index.html' }

dependencies { 'ox_lib', 'oxmysql', 'qbx_core' }
