fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mars_identity'
author 'Mars Community 2'
description 'VMP identity shim: gives players a stable license identifier when VMP provides no Rockstar license'
version '1.0.0'

-- shim.lua is not run by this resource itself; other resources (qbx_core)
-- load it with '@mars_identity/shim.lua' at the top of their server_scripts.
files { 'shim.lua' }
server_script 'status.lua'
