fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'mars_chat'
author 'Mars Community 2'
description 'Mars chat: RTL/Persian-friendly chat with roleplay commands (/ooc /me /do /f /w)'
version '1.0.0'

-- other resources talk to "chat" (chat:addMessage, chat:addSuggestion, ...)
provide 'chat'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}

shared_script 'config.lua'
client_script 'client.lua'
server_script 'server.lua'
