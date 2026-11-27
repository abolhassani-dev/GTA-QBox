fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mars_give'
author 'Mars Community 2'
description 'Admin item giver: /give [id] [item name] [amount] or /give for a searchable menu'
version '1.0.0'

shared_script '@ox_lib/init.lua'
client_script 'client.lua'
server_script 'server.lua'
dependencies { 'ox_lib', 'ox_inventory' }
